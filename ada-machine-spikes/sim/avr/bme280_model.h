/* bme280_model.h -- a software BME280 for the simavr harness (one model, both
 * buses; TODO.md #15 Step 3).
 *
 * The model is pure register-file logic with no simavr dependency: the
 * harness feeds it bus events and takes the answers. Two front ends:
 *
 *   SPI (mode 0, CS active low):  the first byte after CS falls is the
 *     register address, bit 7 = read; as on the real chip only the low 7
 *     address bits are sent (0xF7 is addressed as 0x77 for a write, 0xF7 for
 *     a read) and every register lives in 0x80..0xFF. Reads auto-increment the address; the
 *     answer to byte N is available while byte N is clocked, i.e. the answer
 *     to the address byte is garbage (0xFF) and to the next dummy byte the
 *     register itself. Writes (bit 7 = 0) are (address, data) pairs.
 *   I2C (7-bit address 0x76): SLA+W then the register pointer, then (data,
 *     address, data, ...) pairs; SLA+R (also after a repeated start) returns
 *     registers from the pointer, auto-incrementing, wrapping at 0xFF.
 *
 * Register set: chip id 0xD0 (0x60, or a configurable wrong value), reset
 * 0xE0 (accepted, registers are not cleared), ctrl_hum 0xF2, status 0xF3
 * (never "measuring": conversions complete instantly), ctrl_meas 0xF4,
 * config 0xF5, calibration 0x88..0xA1 and 0xE1..0xE7, data 0xF7..0xFE.
 *
 * Fixed sample and calibration -- the same bytes as host_test's Mock_Regmap,
 * which is what the repo's own driver is checked against (host_test prints
 * "PASS  Temperature: ... want 25.08" etc.):
 *   dig_T1..T3 = 27504, 26435, -1000          (BMP280 datasheet 3.12 example)
 *   dig_P1..P9 = 36477, -10685, 3024, 2855, 140, -7, 15500, -14600, 6000
 *   dig_H1..H6 = 75, 362, 0, 333, 0, 30
 *   adc_T = 519888, adc_P = 415148, adc_H = 25000
 * Expected compensated result of the repo's driver (BME280_EXPECT_*):
 *   25.08 degC (log arg 2508 = 0x09CC), 1006.53 hPa, 20.78 %RH.
 */
#ifndef BME280_MODEL_H
#define BME280_MODEL_H

#include <stdint.h>

#define BME280_I2C_ADDR 0x76
#define BME280_GOOD_CHIP_ID 0x60

#define BME280_EXPECT_TEMP_CENTI 2508      /* 25.08 degC */
#define BME280_EXPECT_PRESS_CENTI_HPA 100653 /* 1006.53 hPa */
#define BME280_EXPECT_HUM_CENTI 2078       /* 20.78 %RH */

typedef struct bme280_model {
	uint8_t regs[256];
	/* SPI / I2C transaction state */
	int selected;          /* CS low / addressed */
	int first_byte;        /* next byte is the address/pointer byte */
	int is_read;
	int expect_data;       /* write pairs: next byte is data (else address) */
	uint8_t ptr;
	/* observations, for the harness's sanity checks */
	unsigned n_reset;      /* writes of 0xB6 to 0xE0 */
	unsigned n_forced;     /* ctrl_meas writes with a forced-mode request */
	unsigned n_data_reads; /* reads that touched 0xF7 */
	unsigned n_calib_reads;/* reads that touched 0x88, 0xA1 or 0xE1 */
	unsigned n_id_reads;
	unsigned n_writes;
} bme280_model_t;

void bme280_init(bme280_model_t *m, uint8_t chip_id);

/* SPI */
void bme280_spi_select(bme280_model_t *m, int selected);
uint8_t bme280_spi_exchange(bme280_model_t *m, uint8_t mosi);

/* I2C: bme280_i2c_start returns 1 if the address byte (SLA+R/W) is ours. */
int bme280_i2c_start(bme280_model_t *m, uint8_t sla_rw);
void bme280_i2c_stop(bme280_model_t *m);
void bme280_i2c_write(bme280_model_t *m, uint8_t byte);
uint8_t bme280_i2c_read(bme280_model_t *m);

#endif
