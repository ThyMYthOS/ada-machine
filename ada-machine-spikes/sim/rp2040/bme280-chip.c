/* bme280-chip.c -- a BME280 I2C slave as a Wokwi custom chip (WASM), for the
 * RP2040 simulation of spike1_pico (TODO.md #15 Step 3).
 *
 * Register-for-register the same model as ../avr/bme280_model.c (see
 * ../avr/bme280_model.h for the full description): 7-bit address 0x76,
 * register-pointer write, repeated start, auto-incrementing reads wrapping at
 * 0xFF, (data, address, data, ...) write pairs, writes honoured only for
 * ctrl_hum 0xF2 / ctrl_meas 0xF4 / config 0xF5 (0xE0 reset is counted and
 * ignored: state is kept), status 0xF3 never "measuring", and the fixed
 * calibration and raw sample of host_test's Mock_Regmap, which the repo's
 * driver compensates to 25.08 degC, 1006.53 hPa, 20.78 %RH.
 *
 * The chip id register 0xD0 comes from the integer attribute "chipId"
 * (diagram.json: "attrs": { "chipId": "88" }; default 96 = 0x60, the BME280;
 * 88 = 0x58 is what a real BMP280 answers, the wrong-chip-id case).
 *
 * Build: `make chip` in this directory (wokwi-cli chip compile). The same
 * file is compiled for the host by test/test_bme280_chip.c, with a stub
 * wokwi-api.h, to unit-test the register logic.
 */
#include "wokwi-api.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define BME280_I2C_ADDR 0x76
#define BME280_GOOD_CHIP_ID 0x60

typedef struct {
  uint8_t regs[256];
  int selected;     /* addressed by the current transaction */
  int first_byte;   /* next written byte is the register pointer */
  int is_read;
  int expect_data;  /* write pairs: next byte is data (else address) */
  uint8_t ptr;
} chip_state_t;

static void le16(uint8_t *p, int v) {
  p[0] = (uint8_t)(v & 0xFF);
  p[1] = (uint8_t)((v >> 8) & 0xFF);
}

static void regs_init(chip_state_t *c, uint8_t chip_id) {
  /* dig_T1..T3, dig_P1..P9 (BMP280 datasheet 3.12 example values) */
  static const int tp[12] = {27504, 26435, -1000, 36477, -10685, 3024,
                             2855,  140,   -7,    15500, -14600, 6000};
  memset(c, 0, sizeof *c);
  c->regs[0xD0] = chip_id;
  for (int i = 0; i < 12; i++)
    le16(&c->regs[0x88 + 2 * i], tp[i]);
  c->regs[0xA1] = 75;               /* dig_H1 */
  le16(&c->regs[0xE1], 362);        /* dig_H2 */
  c->regs[0xE3] = 0;                /* dig_H3 */
  c->regs[0xE4] = 333 >> 4;         /* dig_H4 = E4<<4 | E5[3:0] */
  c->regs[0xE5] = 333 & 0x0F;       /* H5[3:0] (= 0) in E5[7:4] */
  c->regs[0xE6] = 0;                /* dig_H5 = E6<<4 | E5[7:4] */
  c->regs[0xE7] = 30;               /* dig_H6 */
  c->regs[0xF3] = 0x00;             /* status: never measuring */
  {
    /* adc_P (20 bit, <<4), adc_T (20 bit, <<4), adc_H (16 bit) */
    uint32_t p = 415148u << 4, t = 519888u << 4, h = 25000u;
    c->regs[0xF7] = (uint8_t)(p >> 16);
    c->regs[0xF8] = (uint8_t)(p >> 8);
    c->regs[0xF9] = (uint8_t)p;
    c->regs[0xFA] = (uint8_t)(t >> 16);
    c->regs[0xFB] = (uint8_t)(t >> 8);
    c->regs[0xFC] = (uint8_t)t;
    c->regs[0xFD] = (uint8_t)(h >> 8);
    c->regs[0xFE] = (uint8_t)h;
  }
}

static void write_reg(chip_state_t *c, uint8_t a, uint8_t v) {
  switch (a) {
  case 0xF2: case 0xF4: case 0xF5:
    c->regs[a] = v;
    return;
  default: /* 0xE0 reset (state kept), read-only and reserved: ignored */
    return;
  }
}

static bool on_i2c_connect(void *user_data, uint32_t address, bool read) {
  chip_state_t *c = user_data;
  c->selected = (address == BME280_I2C_ADDR);
  if (!c->selected)
    return false;
  c->is_read = read;
  if (!read) {
    c->first_byte = 1; /* register pointer follows */
    c->expect_data = 0;
  }
  return true;
}

static bool on_i2c_write(void *user_data, uint8_t byte) {
  chip_state_t *c = user_data;
  if (c->first_byte) {
    c->first_byte = 0;
    c->ptr = byte;
    c->expect_data = 1;
  } else if (c->expect_data) {
    write_reg(c, c->ptr, byte);
    c->expect_data = 0;
  } else {
    c->ptr = byte;
    c->expect_data = 1;
  }
  return true;
}

static uint8_t on_i2c_read(void *user_data) {
  chip_state_t *c = user_data;
  return c->regs[c->ptr++];
}

static void on_i2c_disconnect(void *user_data) {
  chip_state_t *c = user_data;
  c->selected = 0;
}

void chip_init(void) {
  chip_state_t *c = malloc(sizeof(chip_state_t));
  uint32_t id_attr = attr_init("chipId", BME280_GOOD_CHIP_ID);
  uint8_t chip_id = (uint8_t)attr_read(id_attr);
  regs_init(c, chip_id);

  static i2c_config_t i2c;
  i2c = (i2c_config_t){
      .address = BME280_I2C_ADDR,
      .scl = pin_init("SCL", INPUT_PULLUP),
      .sda = pin_init("SDA", INPUT_PULLUP),
      .connect = on_i2c_connect,
      .read = on_i2c_read,
      .write = on_i2c_write,
      .disconnect = on_i2c_disconnect,
      .user_data = c,
  };
  i2c_init(&i2c);
  printf("BME280 model ready, address 0x%02x, chip id 0x%02x\n",
         BME280_I2C_ADDR, chip_id);
}
