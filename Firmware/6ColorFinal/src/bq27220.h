#ifndef BQ27220_H
#define BQ27220_H

#include <stdint.h>

#include <zephyr/drivers/i2c.h>

#define BQ27220_I2C_ADDR 0x55

enum bq27220_subcommand {
	BQ27220_SUBCMD_CONTROL_STATUS = 0x0000,
	BQ27220_SUBCMD_DEVICE_NUMBER = 0x0001,
	BQ27220_SUBCMD_FW_VERSION = 0x0002,
	BQ27220_SUBCMD_HW_VERSION = 0x0003,
	BQ27220_SUBCMD_OCV = 0x000c,
	BQ27220_SUBCMD_BAT_INSERT = 0x000d,
	BQ27220_SUBCMD_BAT_REMOVE = 0x000e,
	BQ27220_SUBCMD_SET_PROFILE_1 = 0x0015,
	BQ27220_SUBCMD_SET_PROFILE_2 = 0x0016,
	BQ27220_SUBCMD_SET_PROFILE_3 = 0x0017,
	BQ27220_SUBCMD_SEALED = 0x0030,
	BQ27220_SUBCMD_RESET = 0x0041,
	BQ27220_SUBCMD_OPERATION_STATUS = 0x0054,
	BQ27220_SUBCMD_GAUGING_STATUS = 0x0056,
	BQ27220_SUBCMD_ENTER_CFG_UPDATE = 0x0090,
	BQ27220_SUBCMD_EXIT_CFG_UPDATE_REINIT = 0x0091,
	BQ27220_SUBCMD_EXIT_CFG_UPDATE = 0x0092,
};

struct bq27220 {
	struct i2c_dt_spec i2c;
};

struct bq27220_sample {
	uint16_t voltage_mv;
	int16_t current_ma;
	uint16_t temperature_dk;
	int16_t temperature_c_x10;
	uint16_t remaining_capacity_mah;
	uint16_t full_charge_capacity_mah;
	uint16_t state_of_charge_pct;
	uint16_t state_of_health_pct;
	uint16_t time_to_empty_min;
	uint16_t cycle_count;
	uint16_t battery_status;
	uint16_t operation_status;
};

int bq27220_init(struct bq27220 *gauge, const struct i2c_dt_spec *i2c);
bool bq27220_is_ready(const struct bq27220 *gauge);

int bq27220_read_word(const struct bq27220 *gauge, uint8_t command, uint16_t *value);
int bq27220_write_word(const struct bq27220 *gauge, uint8_t command, uint16_t value);
int bq27220_control(const struct bq27220 *gauge, enum bq27220_subcommand subcommand);

int bq27220_read_voltage_mv(const struct bq27220 *gauge, uint16_t *voltage_mv);
int bq27220_read_current_ma(const struct bq27220 *gauge, int16_t *current_ma);
int bq27220_read_state_of_charge_pct(const struct bq27220 *gauge, uint16_t *soc_pct);
int bq27220_read_sample(const struct bq27220 *gauge, struct bq27220_sample *sample);

#endif
