#include "dev_config.h"
#include "epd_interface.h"

#include <string.h>
#include <zephyr/devicetree.h>
#include <zephyr/logging/log.h>
#include <zephyr/sys/util.h>
#if defined(CONFIG_PM_DEVICE)
#include <zephyr/pm/device.h>
#endif

LOG_MODULE_REGISTER(epd_driver_4gray);

#define EPD_NODE DT_PATH(zephyr_user)
#define EPD_BUSY_TIMEOUT_MS 45000
#define EPD_CHUNK_BYTES 64U
#define EPD_CS_IDLE 1
#define EPD_CS_ACTIVE 0

enum epd_update_mode {
  EPD_UPDATE_MODE_NONE = 0,
  EPD_UPDATE_MODE_FULL,
  EPD_UPDATE_MODE_FAST,
  EPD_UPDATE_MODE_4GRAY,
};

static const struct device *epd_spi_dev;
static enum epd_update_mode epd_active_mode = EPD_UPDATE_MODE_NONE;
static bool epd_ready;
static bool epd_hibernating;
static const struct gpio_dt_spec epd_busy =
    GPIO_DT_SPEC_GET(EPD_NODE, epd_busy_gpios);

static int epd_cs_idle(void) {
  return DEV_Digital_Write(EPD_CS_PIN, EPD_CS_IDLE);
}

static int epd_cs_active(void) {
  return DEV_Digital_Write(EPD_CS_PIN, EPD_CS_ACTIVE);
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

  ret = epd_cs_active();
  if (ret != 0) {
    return ret;
  }

  ret = DEV_SPI_Write_nByte(data, (uint32_t)len);
  (void)epd_cs_idle();
  return ret;
}

static int epd_send_data_array(const uint8_t *data, size_t len) {
  int ret;

  for (size_t i = 0U; i < len; ++i) {
    ret = epd_send_data(data[i]);
    if (ret != 0) {
      return ret;
    }
  }

  return 0;
}

static int epd_send_command_data(uint8_t command, const uint8_t *data,
                                 size_t len) {
  int ret;

  ret = epd_send_command(command);
  if (ret != 0) {
    return ret;
  }

  return epd_send_data_array(data, len);
}

static int epd_reset(void) {
  int ret;

  ret = DEV_Digital_Write(EPD_RST_PIN, GPIO_PIN_RESET);
  if (ret != 0) {
    return ret;
  }
  DEV_Delay_ms(10);

  ret = DEV_Digital_Write(EPD_RST_PIN, GPIO_PIN_SET);
  if (ret != 0) {
    return ret;
  }
  DEV_Delay_ms(10);

  epd_hibernating = false;
  return 0;
}

static int epd_wait_idle(void) {
  int timeout_ms = EPD_BUSY_TIMEOUT_MS;
  int busy_level;

  if (!device_is_ready(epd_busy.port)) {
    return -ENODEV;
  }

  while (timeout_ms > 0) {
    busy_level = gpio_pin_get_dt(&epd_busy);
    if (busy_level < 0) {
      return busy_level;
    }

    if (busy_level == 0) {
      return 0;
    }

    DEV_Delay_ms(10);
    timeout_ms -= 10;
  }

  LOG_ERR("EPD busy timeout");
  return -ETIMEDOUT;
}

static int epd_write_repeated(uint8_t value, uint32_t len) {
  uint8_t chunk[EPD_CHUNK_BYTES];
  int ret;

  memset(chunk, value, sizeof(chunk));

  while (len > 0U) {
    uint32_t write_len = MIN(len, (uint32_t)sizeof(chunk));

    ret = epd_send_buffer(chunk, write_len);
    if (ret != 0) {
      return ret;
    }

    len -= write_len;
  }

  return 0;
}

