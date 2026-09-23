#include <errno.h>

#include <zephyr/bluetooth/bluetooth.h>
#include <zephyr/bluetooth/conn.h>
#include <zephyr/device.h>
#include <zephyr/devicetree.h>
#include <zephyr/drivers/spi.h>
#include <zephyr/kernel.h>

#include "battery_status.h"
#include "ble/ble_image_transfer.h"
#include "epd_driver.h"

#define GPIO1_NODE DT_NODELABEL(gpio0)

static const struct device *spi = DEVICE_DT_GET_OR_NULL(DT_NODELABEL(spi30));
static const struct device *gpiob_dev = DEVICE_DT_GET(GPIO1_NODE);
static struct bt_conn *active_conn;

#define ADV_INTERVAL_MIN 2400U /* 1.5 seconds */
#define ADV_INTERVAL_MAX 3200U /* 2.0 seconds */

static const struct bt_data advertising_data[] = {
	BT_DATA_BYTES(BT_DATA_FLAGS, (BT_LE_AD_GENERAL | BT_LE_AD_NO_BREDR)),
	BT_DATA(BT_DATA_NAME_COMPLETE, CONFIG_BT_DEVICE_NAME, sizeof(CONFIG_BT_DEVICE_NAME) - 1),
};

static const struct bt_le_adv_param advertising_param = {
	.id = BT_ID_DEFAULT,
	.options = BT_LE_ADV_OPT_CONN | BT_LE_ADV_OPT_USE_IDENTITY |
		   BT_LE_ADV_OPT_FILTER_SCAN_REQ,
	.interval_min = ADV_INTERVAL_MIN,
	.interval_max = ADV_INTERVAL_MAX,
	.peer = NULL,
};

static int start_advertising(void)
{
	return bt_le_adv_start(&advertising_param, advertising_data,
			       ARRAY_SIZE(advertising_data), NULL, 0);
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

	if (!spi || !device_is_ready(spi)) {
		return -ENODEV;
	}

	if (!device_is_ready(gpiob_dev)) {
		return -ENODEV;
	}

	ret = battery_status_init();
	if (ret != 0) {
		/* Battery monitoring is optional at boot so BLE/display still start. */
	}

	ret = epd_configure(spi, gpiob_dev);
	if (ret != 0) {
		return ret;
	}

	ret = epd_bus_suspend();
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
