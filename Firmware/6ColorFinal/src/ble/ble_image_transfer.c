#include "ble_image_transfer.h"

#include "../battery_status.h"
#include "../epd_interface.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <zephyr/bluetooth/conn.h>
#include <zephyr/bluetooth/gatt.h>
#include <zephyr/bluetooth/uuid.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <zephyr/sys/atomic.h>
#include <zephyr/sys/byteorder.h>

LOG_MODULE_REGISTER(ble_image_transfer);

#define IMAGE_TRANSFER_BYTES EPD_6COLOR_IMAGE_BYTES
#define DISPLAY_WORK_STACK_SIZE 2048
#define UUID128_ENC(w32, w1, w2, w3, w48) BT_UUID_128_ENCODE(w32, w1, w2, w3, w48)

BUILD_ASSERT(IMAGE_TRANSFER_BYTES == 120000U,
	     "6-color image transfer must be exactly 120000 bytes");

static uint8_t image_buf[IMAGE_TRANSFER_BYTES];
static size_t image_expected;
static size_t image_received;
static bool notify_enabled;
static atomic_t display_busy;
static bool display_queue_started;
static struct k_work display_work;
static struct k_work_q display_work_q;
K_THREAD_STACK_DEFINE(display_work_stack, DISPLAY_WORK_STACK_SIZE);

static int notify_progress(struct bt_conn *conn);

static struct bt_uuid_128 uuid_svc = BT_UUID_INIT_128(
	UUID128_ENC(0x12345678, 0x1234, 0x5678, 0x1234, 0x56789abcdef0ULL));
static struct bt_uuid_128 uuid_size = BT_UUID_INIT_128(
	UUID128_ENC(0x12345678, 0x1234, 0x5678, 0x1234, 0x56789abcdef1ULL));
static struct bt_uuid_128 uuid_data = BT_UUID_INIT_128(
	UUID128_ENC(0x12345678, 0x1234, 0x5678, 0x1234, 0x56789abcdef2ULL));
static struct bt_uuid_128 uuid_prog = BT_UUID_INIT_128(
	UUID128_ENC(0x12345678, 0x1234, 0x5678, 0x1234, 0x56789abcdef3ULL));
static struct bt_uuid_128 uuid_batt = BT_UUID_INIT_128(
	UUID128_ENC(0x12345678, 0x1234, 0x5678, 0x1234, 0x56789abcdef4ULL));

#define IMAGE_SVC_ATTRS image_transfer_svc.attrs

static void display_work_handler(struct k_work *work)
{
	int ret;

	ARG_UNUSED(work);

	ret = epd_bus_resume();
	if (ret != 0) {
		LOG_ERR("Failed to resume EPD bus: %d", ret);
		goto done;
	}

	ret = display_image(image_buf);
	if (ret != 0) {
		LOG_ERR("Failed to display BLE image: %d", ret);
	} else {
		LOG_INF("BLE image displayed");
	}

	ret = epd_power_down();
	if (ret != 0) {
		LOG_ERR("Failed to power down EPD: %d", ret);
	}

	ret = epd_bus_suspend();
	if (ret != 0) {
		LOG_ERR("Failed to suspend EPD bus: %d", ret);
	}

done:
	image_expected = 0U;
	image_received = 0U;
	atomic_clear(&display_busy);
}

static ssize_t size_write(struct bt_conn *conn, const struct bt_gatt_attr *attr,
			  const void *buf, uint16_t len, uint16_t offset,
			  uint8_t flags)
{
	uint32_t val;

	ARG_UNUSED(attr);
	ARG_UNUSED(flags);

	if (offset != 0U || len != sizeof(val)) {
		return BT_GATT_ERR(BT_ATT_ERR_INVALID_ATTRIBUTE_LEN);
	}

	if (atomic_get(&display_busy) != 0) {
		LOG_WRN("Image display is still busy");
		return BT_GATT_ERR(BT_ATT_ERR_PROCEDURE_IN_PROGRESS);
	}

	val = sys_get_le32(buf);
	if (val != IMAGE_TRANSFER_BYTES) {
		LOG_WRN("Invalid image size %u, expected %u", val, IMAGE_TRANSFER_BYTES);
		return BT_GATT_ERR(BT_ATT_ERR_VALUE_NOT_ALLOWED);
	}

	image_expected = val;
	image_received = 0U;
	LOG_INF("6-color image transfer started: %u bytes", val);

	(void)notify_progress(conn);
	return len;
}