static int epd_set_full_ram_area(uint8_t data_entry_mode) {
  const uint16_t width_end = EPD_PANEL_WIDTH - 1U;
  const uint16_t height_end = EPD_PANEL_HEIGHT - 1U;
  const uint8_t driver_output[] = {
      (uint8_t)(width_end & 0xFFU),
      (uint8_t)(width_end >> 8),
      0x02U,
  };
  const uint8_t entry_mode[] = { data_entry_mode };
  const uint8_t ram_x[] = {
      0x00U,
      0x00U,
      (uint8_t)(height_end & 0xFFU),
      (uint8_t)(height_end >> 8),
  };
  const uint8_t ram_y[] = {
      0x00U,
      0x00U,
      (uint8_t)(width_end & 0xFFU),
      (uint8_t)(width_end >> 8),
  };
  const uint8_t ram_start[] = { 0x00U, 0x00U };
  int ret;

  ret = epd_send_command_data(0x01, driver_output, sizeof(driver_output));
  if (ret != 0) {
    return ret;
  }

  ret = epd_send_command_data(0x11, entry_mode, sizeof(entry_mode));
  if (ret != 0) {
    return ret;
  }

  ret = epd_send_command_data(0x44, ram_x, sizeof(ram_x));
  if (ret != 0) {
    return ret;
  }

  ret = epd_send_command_data(0x45, ram_y, sizeof(ram_y));
  if (ret != 0) {
    return ret;
  }

  ret = epd_send_command_data(0x4E, ram_start, sizeof(ram_start));
  if (ret != 0) {
    return ret;
  }

  return epd_send_command_data(0x4F, ram_start, sizeof(ram_start));
}

static int epd_panel_init(enum epd_update_mode mode) {
  const uint8_t booster_soft_start[] = { 0xAEU, 0xC7U, 0xC3U, 0xC0U, 0x80U };
  const uint8_t border_waveform[] = { 0x01U };
  const uint8_t temp_sensor[] = { 0x80U };
  const uint8_t mode_4gray[] = { 0x5AU };
  const uint8_t mode_fast[] = { 0x6AU };
  int ret;

  ret = epd_reset();
  if (ret != 0) {
    return ret;
  }

  ret = epd_wait_idle();
  if (ret != 0) {
    return ret;
  }

  ret = epd_send_command(0x12);
  if (ret != 0) {
    return ret;
  }

  ret = epd_wait_idle();
  if (ret != 0) {
    return ret;
  }

  if (mode == EPD_UPDATE_MODE_FULL) {
    ret = epd_send_command_data(0x18, temp_sensor, sizeof(temp_sensor));
    if (ret != 0) {
      return ret;
    }
  }

  ret = epd_send_command_data(0x0C, booster_soft_start,
                              sizeof(booster_soft_start));
  if (ret != 0) {
    return ret;
  }

  if (mode == EPD_UPDATE_MODE_FULL) {
    ret = epd_send_command_data(0x3C, border_waveform,
                                sizeof(border_waveform));
    if (ret != 0) {
      return ret;
    }
  }

  ret = epd_set_full_ram_area(0x03U);
  if (ret != 0) {
    return ret;
  }

  ret = epd_wait_idle();
  if (ret != 0) {
    return ret;
  }

  if (mode != EPD_UPDATE_MODE_FULL) {
    ret = epd_send_command_data(0x3C, border_waveform,
                                sizeof(border_waveform));
    if (ret != 0) {
      return ret;
    }

    ret = epd_send_command_data(0x18, temp_sensor, sizeof(temp_sensor));
    if (ret != 0) {
      return ret;
    }

    if (mode == EPD_UPDATE_MODE_4GRAY) {
      ret = epd_send_command_data(0x1A, mode_4gray, sizeof(mode_4gray));
    } else {
      ret = epd_send_command_data(0x1A, mode_fast, sizeof(mode_fast));
    }
    if (ret != 0) {
      return ret;
    }
  }

  epd_active_mode = mode;
  epd_ready = true;
  epd_hibernating = false;
  return 0;
}

static int epd_prepare_update(enum epd_update_mode mode) {
  if (!epd_ready || epd_hibernating || epd_active_mode != mode) {
    return epd_panel_init(mode);
  }

  return 0;
}

