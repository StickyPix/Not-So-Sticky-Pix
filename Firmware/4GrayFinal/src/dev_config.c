#include "dev_config.h"

#include <zephyr/devicetree.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/drivers/spi.h>
#include <zephyr/kernel.h>
#include <zephyr/sys/util.h>

#define EPD_NODE DT_PATH(zephyr_user)

BUILD_ASSERT(DT_NODE_EXISTS(EPD_NODE), "zephyr,user node is required");
BUILD_ASSERT(DT_PROP_LEN(EPD_NODE, epd_gpios) >= 3,
             "zephyr,user must define dc/cs/rst in epd-gpios");

static const struct gpio_dt_spec epd_dc =
    GPIO_DT_SPEC_GET_BY_IDX(EPD_NODE, epd_gpios, 0);
static const struct gpio_dt_spec epd_cs =
    GPIO_DT_SPEC_GET_BY_IDX(EPD_NODE, epd_gpios, 1);
static const struct gpio_dt_spec epd_rst =
    GPIO_DT_SPEC_GET_BY_IDX(EPD_NODE, epd_gpios, 2);

#if DT_NODE_HAS_PROP(EPD_NODE, epd_power_gpios)
static const struct gpio_dt_spec epd_power =
    GPIO_DT_SPEC_GET(EPD_NODE, epd_power_gpios);
#define DEV_CONFIG_HAS_POWER 1
#else
#define DEV_CONFIG_HAS_POWER 0
#endif

static const struct device *epd_spi_dev;

static const struct spi_config epd_spi_cfg = {
    .frequency = 4000000U,
    .operation = SPI_OP_MODE_MASTER | SPI_WORD_SET(8) | SPI_TRANSFER_MSB,
    .slave = 0U,
    .cs = {
        .gpio = { 0 },
        .delay = 0U,
    },
};

static const struct gpio_dt_spec *dev_lookup_gpio(uint8_t pin) {
  switch (pin) {
  case DEV_PIN_DC:
    return &epd_dc;
  case DEV_PIN_CS:
    return &epd_cs;
  case DEV_PIN_RST:
    return &epd_rst;
#if DEV_CONFIG_HAS_POWER
  case DEV_PIN_PWR:
    return &epd_power;
#endif
  default:
    return NULL;
  }
}

static int dev_configure_output(const struct gpio_dt_spec *spec, int value) {
  int ret;

  if (!spec || !device_is_ready(spec->port)) {
    return -ENODEV;
  }

  ret = gpio_pin_configure_dt(spec, GPIO_OUTPUT);
  if (ret != 0) {
    return ret;
  }

  return gpio_pin_set_raw(spec->port, spec->pin, value);
}

int DEV_Module_Init(const struct device *spi_dev, const struct device *gpio_dev) {
  int ret;

  ARG_UNUSED(gpio_dev);

  epd_spi_dev = spi_dev;
  if (!epd_spi_dev || !device_is_ready(epd_spi_dev)) {
    return -ENODEV;
  }

  ret = dev_configure_output(&epd_cs, 1);
  if (ret != 0) {
    return ret;
  }

  ret = dev_configure_output(&epd_dc, 0);
  if (ret != 0) {
    return ret;
  }

  ret = dev_configure_output(&epd_rst, 1);
  if (ret != 0) {
    return ret;
  }

#if DEV_CONFIG_HAS_POWER
  ret = dev_configure_output(&epd_power, 1);
  if (ret != 0) {
    return ret;
  }
#endif

  return 0;
}

void DEV_GPIO_Init(void) {}

void DEV_SPI_Init(void) {}

int DEV_Digital_Write(uint8_t pin, uint8_t value) {
  const struct gpio_dt_spec *spec = dev_lookup_gpio(pin);

  if (!spec) {
    return -ENOTSUP;
  }

  return gpio_pin_set_raw(spec->port, spec->pin, value);
}

int DEV_Digital_Read(uint8_t pin) {
  const struct gpio_dt_spec *spec = dev_lookup_gpio(pin);

  if (!spec) {
    return -ENOTSUP;
  }

  return gpio_pin_get_raw(spec->port, spec->pin);
}

void DEV_Delay_ms(uint32_t xms) { k_msleep(xms); }

int DEV_SPI_WriteByte(uint8_t data) {
  struct spi_buf tx_buf = {
      .buf = &data,
      .len = 1U,
  };
  struct spi_buf_set tx = {
      .buffers = &tx_buf,
      .count = 1U,
  };

  if (!epd_spi_dev) {
    return -ENODEV;
  }

  return spi_write(epd_spi_dev, &epd_spi_cfg, &tx);
}

int DEV_SPI_Write_nByte(const uint8_t *data, uint32_t len) {
  struct spi_buf tx_buf = {
      .buf = (void *)data,
      .len = len,
  };
  struct spi_buf_set tx = {
      .buffers = &tx_buf,
      .count = 1U,
  };

  if (!epd_spi_dev) {
    return -ENODEV;
  }

  return spi_write(epd_spi_dev, &epd_spi_cfg, &tx);
}

void DEV_Module_Exit(void) {
#if DEV_CONFIG_HAS_POWER
  (void)gpio_pin_set_dt(&epd_power, 0);
#endif
}