static ssize_t data_write(struct bt_conn *conn, const struct bt_gatt_attr *attr,
			  const void *buf, uint16_t len, uint16_t offset,
			  uint8_t flags)
{
	size_t remaining;

	ARG_UNUSED(attr);
	ARG_UNUSED(flags);

	if (image_expected == 0U) {
		return BT_GATT_ERR(BT_ATT_ERR_UNLIKELY);
	}

	if (atomic_get(&display_busy) != 0) {
		return BT_GATT_ERR(BT_ATT_ERR_PROCEDURE_IN_PROGRESS);
	}

	if (offset != 0U && offset != image_received) {
		if (offset > image_expected) {
			return BT_GATT_ERR(BT_ATT_ERR_INVALID_OFFSET);
		}
		image_received = offset;
	}

	remaining = image_expected - image_received;
	if (len > remaining || (image_received + len) > IMAGE_TRANSFER_BYTES) {
		return BT_GATT_ERR(BT_ATT_ERR_INVALID_OFFSET);
	}

	memcpy(&image_buf[image_received], buf, len);
	image_received += len;

	(void)notify_progress(conn);

	if (image_received == image_expected) {
		LOG_INF("6-color image transfer complete");
		atomic_set(&display_busy, 1);
		k_work_submit_to_queue(&display_work_q, &display_work);
	}

	return len;
}

static void prog_ccc_cfg_changed(const struct bt_gatt_attr *attr, uint16_t value)
{
	ARG_UNUSED(attr);

	notify_enabled = (value == BT_GATT_CCC_NOTIFY);
}

static ssize_t battery_read(struct bt_conn *conn, const struct bt_gatt_attr *attr,
			    void *buf, uint16_t len, uint16_t offset)
{
	uint8_t percent;
	int ret;

	ARG_UNUSED(attr);

	ret = battery_status_read_percent(&percent);
	if (ret != 0) {
		LOG_WRN("Battery percentage read failed: %d", ret);
		return BT_GATT_ERR(BT_ATT_ERR_UNLIKELY);
	}

	return bt_gatt_attr_read(conn, attr, buf, len, offset, &percent, sizeof(percent));
}

BT_GATT_SERVICE_DEFINE(
	image_transfer_svc, BT_GATT_PRIMARY_SERVICE(&uuid_svc.uuid),
	BT_GATT_CHARACTERISTIC(&uuid_size.uuid, BT_GATT_CHRC_WRITE,
			       BT_GATT_PERM_WRITE, NULL, size_write, NULL),
	BT_GATT_CHARACTERISTIC(&uuid_data.uuid,
			       BT_GATT_CHRC_WRITE | BT_GATT_CHRC_WRITE_WITHOUT_RESP,
			       BT_GATT_PERM_WRITE, NULL, data_write, NULL),
	BT_GATT_CHARACTERISTIC(&uuid_prog.uuid, BT_GATT_CHRC_NOTIFY, BT_GATT_PERM_NONE,
			       NULL, NULL, NULL),
	BT_GATT_CCC(prog_ccc_cfg_changed, BT_GATT_PERM_READ | BT_GATT_PERM_WRITE),
	BT_GATT_CHARACTERISTIC(&uuid_batt.uuid, BT_GATT_CHRC_READ, BT_GATT_PERM_READ,
			       battery_read, NULL, NULL));

static int notify_progress(struct bt_conn *conn)
{
	uint8_t percent;

	if (!notify_enabled || image_expected == 0U) {
		return 0;
	}

	percent = (uint8_t)((image_received * 100U) / image_expected);
	return bt_gatt_notify_uuid(conn, &uuid_prog.uuid, IMAGE_SVC_ATTRS, &percent,
				   sizeof(percent));
}

int ble_image_transfer_init(void)
{
	k_work_init(&display_work, display_work_handler);

	if (!display_queue_started) {
		k_work_queue_start(&display_work_q, display_work_stack,
				   K_THREAD_STACK_SIZEOF(display_work_stack), 5, NULL);
		display_queue_started = true;
	}
	return 0;
}

void ble_image_transfer_reset(void)
{
	if (atomic_get(&display_busy) != 0) {
		return;
	}

	image_expected = 0U;
	image_received = 0U;
}
