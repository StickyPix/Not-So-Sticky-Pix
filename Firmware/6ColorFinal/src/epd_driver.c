#include "dev_config.h"
#include "epd_interface.h"

#include <string.h>
#include <zephyr/devicetree.h>
#include <zephyr/logging/log.h>
#include <zephyr/sys/util.h>
#if defined(CONFIG_PM_DEVICE)
#include <zephyr/pm/device.h>
#endif

LOG_MODULE_REGISTER(epd_driver_type2);

#define EPD_4IN0E_WIDTH 400U
#define EPD_4IN0E_HEIGHT 600U
#define EPD_4IN0E_ROW_BYTES ((EPD_4IN0E_WIDTH + 1U) / 2U)
#define EPD_4IN0E_IMAGE_BYTES (EPD_4IN0E_ROW_BYTES * EPD_4IN0E_HEIGHT)
#define EPD_4IN0E_BUSY_TIMEOUT_MS 45000
#define EPD_4IN0E_CHUNK_BYTES 64U
#define EPD_NODE DT_PATH(zephyr_user)

#define EPD_4IN0E_BLACK 0x0U
#define EPD_4IN0E_WHITE 0x1U
#define EPD_4IN0E_YELLOW 0x2U
#define EPD_4IN0E_RED 0x3U
#define EPD_4IN0E_BLUE 0x5U
#define EPD_4IN0E_GREEN 0x6U

static const struct device *epd_spi_dev;
static bool epd_hibernating;
static bool epd_ready;
static const struct gpio_dt_spec epd_busy =
    GPIO_DT_SPEC_GET(EPD_NODE, epd_busy_gpios);

static uint8_t epd_color_from_legacy_value(uint8_t value) {
  if (value == 0x00U) {
    return EPD_4IN0E_BLACK;
  }

  if (value == 0x01U || value == 0xFFU) {
    return EPD_4IN0E_WHITE;
  }

  if (value == EPD_4IN0E_BLACK || value == EPD_4IN0E_WHITE ||
      value == EPD_4IN0E_YELLOW || value == EPD_4IN0E_RED ||
      value == EPD_4IN0E_BLUE || value == EPD_4IN0E_GREEN) {
    return value;
  }

  return EPD_4IN0E_WHITE;
}

static int epd_send_command(uint8_t reg) {
  int ret;

  ret = DEV_Digital_Write(EPD_DC_PIN, GPIO_PIN_RESET);
  if (ret != 0) {
    return ret;
  }

  ret = DEV_Digital_Write(EPD_CS_PIN, GPIO_PIN_RESET);
  if (ret != 0) {
    return ret;
  }

  ret = DEV_SPI_WriteByte(reg);
  (void)DEV_Digital_Write(EPD_CS_PIN, GPIO_PIN_SET);
  return ret;
}

static int epd_send_data(uint8_t data) {
  int ret;

  ret = DEV_Digital_Write(EPD_DC_PIN, GPIO_PIN_SET);
  if (ret != 0) {
    return ret;
  }

  ret = DEV_Digital_Write(EPD_CS_PIN, GPIO_PIN_RESET);
  if (ret != 0) {
    return ret;
  }

  ret = DEV_SPI_WriteByte(data);
  (void)DEV_Digital_Write(EPD_CS_PIN, GPIO_PIN_SET);
  return ret;
}

static int epd_send_buffer(const uint8_t *data, size_t len) {
  int ret;

  ret = DEV_Digital_Write(EPD_DC_PIN, GPIO_PIN_SET);
  if (ret != 0) {
    return ret;
  }

  ret = DEV_Digital_Write(EPD_CS_PIN, GPIO_PIN_RESET);
  if (ret != 0) {
    return ret;
  }

  ret = DEV_SPI_Write_nByte(data, len);
  (void)DEV_Digital_Write(EPD_CS_PIN, GPIO_PIN_SET);
  return ret;
}

static int epd_reset(void) {
  int ret;

  ret = DEV_Digital_Write(EPD_RST_PIN, GPIO_PIN_SET);
  if (ret != 0) {
    return ret;
  }
  DEV_Delay_ms(20);

  ret = DEV_Digital_Write(EPD_RST_PIN, GPIO_PIN_RESET);
  if (ret != 0) {
    return ret;
  }
  DEV_Delay_ms(2);

  ret = DEV_Digital_Write(EPD_RST_PIN, GPIO_PIN_SET);
  if (ret != 0) {
    return ret;
  }
  DEV_Delay_ms(20);

  epd_hibernating = false;
  return 0;
}

