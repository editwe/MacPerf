#ifndef MacPerfBridge_h
#define MacPerfBridge_h

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Opens a read-only connection to the AppleSMC user client. Safe to call repeatedly.
int macperf_smc_available(void);

/// Returns max CPU, GPU and battery temperatures in Celsius.
/// Returns the number of valid CPU / GPU sensors through cpu_count / gpu_count.
int macperf_smc_read_temps(double *cpu_max, double *gpu_max, double *battery,
                           int *cpu_count, int *gpu_count);

/// Reads one SMC key as a scalar. Returns NAN when unavailable.
double macperf_smc_read_key(const char *key);

#ifdef __cplusplus
}
#endif

#endif
