#ifndef EPD_INTERFACE_H
#define EPD_INTERFACE_H

#include <zephyr/device.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/drivers/spi.h>
#include <zephyr/kernel.h>

#ifndef EPD_PANEL_WIDTH
#define EPD_PANEL_WIDTH 400U
#define EPD_PANEL_HEIGHT 600U
#define EPD_6COLOR_IMAGE_BYTES (EPD_PANEL_WIDTH * EPD_PANEL_HEIGHT / 2U)
#endif

/**
 * @brief Initialize the e-ink display driver
 */
int epd_init(const struct device *spi_dev, const struct device *gpio_dev);

/**
 * @brief Store the e-ink devices and leave the display powered off
 */
int epd_configure(const struct device *spi_dev, const struct device *gpio_dev);

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
 * @brief Hibernate the display, disable panel power, and release EPD pins
 */
int epd_power_down(void);

/**
 * @brief Display an image buffer
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
