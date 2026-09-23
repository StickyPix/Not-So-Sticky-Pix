#ifndef DEV_CONFIG_H
#define DEV_CONFIG_H

#include <stdbool.h>
#include <stdint.h>
#include <zephyr/device.h>

typedef uint8_t UBYTE;
typedef uint16_t UWORD;
typedef uint32_t UDOUBLE;

enum dev_gpio_pin {
  DEV_PIN_DC = 0,
  DEV_PIN_CS,
  DEV_PIN_RST,
  DEV_PIN_PWR,
};

#define EPD_DC_PIN DEV_PIN_DC
#define EPD_CS_PIN DEV_PIN_CS
#define EPD_RST_PIN DEV_PIN_RST
#define EPD_PWR_PIN DEV_PIN_PWR

#define GPIO_PIN_SET 1
#define GPIO_PIN_RESET 0

int DEV_Module_Init(const struct device *spi_dev, const struct device *gpio_dev);
void DEV_GPIO_Init(void);
void DEV_SPI_Init(void);
int DEV_Digital_Write(uint8_t pin, uint8_t value);
int DEV_Digital_Read(uint8_t pin);
void DEV_Delay_ms(uint32_t xms);
int DEV_SPI_WriteByte(uint8_t data);
int DEV_SPI_Write_nByte(const uint8_t *data, uint32_t len);
void DEV_Module_Exit(void);

#endif
