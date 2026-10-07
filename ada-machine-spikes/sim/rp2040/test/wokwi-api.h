/* Host-side stub of the parts of Wokwi's wokwi-api.h that bme280-chip.c uses,
 * for test_bme280_chip.c. i2c_init and attr_init record what the chip
 * registers; the test then drives the callbacks like Wokwi's I2C master. */
#ifndef STUB_WOKWI_API_H
#define STUB_WOKWI_API_H
#include <stdbool.h>
#include <stdint.h>

typedef int32_t pin_t;
enum { INPUT = 0, OUTPUT = 1, INPUT_PULLUP = 2 };

typedef struct {
  void *user_data;
  uint32_t address;
  pin_t scl;
  pin_t sda;
  bool (*connect)(void *user_data, uint32_t address, bool read);
  uint8_t (*read)(void *user_data);
  bool (*write)(void *user_data, uint8_t data);
  void (*disconnect)(void *user_data);
  uint32_t reserved[8];
} i2c_config_t;
typedef uint32_t i2c_dev_t;

pin_t pin_init(const char *name, uint32_t mode);
uint32_t attr_init(const char *name, uint32_t default_value);
uint32_t attr_read(uint32_t attr_id);
i2c_dev_t i2c_init(const i2c_config_t *config);
void chip_init(void);
#endif