static int epd_update(uint8_t update_control) {
  int ret;

  ret = epd_send_command(0x22);
  if (ret != 0) {
    return ret;
  }

  ret = epd_send_data(update_control);
  if (ret != 0) {
    return ret;
  }

  ret = epd_send_command(0x20);
  if (ret != 0) {
    return ret;
  }

  return epd_wait_idle();
}

static uint8_t epd_4gray_ram1_from_2bpp(uint8_t data1, uint8_t data2) {
  uint8_t out = 0U;
  uint8_t temp1 = data1;
  uint8_t temp2 = data2;

  for (uint8_t i = 0U; i < 4U; ++i) {
    out <<= 1;
    if ((temp1 & 0xC0U) == 0xC0U || (temp1 & 0xC0U) == 0x40U) {
      out |= 0x01U;
    }
    temp1 <<= 2;
  }

  for (uint8_t i = 0U; i < 4U; ++i) {
    out <<= 1;
    if ((temp2 & 0xC0U) == 0xC0U || (temp2 & 0xC0U) == 0x40U) {
      out |= 0x01U;
    }
    temp2 <<= 2;
  }

  return out;
}

static uint8_t epd_4gray_ram2_from_2bpp(uint8_t data1, uint8_t data2) {
  uint8_t out = 0U;
  uint8_t temp1 = data1;
  uint8_t temp2 = data2;

  for (uint8_t i = 0U; i < 4U; ++i) {
    out <<= 1;
    if ((temp1 & 0xC0U) == 0xC0U || (temp1 & 0xC0U) == 0x80U) {
      out |= 0x01U;
    }
    temp1 <<= 2;
  }

  for (uint8_t i = 0U; i < 4U; ++i) {
    out <<= 1;
    if ((temp2 & 0xC0U) == 0xC0U || (temp2 & 0xC0U) == 0x80U) {
      out |= 0x01U;
    }
    temp2 <<= 2;
  }

  return out;
}

int epd_bus_resume(void) {
#if defined(CONFIG_PM_DEVICE)
  if (!epd_spi_dev) {
    return -ENODEV;
  }
  return pm_device_action_run(epd_spi_dev, PM_DEVICE_ACTION_RESUME);
#else
  return 0;
#endif
}

int epd_bus_suspend(void) {
#if defined(CONFIG_PM_DEVICE)
  if (!epd_spi_dev) {
    return -ENODEV;
  }
  return pm_device_action_run(epd_spi_dev, PM_DEVICE_ACTION_SUSPEND);
#else
  return 0;
#endif
}

int epd_init(const struct device *spi_dev, const struct device *gpio_dev) {
  int ret;

  epd_spi_dev = spi_dev;
  ARG_UNUSED(gpio_dev);

  if (!epd_spi_dev || !device_is_ready(epd_spi_dev)) {
    return -ENODEV;
  }

  if (!device_is_ready(epd_busy.port)) {
    return -ENODEV;
  }

  ret = DEV_Module_Init(spi_dev, gpio_dev);
  if (ret != 0) {
    return ret;
  }

  ret = gpio_pin_configure_dt(&epd_busy, GPIO_INPUT);
  if (ret != 0) {
    return ret;
  }

  return epd_panel_init(EPD_UPDATE_MODE_4GRAY);
}

int epd_clear_screen(uint8_t black_value, uint8_t color_value) {
  ARG_UNUSED(color_value);

  if (black_value == 0x00U) {
    return epd_clear_black();
  }

  return epd_clear_white();
}

int epd_clear_white(void) {
  int ret;

  ret = epd_prepare_update(EPD_UPDATE_MODE_FULL);
  if (ret != 0) {
    return ret;
  }

  ret = epd_send_command(0x24);
  if (ret != 0) {
    return ret;
  }
  ret = epd_write_repeated(0xFFU, EPD_BW_IMAGE_BYTES);
  if (ret != 0) {
    return ret;
  }

  ret = epd_send_command(0x26);
  if (ret != 0) {
    return ret;
  }
  ret = epd_write_repeated(0xFFU, EPD_BW_IMAGE_BYTES);
  if (ret != 0) {
    return ret;
  }

  return epd_update(0xF7U);
}