static int epd_wait_idle(void) {
  int timeout_ms;
  int busy_level;

  if (!device_is_ready(epd_busy.port)) {
    return -ENODEV;
  }

  timeout_ms = EPD_4IN0E_BUSY_TIMEOUT_MS;
  while (timeout_ms > 0) {
    busy_level = gpio_pin_get_dt(&epd_busy);

    if (busy_level < 0) {
      return busy_level;
    }
    if (busy_level != 0) {
      DEV_Delay_ms(200);
      return 0;
    }

    DEV_Delay_ms(10);
    timeout_ms -= 10;
  }

  LOG_ERR("EPD busy timeout");
  return -ETIMEDOUT;
}

static int epd_turn_on_display(void) {
  int ret;

  ret = epd_send_command(0x04);
  if (ret != 0) {
    return ret;
  }
  ret = epd_wait_idle();
  if (ret != 0) {
    return ret;
  }
  DEV_Delay_ms(200);

  ret = epd_send_command(0x06);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x6F);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x1F);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x17);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x27);
  if (ret != 0) {
    return ret;
  }
  DEV_Delay_ms(200);

  ret = epd_send_command(0x12);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x00);
  if (ret != 0) {
    return ret;
  }
  ret = epd_wait_idle();
  if (ret != 0) {
    return ret;
  }

  ret = epd_send_command(0x02);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x00);
  if (ret != 0) {
    return ret;
  }
  ret = epd_wait_idle();
  if (ret != 0) {
    return ret;
  }

  DEV_Delay_ms(200);
  return 0;
}

static int epd_panel_init(void) {
  int ret;

  ret = epd_reset();
  if (ret != 0) {
    return ret;
  }
  ret = epd_wait_idle();
  if (ret != 0) {
    return ret;
  }
  DEV_Delay_ms(30);

  ret = epd_send_command(0xAA);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x49);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x55);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x20);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x08);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x09);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x18);
  if (ret != 0) {
    return ret;
  }

  ret = epd_send_command(0x01);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x3F);
  if (ret != 0) {
    return ret;
  }

  ret = epd_send_command(0x00);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x5F);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x69);
  if (ret != 0) {
    return ret;
  }

  ret = epd_send_command(0x05);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x40);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x1F);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x1F);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x2C);
  if (ret != 0) {
    return ret;
  }

  ret = epd_send_command(0x08);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x6F);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x1F);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x1F);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x22);
  if (ret != 0) {
    return ret;
  }

  ret = epd_send_command(0x06);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x6F);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x1F);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x17);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x17);
  if (ret != 0) {
    return ret;
  }

  ret = epd_send_command(0x03);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x00);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x54);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x00);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x44);
  if (ret != 0) {
    return ret;
  }

  ret = epd_send_command(0x60);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x02);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x00);
  if (ret != 0) {
    return ret;
  }

  ret = epd_send_command(0x30);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x08);
  if (ret != 0) {
    return ret;
  }

  ret = epd_send_command(0x50);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x3F);
  if (ret != 0) {
    return ret;
  }

  ret = epd_send_command(0x61);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x01);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x90);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x02);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x58);
  if (ret != 0) {
    return ret;
  }

  ret = epd_send_command(0xE3);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x2F);
  if (ret != 0) {
    return ret;
  }

  ret = epd_send_command(0x84);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x01);
  if (ret != 0) {
    return ret;
  }
  ret = epd_wait_idle();
  if (ret != 0) {
    return ret;
  }

  epd_ready = true;
  return 0;
}

static int epd_store_first_error(int ret, int fallback) {
  return ret == 0 ? fallback : ret;
}

static int epd_disconnect_busy(void) {
  if (!device_is_ready(epd_busy.port)) {
    return -ENODEV;
  }

  return gpio_pin_configure(epd_busy.port, epd_busy.pin, GPIO_DISCONNECTED);
}

static int epd_module_start(void) {
  int ret;

  if (!epd_spi_dev || !device_is_ready(epd_spi_dev)) {
    return -ENODEV;
  }

  if (!device_is_ready(epd_busy.port)) {
    return -ENODEV;
  }

  ret = DEV_Module_Init(epd_spi_dev, NULL);
  if (ret != 0) {
    return ret;
  }

  return gpio_pin_configure_dt(&epd_busy, GPIO_INPUT);
}

static int epd_module_stop(void) {
  int ret;

  ret = DEV_Module_Exit();
  ret = epd_store_first_error(ret, epd_disconnect_busy());

  epd_ready = false;
  epd_hibernating = false;

  return ret;
}

static int epd_prepare_update(void) {
  int ret;

  if (!epd_ready || epd_hibernating) {
    ret = epd_module_start();
    if (ret != 0) {
      return ret;
    }

    return epd_panel_init();
  }

  return 0;
}

