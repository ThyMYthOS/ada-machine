/* Host unit test of bme280-chip.c's register logic (no Wokwi needed).
 * Includes the chip source directly (compiled from a copy in a directory
 * without the fetched wokwi-api.h, see the Makefile) against a stub API,
 * captures the i2c_config_t the chip registers, and drives its callbacks the
 * way an I2C master would: pointer write, repeated start, burst reads,
 * register writes, a foreign address, and the chipId attribute. Also checks
 * the bytes against sim/avr's model constants (calibration, raw sample, ids).
 */
#include "bme280-chip.c"

static i2c_config_t cfg;
static uint32_t attr_value = BME280_GOOD_CHIP_ID; /* what diagram.json says */
static int attr_name_ok;
static int pins_seen;

pin_t pin_init(const char *name, uint32_t mode) {
  if (mode == INPUT_PULLUP && (!strcmp(name, "SCL") || !strcmp(name, "SDA")))
    pins_seen++;
  return pins_seen;
}
uint32_t attr_init(const char *name, uint32_t def) {
  attr_name_ok = !strcmp(name, "chipId") && def == BME280_GOOD_CHIP_ID;
  return 1;
}
uint32_t attr_read(uint32_t id) { (void)id; return attr_value; }
i2c_dev_t i2c_init(const i2c_config_t *c) { cfg = *c; return 1; }

static int failures, checks;
#define CHECK(cond, ...)                                                       \
  do {                                                                         \
    checks++;                                                                  \
    if (!(cond)) {                                                             \
      failures++;                                                              \
      printf("FAIL  %s:%d: ", __FILE__, __LINE__);                             \
      printf(__VA_ARGS__);                                                     \
      printf("\n");                                                            \
    }                                                                          \
  } while (0)

/* Master-side helpers over the registered callbacks. */
static bool m_start(bool read) { return cfg.connect(cfg.user_data, 0x76, read); }
static void m_stop(void) { cfg.disconnect(cfg.user_data); }
static void m_set_ptr(uint8_t r) {
  CHECK(m_start(false), "SLA+W NACKed");
  CHECK(cfg.write(cfg.user_data, r), "pointer byte NACKed");
}
static void m_read(uint8_t r, uint8_t *out, int n) {
  m_set_ptr(r);
  CHECK(m_start(true), "repeated start SLA+R NACKed"); /* no stop in between */
  for (int i = 0; i < n; i++)
    out[i] = cfg.read(cfg.user_data);
  m_stop();
}
static void m_write(uint8_t r, uint8_t v) {
  m_set_ptr(r);
  CHECK(cfg.write(cfg.user_data, v), "data byte NACKed");
  m_stop();
}
static uint8_t rd1(uint8_t r) { uint8_t v; m_read(r, &v, 1); return v; }

static int16_t s16(const uint8_t *p) { return (int16_t)(p[0] | (p[1] << 8)); }
static uint16_t u16(const uint8_t *p) { return (uint16_t)(p[0] | (p[1] << 8)); }

static void test_with_id(uint32_t id) {
  attr_value = id;
  pins_seen = 0;
  chip_init();
  CHECK(attr_name_ok, "attr_init(\"chipId\", 0x60) not called as expected");
  CHECK(pins_seen == 2, "SCL and SDA not both INPUT_PULLUP (%d)", pins_seen);
  CHECK(cfg.address == 0x76, "address 0x%02x", (unsigned)cfg.address);
  CHECK(cfg.connect && cfg.read && cfg.write && cfg.disconnect, "callbacks");
  CHECK(rd1(0xD0) == (uint8_t)id, "chip id 0x%02x, want 0x%02x", rd1(0xD0),
        (unsigned)id);
}

