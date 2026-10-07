/* avr_harness.c -- run a spike2_avr test-mode ELF in simavr against a
 * simulated BME280 and report the on-target verdict (TODO.md #15 Step 3).
 *
 *   avr_harness [options] <elf>
 *     --bus spi|i2c      which bus the BME280 model is attached to (spi)
 *     --chip-id N        value of register 0xD0 (0x60 = good sensor)
 *     --out FILE         write the raw USART0 TX bytes here
 *     --freq HZ          CPU clock (16000000, atmega328p_hal's F_CPU)
 *     --max-cycles N     simulated-cycle budget (default 10 s of CPU time)
 *     --simavr-twint     I2C only: keep simavr's own TWINT behaviour. By
 *                        default TWINT is cleared when software writes 1 to
 *                        it, as on the silicon (simavr keeps it set, which
 *                        makes a polling driver read stale TWSR)
 *     --diag-spif-in-isr, --diag-twint-after-stop
 *                        diagnostics for the findings in TODO.md #15; they
 *                        change the hardware model, never use them for CI
 *     -v                 verbose (simavr log level + bus trace)
 *
 * Wiring (spike2_avr, read from src/{spi,i2c}/avr_board.ad[sb]):
 *   SPI: ATmega328P SPI0 master, mode 0, MSB first; chip select PB2
 *        (ATmega328P.GPIO pin 2 = PORTB bit 2), active low.
 *   I2C: TWI0 master, 100 kHz, device address 0x76.
 *   USART0 (9600 baud) carries the binary log events and the ASCII verdict
 *   line `ADA-MACHINE-TEST: PASS|FAIL <code>` + CR LF.
 *
 * Exit status: 0 PASS verdict, 1 FAIL verdict, 2 no complete verdict,
 *   3 PASS but the BME280 model did not see the traffic a real run implies
 *   (reset, calibration, 3 forced measurements with data reads).
 * The verdict line is printed on stdout as `VERDICT: <text>`; the end of
 * the run as `END: halted|budget|crashed ...` on stderr.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#include "sim_avr.h"
#include "sim_elf.h"
#include "sim_irq.h"
#include "avr_ioport.h"
#include "avr_spi.h"
#include "avr_twi.h"
#include "avr_uart.h"

#include "bme280_model.h"

#define CS_PORT 'B'
#define CS_PIN 2

static bme280_model_t model;
static int verbose;

static uint8_t cap[1 << 16];
static size_t cap_len;

/* ---- verdict extraction ------------------------------------------------ */

static const char verdict_tag[] = "ADA-MACHINE-TEST: ";

/* Copy the last complete verdict line (without CR LF) into out; return 1. */
static int find_verdict(char *out, size_t outsz)
{
	size_t tl = sizeof verdict_tag - 1;
	int found = 0;
	for (size_t i = 0; i + tl <= cap_len; i++) {
		if (memcmp(cap + i, verdict_tag, tl) != 0)
			continue;
		for (size_t j = i; j + 1 < cap_len; j++) {
			if (cap[j] == '\r' && cap[j + 1] == '\n') {
				size_t n = j - i;
				if (n >= outsz) n = outsz - 1;
				memcpy(out, cap + i, n);
				out[n] = 0;
				found = 1;
				break;
			}
		}
	}
	return found;
}

/* ---- USART0 ------------------------------------------------------------ */

static void uart_out(avr_irq_t *irq, uint32_t value, void *param)
{
	(void)irq; (void)param;
	if (cap_len < sizeof cap)
		cap[cap_len++] = (uint8_t)value;
}

/* ---- SPI model attachment ---------------------------------------------- */

static avr_t *g_avr;

static void cs_notify(avr_irq_t *irq, uint32_t value, void *param)
{
	(void)irq; (void)param;
	/* active low: selected while the pin reads 0 */
	if (verbose) fprintf(stderr, "[spi] CS %s\n", value ? "high" : "low");
	bme280_spi_select(&model, value == 0);
}