int epd_bus_resume(void) {
#if defined(CONFIG_PM_DEVICE)
  int ret;

  if (!epd_spi_dev) {
    return -ENODEV;
  }

  ret = pm_device_action_run(epd_spi_dev, PM_DEVICE_ACTION_RESUME);
  return ret == -EALREADY ? 0 : ret;
#else
  return 0;
#endif
}

int epd_bus_suspend(void) {
#if defined(CONFIG_PM_DEVICE)
  int ret;

  if (!epd_spi_dev) {
    return -ENODEV;
  }

  ret = pm_device_action_run(epd_spi_dev, PM_DEVICE_ACTION_SUSPEND);
  return ret == -EALREADY ? 0 : ret;
#else
  return 0;
#endif
}

int epd_init(const struct device *spi_dev, const struct device *gpio_dev) {
  int ret;

  ret = epd_configure(spi_dev, gpio_dev);
  if (ret != 0) {
    return ret;
  }

  ret = epd_module_start();
  if (ret != 0) {
    return ret;
  }

  ret = epd_panel_init();
  if (ret != 0) {
    (void)epd_module_stop();
    return ret;
  }

  return epd_hibernate();
}

int epd_configure(const struct device *spi_dev, const struct device *gpio_dev) {
  epd_spi_dev = spi_dev;
  ARG_UNUSED(gpio_dev);

  if (!epd_spi_dev || !device_is_ready(epd_spi_dev)) {
    return -ENODEV;
  }

  if (!device_is_ready(epd_busy.port)) {
    return -ENODEV;
  }

  return epd_module_stop();
}

int epd_clear_screen(uint8_t black_value, uint8_t color_value) {
  uint8_t chunk[EPD_4IN0E_CHUNK_BYTES];
  uint8_t packed_color;
  uint32_t remaining;
  int ret;

  ARG_UNUSED(color_value);

  ret = epd_prepare_update();
  if (ret != 0) {
    return ret;
  }

  packed_color = epd_color_from_legacy_value(black_value);
  packed_color = (uint8_t)((packed_color << 4) | packed_color);
  memset(chunk, packed_color, sizeof(chunk));

  ret = epd_send_command(0x10);
  if (ret != 0) {
    return ret;
  }

  remaining = EPD_4IN0E_IMAGE_BYTES;
  while (remaining > 0U) {
    uint32_t write_len = MIN(remaining, (uint32_t)sizeof(chunk));

    ret = epd_send_buffer(chunk, write_len);
    if (ret != 0) {
      return ret;
    }

    remaining -= write_len;
  }

  return epd_turn_on_display();
}

int epd_clear_white(void) {
  return epd_clear_screen(EPD_4IN0E_WHITE, EPD_4IN0E_WHITE);
}

int epd_clear_black(void) {
  return epd_clear_screen(EPD_4IN0E_BLACK, EPD_4IN0E_BLACK);
}

int epd_power_off(void) {
  int ret;

  if (!epd_ready) {
    return 0;
  }

  ret = epd_send_command(0x02);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0x00);
  if (ret != 0) {
    return ret;
  }

  return epd_wait_idle();
}

int epd_hibernate(void) {
  int ret;

  if (!epd_ready) {
    return 0;
  }

  ret = epd_send_command(0x07);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_data(0xA5);
  if (ret != 0) {
    return ret;
  }

  epd_hibernating = true;
  return 0;
}

int epd_power_down(void) {
  int ret = 0;

  if (epd_ready && !epd_hibernating) {
    ret = epd_hibernate();
  }

  ret = epd_store_first_error(ret, epd_module_stop());
  return ret;
}

int display_image(const uint8_t *buffer) {
  int ret;

  if (!buffer) {
    return -EINVAL;
  }

  ret = epd_prepare_update();
  if (ret != 0) {
    return ret;
  }

  ret = epd_send_command(0x10);
  if (ret != 0) {
    return ret;
  }

  for (uint16_t row = 0U; row < EPD_4IN0E_HEIGHT; ++row) {
    const uint8_t *row_data = buffer + ((size_t)row * EPD_4IN0E_ROW_BYTES);

    ret = epd_send_buffer(row_data, EPD_4IN0E_ROW_BYTES);
    if (ret != 0) {
      return ret;
    }
  }

  return epd_turn_on_display();
}

void drawBitmap(int16_t x, int16_t y, const uint8_t *bitmap, int16_t w,
                int16_t h, bool color) {
  ARG_UNUSED(x);
  ARG_UNUSED(y);
  ARG_UNUSED(bitmap);
  ARG_UNUSED(w);
  ARG_UNUSED(h);
  ARG_UNUSED(color);
}
