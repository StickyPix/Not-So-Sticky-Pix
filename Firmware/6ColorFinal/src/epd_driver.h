#ifndef EPD_DRIVER_H
#define EPD_DRIVER_H

#include <zephyr/device.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/drivers/spi.h>
#include <zephyr/kernel.h>

#ifndef EPD_PANEL_WIDTH
#define EPD_PANEL_WIDTH 400U
#define EPD_PANEL_HEIGHT 600U
#define EPD_6COLOR_IMAGE_BYTES (EPD_PANEL_WIDTH * EPD_PANEL_HEIGHT / 2U)
#endif

int epd_init(const struct device *spi_dev, const struct device *gpio_dev);
int epd_configure(const struct device *spi_dev, const struct device *gpio_dev);
int epd_clear_screen(uint8_t black_value, uint8_t color_value);
int epd_clear_white(void);
int epd_clear_black(void);
int epd_hibernate(void);
int epd_power_off(void);
int epd_power_down(void);
int display_image(const uint8_t *buffer);
int epd_bus_resume(void);
int epd_bus_suspend(void);
void drawBitmap(int16_t x, int16_t y, const uint8_t *bitmap, int16_t w,
                int16_t h, bool color);

#endif
