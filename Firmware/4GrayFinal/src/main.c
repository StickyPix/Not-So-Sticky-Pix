#include <errno.h>

#include <zephyr/bluetooth/bluetooth.h>
#include <zephyr/bluetooth/conn.h>
#include <zephyr/device.h>
#include <zephyr/devicetree.h>
#include <zephyr/drivers/spi.h>
#include <zephyr/kernel.h>

#include "ble/ble_image_transfer.h"
#include "epd_driver.h"

#define EPD_GPIO_NODE DT_NODELABEL(gpio0)
#define EPD_SPI_NODE DT_NODELABEL(spi21)

static const struct device *const spi_dev = DEVICE_DT_GET_OR_NULL(EPD_SPI_NODE);
static const struct device *const gpio_dev = DEVICE_DT_GET(EPD_GPIO_NODE);
static struct bt_conn *active_conn;

static int start_advertising(void)
{
	return bt_le_adv_start(
		BT_LE_ADV_PARAM(BT_LE_ADV_OPT_CONN | BT_LE_ADV_OPT_USE_NAME,
				BT_GAP_ADV_FAST_INT_MIN_2,
				BT_GAP_ADV_FAST_INT_MAX_2, NULL),
		NULL, 0, NULL, 0);
}

static void advertising_work_handler(struct k_work *work)
{
	ARG_UNUSED(work);

	(void)start_advertising();
}

K_WORK_DEFINE(advertising_work, advertising_work_handler);

static void throughput_work_handler(struct k_work *work)
{
	struct bt_conn *conn;

	ARG_UNUSED(work);

	if (!active_conn) {
		return;
	}

	conn = bt_conn_ref(active_conn);

	(void)bt_conn_le_param_update(conn, BT_LE_CONN_PARAM(6, 12, 0, 400));

#if defined(CONFIG_BT_USER_DATA_LEN_UPDATE)
	(void)bt_conn_le_data_len_update(conn, BT_LE_DATA_LEN_PARAM_MAX);
#endif

#if defined(CONFIG_BT_USER_PHY_UPDATE)
	(void)bt_conn_le_phy_update(conn, BT_CONN_LE_PHY_PARAM_2M);
#endif

	bt_conn_unref(conn);
}

K_WORK_DELAYABLE_DEFINE(throughput_work, throughput_work_handler);

static void connected(struct bt_conn *conn, uint8_t err)
{
	if (err != 0) {
		k_work_submit(&advertising_work);
		return;
	}

	if (active_conn) {
		bt_conn_unref(active_conn);
	}

	active_conn = bt_conn_ref(conn);
	k_work_schedule(&throughput_work, K_MSEC(500));
}

static void disconnected(struct bt_conn *conn, uint8_t reason)
{
	ARG_UNUSED(conn);
	ARG_UNUSED(reason);

	k_work_cancel_delayable(&throughput_work);
	if (active_conn) {
		bt_conn_unref(active_conn);
		active_conn = NULL;
	}

	ble_image_transfer_reset();
}

static void recycled(void)
{
	/* Bluetooth API calls must not be made directly from this callback. */
	k_work_submit(&advertising_work);
}

BT_CONN_CB_DEFINE(connection_callbacks) = {
	.connected = connected,
	.disconnected = disconnected,
	.recycled = recycled,
};

int main(void)
{
	int ret;

	if (!spi_dev || !device_is_ready(spi_dev)) {
		return -ENODEV;
	}

	if (!device_is_ready(gpio_dev)) {
		return -ENODEV;
	}

	ret = epd_init(spi_dev, gpio_dev);
	if (ret != 0) {
		return ret;
	}

	ret = epd_hibernate();
	if (ret != 0) {
		return ret;
	}

	ret = ble_image_transfer_init();
	if (ret != 0) {
		return ret;
	}

	ret = bt_enable(NULL);
	if (ret != 0) {
		return ret;
	}

	ret = start_advertising();
	if (ret != 0) {
		return ret;
	}

	while (true) {
		k_sleep(K_FOREVER);
	}
}
