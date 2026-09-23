#include "battery_status.h"

#include <errno.h>

#include <zephyr/devicetree.h>
#include <zephyr/sys/util.h>

#include "bq27220.h"

#define BQ27220_NODE DT_NODELABEL(bq27220)

static const struct i2c_dt_spec fuel_gauge_i2c = I2C_DT_SPEC_GET(BQ27220_NODE);
static struct bq27220 fuel_gauge;
static bool fuel_gauge_available;

int battery_status_init(void)
{
	int ret;

	ret = bq27220_init(&fuel_gauge, &fuel_gauge_i2c);
	fuel_gauge_available = (ret == 0);

	return ret;
}

int battery_status_read_percent(uint8_t *percent)
{
	uint16_t soc_pct;
	int ret;

	if (!percent) {
		return -EINVAL;
	}

	if (!fuel_gauge_available) {
		ret = bq27220_init(&fuel_gauge, &fuel_gauge_i2c);
		if (ret != 0) {
			return ret;
		}
		fuel_gauge_available = true;
	}

	ret = bq27220_read_state_of_charge_pct(&fuel_gauge, &soc_pct);
	if (ret != 0) {
		fuel_gauge_available = false;
		return ret;
	}

	*percent = (uint8_t)MIN(soc_pct, 100U);
	return 0;
}