int main(void) {
  uint8_t b[32];

  /* Good chip. */
  test_with_id(0x60);

  /* Calibration block 0x88..0xA1: dig_T1..T3, dig_P1..P9, (0xA0 unused), H1 */
  m_read(0x88, b, 26);
  CHECK(u16(&b[0]) == 27504, "dig_T1 %u", u16(&b[0]));
  CHECK(s16(&b[2]) == 26435, "dig_T2 %d", s16(&b[2]));
  CHECK(s16(&b[4]) == -1000, "dig_T3 %d", s16(&b[4]));
  CHECK(u16(&b[6]) == 36477, "dig_P1 %u", u16(&b[6]));
  CHECK(s16(&b[8]) == -10685, "dig_P2 %d", s16(&b[8]));
  CHECK(s16(&b[10]) == 3024, "dig_P3 %d", s16(&b[10]));
  CHECK(s16(&b[12]) == 2855, "dig_P4 %d", s16(&b[12]));
  CHECK(s16(&b[14]) == 140, "dig_P5 %d", s16(&b[14]));
  CHECK(s16(&b[16]) == -7, "dig_P6 %d", s16(&b[16]));
  CHECK(s16(&b[18]) == 15500, "dig_P7 %d", s16(&b[18]));
  CHECK(s16(&b[20]) == -14600, "dig_P8 %d", s16(&b[20]));
  CHECK(s16(&b[22]) == 6000, "dig_P9 %d", s16(&b[22]));
  CHECK(b[24] == 0 && b[25] == 75, "0xA0 %u, dig_H1 %u", b[24], b[25]);

  /* Humidity calibration 0xE1..0xE7 */
  m_read(0xE1, b, 7);
  CHECK(s16(&b[0]) == 362, "dig_H2 %d", s16(&b[0]));
  CHECK(b[2] == 0, "dig_H3 %u", b[2]);
  CHECK((int)((b[3] << 4) | (b[4] & 0x0F)) == 333, "dig_H4");
  CHECK((int)((b[5] << 4) | (b[4] >> 4)) == 0, "dig_H5");
  CHECK(b[6] == 30, "dig_H6 %u", b[6]);

  /* Data block 0xF7..0xFE in one burst: adc_P, adc_T (20 bit, <<4), adc_H */
  m_read(0xF7, b, 8);
  CHECK((((uint32_t)b[0] << 12) | (b[1] << 4) | (b[2] >> 4)) == 415148,
        "adc_P");
  CHECK((((uint32_t)b[3] << 12) | (b[4] << 4) | (b[5] >> 4)) == 519888,
        "adc_T");
  CHECK((unsigned)((b[6] << 8) | b[7]) == 25000, "adc_H");

  /* Status never busy, also directly after a forced-mode write. */
  CHECK(rd1(0xF3) == 0x00, "status before");
  m_write(0xF2, 0x01);
  m_write(0xF5, 0xA0);
  m_write(0xF4, 0x25);
  CHECK(rd1(0xF2) == 0x01 && rd1(0xF5) == 0xA0 && rd1(0xF4) == 0x25,
        "ctrl writes not stored");
  CHECK(rd1(0xF3) == 0x00, "status after forced write");

  /* Reset (0xE0) is accepted; state is kept. */
  m_write(0xE0, 0xB6);
  CHECK(rd1(0xD0) == 0x60 && rd1(0xF4) == 0x25, "state after reset");
  /* Read-only registers and reserved space ignore writes. */
  m_write(0xD0, 0x12);
  m_write(0xF7, 0x12);
  m_write(0x88, 0x12);
  CHECK(rd1(0xD0) == 0x60 && rd1(0xF7) == 0x65 && rd1(0x88) == (27504 & 0xFF),
        "read-only register changed");

  /* Write pairs in one transaction: ptr, data, addr, data. */
  CHECK(m_start(false), "SLA+W");
  cfg.write(cfg.user_data, 0xF2);
  cfg.write(cfg.user_data, 0x03);
  cfg.write(cfg.user_data, 0xF5);
  cfg.write(cfg.user_data, 0x10);
  m_stop();
  CHECK(rd1(0xF2) == 0x03 && rd1(0xF5) == 0x10, "write pairs");

  /* Auto-increment wraps at 0xFF. */
  m_read(0xFE, b, 3);
  CHECK(b[0] == (25000 & 0xFF) && b[1] == 0x00 && b[2] == 0x00,
        "wrap: %02x %02x %02x", b[0], b[1], b[2]);

  /* A foreign address is not ours (Wokwi filters on cfg.address already; the
   * chip NACKs too, as the AVR model does). */
  CHECK(!cfg.connect(cfg.user_data, 0x77, false), "0x77 ACKed");

  /* Wrong-chip-id variant: attribute 88 = 0x58 (a BMP280). */
  test_with_id(0x58);
  m_read(0x88, b, 2);
  CHECK(u16(&b[0]) == 27504, "calibration with wrong id still served");

  printf("%s: %d checks, %d failed\n", failures ? "FAIL" : "PASS", checks,
         failures);
  return failures != 0;
}
