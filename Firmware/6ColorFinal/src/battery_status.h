#ifndef BATTERY_STATUS_H
#define BATTERY_STATUS_H

#include <stdint.h>

int battery_status_init(void);
int battery_status_read_percent(uint8_t *percent);

#endif
