#ifndef EPD_INTERFACE_H
#define EPD_INTERFACE_H

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

/**
 * @brief Initialize the e-ink display driver
 */
int epd_init(const struct device *spi_dev, const struct device *gpio_dev);

/**
 * @brief Clear the screen with specified values
 */
int epd_clear_screen(uint8_t black_value, uint8_t color_value);

/**
 * @brief Clear the screen to white
 */
int epd_clear_white(void);

/**
 * @brief Clear the screen to black
 */
int epd_clear_black(void);

/**
 * @brief Put the display into hibernation mode
 */
int epd_hibernate(void);

/**
 * @brief Turn display power off
 */
int epd_power_off(void);

/**
 * @brief Display a 1-bit black/white image buffer using a full refresh
 */
int epd_display_bw(const uint8_t *buffer);

/**
 * @brief Display a 1-bit black/white image buffer using fast refresh
 */
int epd_display_bw_fast(const uint8_t *buffer);

/**
 * @brief Display a 2-bit-per-pixel 4-gray image buffer
 */
int epd_display_4gray(const uint8_t *buffer);

/**
 * @brief Display a 2-bit-per-pixel 4-gray image buffer
 */
int display_image(const uint8_t *buffer);

/**
 * @brief Resume the display SPI device (power management).
 *
 * This is a no-op if device PM is not enabled.
 */
int epd_bus_resume(void);

/**
 * @brief Suspend the display SPI device (power management).
 *
 * This is a no-op if device PM is not enabled.
 */
int epd_bus_suspend(void);

/*
 * Helper prototype for drawing bitmaps if needed by app,
 * though strictly this might be better in a graphics library.
 */
void drawBitmap(int16_t x, int16_t y, const uint8_t *bitmap, int16_t w,
                int16_t h, bool color);

#endif /* EPD_INTERFACE_H */
