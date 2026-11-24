#pragma once

// Darwin notifications, used to wake the daemon when the config changes.
#include <notify.h>

// Battery temperature from the SMC, in °C: the hottest of the battery sensors.
// Returns NAN when no battery sensor can be read. Does not need root.
double bg_battery_temp_c(void);

// macOS's built-in charge limit, owned by the root PowerUIAgent.
// Each function returns 0 on success, or -1 and fills err (NUL-terminated).
int bg_limit_read(int *limit, int *enabled, char *err, int errlen);
int bg_limit_disable(char *err, int errlen);

// Sets an exact target (10-99). Must run as root: it writes PowerUIAgent's own
// preferences, then turns the limit on if it was off. The System Settings
// slider API clamps targets below 80, which the heat pause needs.
int bg_limit_set_exact(int limit, char *err, int errlen);
