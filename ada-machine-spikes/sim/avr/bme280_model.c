/* bme280_model.c -- see bme280_model.h */
#include "bme280_model.h"
#include <string.h>

static void le16(uint8_t *p, int v)
{
	p[0] = (uint8_t)(v & 0xFF);
	p[1] = (uint8_t)((v >> 8) & 0xFF);
}

void bme280_init(bme280_model_t *m, uint8_t chip_id)
{
	static const int tp[12] = { 27504, 26435, -1000, 36477, -10685, 3024,
				    2855, 140, -7, 15500, -14600, 6000 };
	memset(m, 0, sizeof *m);
	memset(m->regs, 0, sizeof m->regs);
	m->regs[0xD0] = chip_id;
	for (int i = 0; i < 12; i++)
		le16(&m->regs[0x88 + 2 * i], tp[i]);
	m->regs[0xA1] = 75;                       /* dig_H1 */
	le16(&m->regs[0xE1], 362);                /* dig_H2 */
	m->regs[0xE3] = 0;                        /* dig_H3 */
	m->regs[0xE4] = 333 >> 4;                 /* dig_H4 = E4<<4 | E5[3:0] */
	m->regs[0xE5] = (333 & 0x0F) | ((0 & 0x0F) << 4); /* H5[3:0] in E5[7:4] */
	m->regs[0xE6] = 0;                        /* dig_H5 = E6<<4 | E5[7:4] */
	m->regs[0xE7] = 30;                       /* dig_H6 */
	m->regs[0xF3] = 0x00;                     /* status: never measuring */
	/* data block: adc_P (20 bit, <<4), adc_T (20 bit, <<4), adc_H (16 bit) */
	{
		uint32_t p = 415148u << 4, t = 519888u << 4, h = 25000u;
		m->regs[0xF7] = (uint8_t)(p >> 16);
		m->regs[0xF8] = (uint8_t)(p >> 8);
		m->regs[0xF9] = (uint8_t)p;
		m->regs[0xFA] = (uint8_t)(t >> 16);
		m->regs[0xFB] = (uint8_t)(t >> 8);
		m->regs[0xFC] = (uint8_t)t;
		m->regs[0xFD] = (uint8_t)(h >> 8);
		m->regs[0xFE] = (uint8_t)h;
	}
}

static uint8_t read_reg(bme280_model_t *m, uint8_t a)
{
	if (a == 0xD0) m->n_id_reads++;
	if (a == 0xF7) m->n_data_reads++;
	if (a == 0x88 || a == 0xA1 || a == 0xE1) m->n_calib_reads++;
	return m->regs[a];
}

static void write_reg(bme280_model_t *m, uint8_t a, uint8_t v)
{
	m->n_writes++;
	switch (a) {
	case 0xE0:                 /* reset: only counted, state is kept */
		if (v == 0xB6) m->n_reset++;
		return;
	case 0xF2: case 0xF4: case 0xF5:
		m->regs[a] = v;
		if (a == 0xF4 && (v & 3) != 0) m->n_forced++;
		return;
	default:                   /* read-only / reserved: ignored */
		return;
	}
}

/* --- SPI ---------------------------------------------------------------- */

void bme280_spi_select(bme280_model_t *m, int selected)
{
	m->selected = selected;
	m->first_byte = 1;
	m->expect_data = 0;
}

uint8_t bme280_spi_exchange(bme280_model_t *m, uint8_t mosi)
{
	if (!m->selected)
		return 0xFF;
	if (m->first_byte) {
		m->first_byte = 0;
		m->is_read = (mosi & 0x80) != 0;
		m->ptr = 0x80 | (mosi & 0x7F);   /* all registers live at 0x80..0xFF */
		m->expect_data = 1;       /* write: data follows its address */
		return 0xFF;
	}
	if (m->is_read)
		return read_reg(m, m->ptr++);
	if (m->expect_data) {
		write_reg(m, m->ptr, mosi);
		m->expect_data = 0;
	} else {                          /* next pair: new address, bit 7 clear */
		m->ptr = 0x80 | (mosi & 0x7F);
		m->expect_data = 1;
	}
	return 0xFF;
}

/* --- I2C ---------------------------------------------------------------- */

int bme280_i2c_start(bme280_model_t *m, uint8_t sla_rw)
{
	m->selected = ((sla_rw >> 1) == BME280_I2C_ADDR);
	if (!m->selected)
		return 0;
	m->is_read = sla_rw & 1;
	if (!m->is_read) {
		m->first_byte = 1;        /* register pointer follows */
		m->expect_data = 0;
	}
	return 1;
}

void bme280_i2c_stop(bme280_model_t *m)
{
	m->selected = 0;
}

void bme280_i2c_write(bme280_model_t *m, uint8_t byte)
{
	if (m->first_byte) {
		m->first_byte = 0;
		m->ptr = byte;
		m->expect_data = 1;
	} else if (m->expect_data) {
		write_reg(m, m->ptr, byte);
		m->expect_data = 0;
	} else {
		m->ptr = byte;
		m->expect_data = 1;
	}
}

uint8_t bme280_i2c_read(bme280_model_t *m)
{
	return read_reg(m, m->ptr++);
}