static void spi_out(avr_irq_t *irq, uint32_t value, void *param)
{
	(void)irq; (void)param;
	uint8_t miso = bme280_spi_exchange(&model, (uint8_t)value);
	if (verbose)
		fprintf(stderr, "[spi] mosi %02x miso %02x\n", (unsigned)(value & 0xFF), miso);
	/* The reply is delivered while the byte is clocked: the master model
	 * latches it into SPDR and raises SPIF. */
	avr_raise_irq(avr_io_getirq(g_avr, AVR_IOCTL_SPI_GETIRQ(0), SPI_IRQ_INPUT), miso);
}

/* ---- TWI model attachment ---------------------------------------------- */

static void twi_reply(uint8_t msg, uint8_t addr, uint8_t data)
{
	avr_raise_irq(avr_io_getirq(g_avr, AVR_IOCTL_TWI_GETIRQ(0), TWI_IRQ_INPUT),
		      avr_twi_irq_msg(msg, addr, data));
}

static void twi_out(avr_irq_t *irq, uint32_t value, void *param)
{
	avr_twi_msg_irq_t v;
	(void)irq; (void)param;
	v.u.v = value;
	uint8_t msg = v.u.twi.msg, addr = v.u.twi.addr, data = v.u.twi.data;

	if (verbose)
		fprintf(stderr, "[twi] msg %02x addr %02x data %02x\n", msg, addr, data);

	if (msg & TWI_COND_STOP)
		bme280_i2c_stop(&model);
	if (msg & TWI_COND_START) {
		/* addr is SLA+R/W as written to TWDR; no reply = NACK */
		if (bme280_i2c_start(&model, addr))
			twi_reply(TWI_COND_ACK, addr, 1);
		return;
	}
	if (!model.selected)
		return;
	if (msg & TWI_COND_WRITE) {
		bme280_i2c_write(&model, data);
		twi_reply(TWI_COND_ACK, addr, 1);
	}
	if (msg & TWI_COND_READ)
		twi_reply(TWI_COND_READ, addr, bme280_i2c_read(&model));
}

/* simavr's TWI model keeps TWINT (raise_sticky) set after software writes 1
 * to it, whereas the ATmega328P clears it (and the operation starts). A
 * polling driver then reads stale status. This hook, installed after the
 * TWI's own TWCR handler, clears TWINT on a write of 1. */
static int twint_fix = 1, diag_twint_after_stop, diag_spif_in_isr;
static void twcr_post_write(avr_t *avr, avr_io_addr_t addr, uint8_t v, void *param)
{
	(void)addr; (void)param;
	if ((v & 0x80) && (v & 0x04)) {          /* TWINT=1 written, TWEN=1 */
		avr_regbit_t twint = { .reg = 0xBC, .bit = 7, .mask = 1 };
		avr_regbit_clear(avr, twint);
		/* DIAGNOSTIC ONLY (never used by `make run`): pretend a STOP sets
		 * TWINT, which the ATmega328P datasheet says it does not. */
		if (diag_twint_after_stop && (v & 0x10))
			avr_regbit_set(avr, twint);
	}
}

/* DIAGNOSTIC ONLY: the silicon (and simavr) clears SPIF when the SPI
 * interrupt vector is taken. Make SPSR read back with SPIF set while the SPI
 * ISR runs, so a Can_Pop that tests SPIF inside the ISR sees it. */
static int in_spi_isr;
static void spi_isr_state(avr_irq_t *irq, uint32_t value, void *param)
{
	(void)irq; (void)param;
	in_spi_isr = value != 0;
}
static uint8_t spsr_read(avr_t *avr, avr_io_addr_t addr, void *param)
{
	(void)param;
	return avr->data[addr] | (in_spi_isr ? 0x80 : 0);
}

static void dbg_w(avr_t *avr, avr_io_addr_t addr, uint8_t v, void *param)
{
	(void)param;
	fprintf(stderr, "[io] cyc %llu pc %x write %04x = %02x\n",
		(unsigned long long)avr->cycle, (unsigned)avr->pc, (unsigned)addr, v);
}
static void dbg_int(avr_irq_t *irq, uint32_t value, void *param)
{
	fprintf(stderr, "[int] %s = %u\n", (const char *)param, value);
	(void)irq;
}