int epd_clear_black(void) {
  int ret;

  ret = epd_prepare_update(EPD_UPDATE_MODE_FULL);
  if (ret != 0) {
    return ret;
  }

  ret = epd_send_command(0x24);
  if (ret != 0) {
    return ret;
  }
  ret = epd_write_repeated(0x00U, EPD_BW_IMAGE_BYTES);
  if (ret != 0) {
    return ret;
  }

  ret = epd_send_command(0x26);
  if (ret != 0) {
    return ret;
  }
  ret = epd_write_repeated(0xFFU, EPD_BW_IMAGE_BYTES);
  if (ret != 0) {
    return ret;
  }

  return epd_update(0xF7U);
}

int epd_display_bw(const uint8_t *buffer) {
  int ret;

  if (!buffer) {
    return -EINVAL;
  }

  ret = epd_prepare_update(EPD_UPDATE_MODE_FULL);
  if (ret != 0) {
    return ret;
  }

  ret = epd_send_command(0x24);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_buffer(buffer, EPD_BW_IMAGE_BYTES);
  if (ret != 0) {
    return ret;
  }

  ret = epd_send_command(0x26);
  if (ret != 0) {
    return ret;
  }
  ret = epd_write_repeated(0xFFU, EPD_BW_IMAGE_BYTES);
  if (ret != 0) {
    return ret;
  }

  return epd_update(0xF7U);
}

int epd_display_bw_fast(const uint8_t *buffer) {
  int ret;

  if (!buffer) {
    return -EINVAL;
  }

  ret = epd_prepare_update(EPD_UPDATE_MODE_FAST);
  if (ret != 0) {
    return ret;
  }

  ret = epd_send_command(0x24);
  if (ret != 0) {
    return ret;
  }
  ret = epd_send_buffer(buffer, EPD_BW_IMAGE_BYTES);
  if (ret != 0) {
    return ret;
  }

  ret = epd_send_command(0x26);
  if (ret != 0) {
    return ret;
  }
  ret = epd_write_repeated(0xFFU, EPD_BW_IMAGE_BYTES);
  if (ret != 0) {
    return ret;
  }

  return epd_update(0xD7U);
}

int epd_display_4gray(const uint8_t *buffer) {
  int ret;

  if (!buffer) {
    return -EINVAL;
  }

  ret = epd_prepare_update(EPD_UPDATE_MODE_4GRAY);
  if (ret != 0) {
    return ret;
  }

  ret = epd_send_command(0x24);
  if (ret != 0) {
    return ret;
  }
  for (uint32_t i = 0U; i < EPD_4GRAY_IMAGE_BYTES; i += 2U) {
    ret = epd_send_data((uint8_t)~epd_4gray_ram1_from_2bpp(buffer[i],
                                                           buffer[i + 1U]));
    if (ret != 0) {
      return ret;
    }
  }

  ret = epd_send_command(0x26);
  if (ret != 0) {
    return ret;
  }
  for (uint32_t i = 0U; i < EPD_4GRAY_IMAGE_BYTES; i += 2U) {
    ret = epd_send_data((uint8_t)~epd_4gray_ram2_from_2bpp(buffer[i],
                                                           buffer[i + 1U]));
    if (ret != 0) {
      return ret;
    }
  }

  return epd_update(0xD7U);
}

int display_image(const uint8_t *buffer) { return epd_display_4gray(buffer); }

int epd_power_off(void) { return epd_hibernate(); }

int epd_hibernate(void) {
  int ret;

  if (!epd_ready && epd_hibernating) {
    return 0;
  }

  ret = epd_send_command(0x10);
  if (ret != 0) {
    return ret;
  }

  ret = epd_send_data(0x01U);
  if (ret != 0) {
    return ret;
  }

  DEV_Delay_ms(100);
  epd_ready = false;
  epd_hibernating = true;
  epd_active_mode = EPD_UPDATE_MODE_NONE;
  return 0;
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
