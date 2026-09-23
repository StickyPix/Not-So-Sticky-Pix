#ifndef EPD_DRIVER_H
#define EPD_DRIVER_H

#include <zephyr/device.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/drivers/spi.h>
#include <zephyr/kernel.h>

#ifndef EPD_PANEL_WIDTH
#define EPD_PANEL_WIDTH 480U
#define EPD_PANEL_HEIGHT 800U
#define EPD_BW_IMAGE_BYTES (EPD_PANEL_WIDTH * EPD_PANEL_HEIGHT / 8U)
#define EPD_4GRAY_IMAGE_BYTES (EPD_BW_IMAGE_BYTES * 2U)
#endif

int epd_init(const struct device *spi_dev, const struct device *gpio_dev);
int epd_clear_screen(uint8_t black_value, uint8_t color_value);
int epd_clear_white(void);
int epd_clear_black(void);
int epd_hibernate(void);
int epd_power_off(void);
int epd_display_bw(const uint8_t *buffer);
int epd_display_bw_fast(const uint8_t *buffer);
int epd_display_4gray(const uint8_t *buffer);
int display_image(const uint8_t *buffer);
int epd_bus_resume(void);
int epd_bus_suspend(void);
void drawBitmap(int16_t x, int16_t y, const uint8_t *bitmap, int16_t w,
                int16_t h, bool color);

#endif