/* ---- main -------------------------------------------------------------- */

static void no_sleep(avr_t *avr, avr_cycle_count_t how_long)
{
	(void)avr; (void)how_long;   /* run as fast as possible, not in real time */
}

static void usage(void)
{
	fprintf(stderr, "usage: avr_harness [--bus spi|i2c] [--chip-id N] [--out FILE]"
			" [--freq HZ] [--max-cycles N] [-v] <elf>\n");
	exit(64);
}

int main(int argc, char **argv)
{
	const char *bus = "spi", *out = NULL, *elf = NULL;
	unsigned long chip_id = BME280_GOOD_CHIP_ID, freq = 16000000UL;
	unsigned long long max_cycles = 0;

	for (int i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "--bus") && i + 1 < argc) bus = argv[++i];
		else if (!strcmp(argv[i], "--chip-id") && i + 1 < argc) chip_id = strtoul(argv[++i], NULL, 0);
		else if (!strcmp(argv[i], "--out") && i + 1 < argc) out = argv[++i];
		else if (!strcmp(argv[i], "--freq") && i + 1 < argc) freq = strtoul(argv[++i], NULL, 0);
		else if (!strcmp(argv[i], "--max-cycles") && i + 1 < argc) max_cycles = strtoull(argv[++i], NULL, 0);
		else if (!strcmp(argv[i], "--simavr-twint")) twint_fix = 0;
		else if (!strcmp(argv[i], "--diag-twint-after-stop")) twint_fix = diag_twint_after_stop = 1;
		else if (!strcmp(argv[i], "--diag-spif-in-isr")) diag_spif_in_isr = 1;
		else if (!strcmp(argv[i], "-v")) verbose = 1;
		else if (argv[i][0] == '-') usage();
		else elf = argv[i];
	}
	if (!elf || (strcmp(bus, "spi") && strcmp(bus, "i2c")))
		usage();
	if (!max_cycles)
		max_cycles = 10ULL * freq;
	int spi = !strcmp(bus, "spi");

	elf_firmware_t fw;
	memset(&fw, 0, sizeof fw);
	if (elf_read_firmware(elf, &fw) != 0) {
		fprintf(stderr, "avr_harness: cannot load ELF %s\n", elf);
		return 64;
	}
	strcpy(fw.mmcu, "atmega328p");   /* the ELFs carry no .mmcu section */
	fw.frequency = freq;

	avr_t *avr = avr_make_mcu_by_name(fw.mmcu);
	if (!avr) {
		fprintf(stderr, "avr_harness: simavr has no core %s\n", fw.mmcu);
		return 64;
	}
	g_avr = avr;
	avr_init(avr);
	avr_load_firmware(avr, &fw);
	avr->frequency = freq;
	avr->log = verbose ? LOG_TRACE : LOG_ERROR;
	avr->sleep = no_sleep;

	/* USART0: capture TX bytes; switch off simavr's own line-buffered
	 * stdout echo so the binary log does not leak into CI output. */
	uint32_t flags = 0;
	avr_ioctl(avr, AVR_IOCTL_UART_GET_FLAGS('0'), &flags);
	flags &= ~AVR_UART_FLAG_STDIO;
	avr_ioctl(avr, AVR_IOCTL_UART_SET_FLAGS('0'), &flags);
	avr_irq_register_notify(avr_io_getirq(avr, AVR_IOCTL_UART_GETIRQ('0'), UART_IRQ_OUTPUT),
				uart_out, NULL);

	bme280_init(&model, (uint8_t)chip_id);
	if (spi) {
		avr_irq_register_notify(avr_io_getirq(avr, AVR_IOCTL_IOPORT_GETIRQ(CS_PORT), CS_PIN),
					cs_notify, NULL);
		avr_irq_register_notify(avr_io_getirq(avr, AVR_IOCTL_SPI_GETIRQ(0), SPI_IRQ_OUTPUT),
					spi_out, NULL);
	} else {
		avr_irq_register_notify(avr_io_getirq(avr, AVR_IOCTL_TWI_GETIRQ(0), TWI_IRQ_OUTPUT),
					twi_out, NULL);
		if (twint_fix)
			avr_register_io_write(avr, 0xBC, twcr_post_write, NULL);
	}

	if (diag_spif_in_isr && spi) {
		avr_irq_register_notify(avr_get_interrupt_irq(avr, 17) + AVR_INT_IRQ_RUNNING,
					spi_isr_state, NULL);
		avr_register_io_read(avr, 0x4D, spsr_read, NULL);
	}
	if (verbose && spi) {
		avr_register_io_write(avr, 0x4E, dbg_w, NULL);
		avr_irq_t *pi = avr_get_interrupt_irq(avr, 17);
		avr_irq_register_notify(pi + AVR_INT_IRQ_PENDING, dbg_int, "spi pending");
		avr_irq_register_notify(pi + AVR_INT_IRQ_RUNNING, dbg_int, "spi running");
	}

	/* Run until the CPU halts (sleep with the I flag clear: simavr then
	 * enters cpu_Done), crashes, or the budget is spent. Once a verdict is
	 * on the wire, allow a short grace period for the halt. */
	const char *end = "budget";
	int state = cpu_Running, have_verdict = 0;
	char verdict[96] = "";
	unsigned long long grace_end = 0;
	while (avr->cycle < max_cycles) {
		state = avr_run(avr);
		if (state == cpu_Done) { end = "halted"; break; }
		if (state == cpu_Crashed) { end = "crashed"; break; }
		if (!have_verdict && cap_len >= sizeof verdict_tag &&
		    (cap[cap_len - 1] == '\n') && find_verdict(verdict, sizeof verdict)) {
			have_verdict = 1;
			grace_end = avr->cycle + freq / 10;
		}
		if (have_verdict && avr->cycle > grace_end) { end = "verdict-no-halt"; break; }
	}
	if (!have_verdict)
		have_verdict = find_verdict(verdict, sizeof verdict);

	if (out) {
		FILE *f = fopen(out, "wb");
		if (!f || fwrite(cap, 1, cap_len, f) != cap_len) {
			fprintf(stderr, "avr_harness: cannot write %s\n", out);
			return 64;
		}
		fclose(f);
	}

	fprintf(stderr, "END: %s after %llu cycles (%.3f s simulated), %zu USART0 bytes, pc=0x%x\n",
		end, (unsigned long long)avr->cycle, (double)avr->cycle / freq, cap_len,
		(unsigned)avr->pc);
	if (verbose)
		fprintf(stderr, "CPU: state=%d I=%d SPCR=%02x SPSR=%02x TWCR=%02x TWSR=%02x SMCR=%02x\n",
			avr->state, avr->sreg[S_I], avr->data[0x4C], avr->data[0x4D],
			avr->data[0xBC], avr->data[0xB9], avr->data[0x53]);
	fprintf(stderr, "MODEL: bus=%s chip_id=0x%02lx id_reads=%u resets=%u calib_reads=%u "
			"forced=%u data_reads=%u writes=%u\n",
		bus, chip_id, model.n_id_reads, model.n_reset, model.n_calib_reads,
		model.n_forced, model.n_data_reads, model.n_writes);

	if (!have_verdict) {
		printf("VERDICT: (none)\n");
		return 2;
	}
	printf("VERDICT: %s\n", verdict + sizeof verdict_tag - 1);
	if (strcmp(verdict + sizeof verdict_tag - 1, "PASS") != 0)
		return 1;
	/* A PASS must come with the traffic a real run implies. */
	if (model.n_reset < 1 || model.n_calib_reads < 3 || model.n_forced < 3 ||
	    model.n_data_reads < 3) {
		fprintf(stderr, "avr_harness: PASS verdict but the model saw too little traffic\n");
		return 3;
	}
	return 0;
}
