#include "bq27220.h"

#include <errno.h>
#include <string.h>

#include <zephyr/kernel.h>

#define BQ27220_CMD_CONTROL 0x00
#define BQ27220_CMD_TEMPERATURE 0x06
#define BQ27220_CMD_VOLTAGE 0x08
#define BQ27220_CMD_BATTERY_STATUS 0x0a
#define BQ27220_CMD_CURRENT 0x0c
#define BQ27220_CMD_REMAINING_CAPACITY 0x10
#define BQ27220_CMD_FULL_CHARGE_CAPACITY 0x12
#define BQ27220_CMD_TIME_TO_EMPTY 0x16
#define BQ27220_CMD_CYCLE_COUNT 0x2a
#define BQ27220_CMD_STATE_OF_CHARGE 0x2c
#define BQ27220_CMD_STATE_OF_HEALTH 0x2e
#define BQ27220_CMD_OPERATION_STATUS 0x3a

#define BQ27220_I2C_WAIT_US 66

static uint16_t bq27220_get_le16(const uint8_t data[2])
{
	return (uint16_t)data[0] | ((uint16_t)data[1] << 8);
}

static void bq27220_put_le16(uint8_t data[2], uint16_t value)
{
	data[0] = (uint8_t)value;
	data[1] = (uint8_t)(value >> 8);
}

int bq27220_init(struct bq27220 *gauge, const struct i2c_dt_spec *i2c)
{
	uint16_t voltage_mv;

	if (!gauge || !i2c) {
		return -EINVAL;
	}

	gauge->i2c = *i2c;

	if (!bq27220_is_ready(gauge)) {
		return -ENODEV;
	}

	return bq27220_read_voltage_mv(gauge, &voltage_mv);
}

bool bq27220_is_ready(const struct bq27220 *gauge)
{
	return gauge && i2c_is_ready_dt(&gauge->i2c);
}

int bq27220_read_word(const struct bq27220 *gauge, uint8_t command, uint16_t *value)
{
	uint8_t data[2];
	int ret;

	if (!gauge || !value) {
		return -EINVAL;
	}

	if (!bq27220_is_ready(gauge)) {
		return -ENODEV;
	}

	ret = i2c_write_read_dt(&gauge->i2c, &command, sizeof(command), data, sizeof(data));
	k_busy_wait(BQ27220_I2C_WAIT_US);
	if (ret != 0) {
		return ret;
	}

	*value = bq27220_get_le16(data);
	return 0;
}

int bq27220_write_word(const struct bq27220 *gauge, uint8_t command, uint16_t value)
{
	uint8_t data[3];
	int ret;

	if (!gauge) {
		return -EINVAL;
	}

	if (!bq27220_is_ready(gauge)) {
		return -ENODEV;
	}

	data[0] = command;
	bq27220_put_le16(&data[1], value);

	ret = i2c_write_dt(&gauge->i2c, data, sizeof(data));
	k_busy_wait(BQ27220_I2C_WAIT_US);

	return ret;
}

int bq27220_control(const struct bq27220 *gauge, enum bq27220_subcommand subcommand)
{
	return bq27220_write_word(gauge, BQ27220_CMD_CONTROL, (uint16_t)subcommand);
}

int bq27220_read_voltage_mv(const struct bq27220 *gauge, uint16_t *voltage_mv)
{
	return bq27220_read_word(gauge, BQ27220_CMD_VOLTAGE, voltage_mv);
}

int bq27220_read_current_ma(const struct bq27220 *gauge, int16_t *current_ma)
{
	uint16_t raw;
	int ret;

	if (!current_ma) {
		return -EINVAL;
	}

	ret = bq27220_read_word(gauge, BQ27220_CMD_CURRENT, &raw);
	if (ret != 0) {
		return ret;
	}

	*current_ma = (int16_t)raw;
	return 0;
}

int bq27220_read_state_of_charge_pct(const struct bq27220 *gauge, uint16_t *soc_pct)
{
	return bq27220_read_word(gauge, BQ27220_CMD_STATE_OF_CHARGE, soc_pct);
}

int bq27220_read_sample(const struct bq27220 *gauge, struct bq27220_sample *sample)
{
	uint16_t current_raw;
	int ret;

	if (!sample) {
		return -EINVAL;
	}

	memset(sample, 0, sizeof(*sample));

	ret = bq27220_read_word(gauge, BQ27220_CMD_VOLTAGE, &sample->voltage_mv);
	if (ret != 0) {
		return ret;
	}

	ret = bq27220_read_word(gauge, BQ27220_CMD_CURRENT, &current_raw);
	if (ret != 0) {
		return ret;
	}
	sample->current_ma = (int16_t)current_raw;

	ret = bq27220_read_word(gauge, BQ27220_CMD_TEMPERATURE, &sample->temperature_dk);
	if (ret != 0) {
		return ret;
	}
	sample->temperature_c_x10 = (int16_t)sample->temperature_dk - 2731;

	ret = bq27220_read_word(gauge, BQ27220_CMD_REMAINING_CAPACITY,
				&sample->remaining_capacity_mah);
	if (ret != 0) {
		return ret;
	}

	ret = bq27220_read_word(gauge, BQ27220_CMD_FULL_CHARGE_CAPACITY,
				&sample->full_charge_capacity_mah);
	if (ret != 0) {
		return ret;
	}

	ret = bq27220_read_word(gauge, BQ27220_CMD_STATE_OF_CHARGE,
				&sample->state_of_charge_pct);
	if (ret != 0) {
		return ret;
	}

	ret = bq27220_read_word(gauge, BQ27220_CMD_STATE_OF_HEALTH,
				&sample->state_of_health_pct);
	if (ret != 0) {
		return ret;
	}

	ret = bq27220_read_word(gauge, BQ27220_CMD_TIME_TO_EMPTY,
				&sample->time_to_empty_min);
	if (ret != 0) {
		return ret;
	}

	ret = bq27220_read_word(gauge, BQ27220_CMD_CYCLE_COUNT, &sample->cycle_count);
	if (ret != 0) {
		return ret;
	}

	ret = bq27220_read_word(gauge, BQ27220_CMD_BATTERY_STATUS,
				&sample->battery_status);
	if (ret != 0) {
		return ret;
	}

	return bq27220_read_word(gauge, BQ27220_CMD_OPERATION_STATUS,
				 &sample->operation_status);
}
