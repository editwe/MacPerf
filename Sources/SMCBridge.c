// Read-only AppleSMC access for MacPerf.
// The struct layout mirrors the kernel's SMCKeyData_t ABI and is intentionally
// kept in C so the Swift side never has to guess at field offsets.

#include "Bridge.h"

#include <IOKit/IOKitLib.h>
#include <math.h>
#include <pthread.h>
#include <stdint.h>
#include <string.h>

#define SMC_KERNEL_INDEX 2
#define SMC_CMD_READ_BYTES 5
#define SMC_CMD_READ_KEYINFO 9
#define SMC_KEY_INFO_CACHE_SIZE 192

typedef struct {
    char major;
    char minor;
    char build;
    char reserved[1];
    uint16_t release;
} SMCVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} SMCPLimitData;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    char dataAttributes;
} SMCKeyInfo;

typedef struct {
    uint32_t key;
    SMCVersion vers;
    SMCPLimitData pLimitData;
    SMCKeyInfo keyInfo;
    char result;
    char status;
    char data8;
    uint32_t data32;
    unsigned char bytes[32];
} SMCKeyData;

typedef struct {
    uint32_t key;
    uint32_t size;
    uint32_t type;
    int valid;
} KeyCacheEntry;

static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static io_connect_t g_conn = 0;
static int g_open_attempted = 0;
static KeyCacheEntry g_cache[SMC_KEY_INFO_CACHE_SIZE];
static int g_cache_count = 0;

static uint32_t fourcc(const char *key) {
    return ((uint32_t)(unsigned char)key[0] << 24) |
           ((uint32_t)(unsigned char)key[1] << 16) |
           ((uint32_t)(unsigned char)key[2] << 8) |
           ((uint32_t)(unsigned char)key[3]);
}

static void fourcc_string(uint32_t value, char out[5]) {
    out[0] = (char)((value >> 24) & 0xFF);
    out[1] = (char)((value >> 16) & 0xFF);
    out[2] = (char)((value >> 8) & 0xFF);
    out[3] = (char)(value & 0xFF);
    out[4] = '\0';
}

static kern_return_t smc_call(SMCKeyData *input, SMCKeyData *output) {
    size_t output_size = sizeof(SMCKeyData);
    return IOConnectCallStructMethod(g_conn, SMC_KERNEL_INDEX,
                                     input, sizeof(SMCKeyData),
                                     output, &output_size);
}

static int ensure_open_locked(void) {
    if (g_conn != 0) {
        return 1;
    }
    if (g_open_attempted) {
        return 0;
    }
    g_open_attempted = 1;

    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                       IOServiceMatching("AppleSMC"));
    if (service == 0) {
        return 0;
    }
    kern_return_t kr = IOServiceOpen(service, mach_task_self(), 0, &g_conn);
    IOObjectRelease(service);
    if (kr != KERN_SUCCESS) {
        g_conn = 0;
        return 0;
    }
    return 1;
}

static KeyCacheEntry *cache_lookup(uint32_t key) {
    for (int i = 0; i < g_cache_count; i++) {
        if (g_cache[i].key == key) {
            return &g_cache[i];
        }
    }
    return NULL;
}

static int get_key_info_locked(uint32_t key, uint32_t *size, uint32_t *type) {
    KeyCacheEntry *entry = cache_lookup(key);
    if (entry != NULL) {
        if (!entry->valid) {
            return 0;
        }
        *size = entry->size;
        *type = entry->type;
        return 1;
    }
    if (g_cache_count >= SMC_KEY_INFO_CACHE_SIZE) {
        return 0;
    }

    SMCKeyData input;
    SMCKeyData output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.key = key;
    input.data8 = SMC_CMD_READ_KEYINFO;

    kern_return_t kr = smc_call(&input, &output);
    entry = &g_cache[g_cache_count++];
    entry->key = key;
    entry->valid = 0;

    if (kr == KERN_SUCCESS && output.result == 0 && output.keyInfo.dataSize > 0) {
        entry->size = output.keyInfo.dataSize;
        entry->type = output.keyInfo.dataType;
        entry->valid = 1;
        *size = entry->size;
        *type = entry->type;
        return 1;
    }
    return 0;
}

static int read_raw_locked(uint32_t key, unsigned char bytes[32], uint32_t *size_out,
                           uint32_t *type_out) {
    uint32_t size = 0;
    uint32_t type = 0;
    if (!get_key_info_locked(key, &size, &type)) {
        return 0;
    }
    if (size > 32) {
        return 0;
    }

    SMCKeyData input;
    SMCKeyData output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.key = key;
    input.data8 = SMC_CMD_READ_BYTES;
    input.keyInfo.dataSize = size;

    kern_return_t kr = smc_call(&input, &output);
    if (kr != KERN_SUCCESS || output.result != 0) {
        return 0;
    }

    memcpy(bytes, output.bytes, 32);
    *size_out = size;
    *type_out = type;
    return 1;
}

static double decode_scalar(const unsigned char *bytes, uint32_t size, uint32_t type) {
    char t[5];
    fourcc_string(type, t);

    if (size == 4 && strncmp(t, "flt", 3) == 0) {
        float f = 0.0f;
        memcpy(&f, bytes, sizeof(float));
        return (double)f;
    }
    if (size == 2 && strncmp(t, "sp78", 4) == 0) {
        int16_t raw = (int16_t)((uint16_t)bytes[0] << 8 | bytes[1]);
        return (double)raw / 256.0;
    }
    if (size == 2 && strncmp(t, "fpe2", 4) == 0) {
        return (double)((uint16_t)bytes[0] << 8 | bytes[1]) / 4.0;
    }
    if (size == 2 && strncmp(t, "ui16", 4) == 0) {
        return (double)((uint16_t)bytes[0] << 8 | bytes[1]);
    }
    if (size == 2 && strncmp(t, "si16", 4) == 0) {
        return (double)(int16_t)((uint16_t)bytes[0] << 8 | bytes[1]);
    }
    if (size == 1 && strncmp(t, "ui8", 3) == 0) {
        return (double)bytes[0];
    }
    if (size == 1 && strncmp(t, "si8", 3) == 0) {
        return (double)(int8_t)bytes[0];
    }
    if (size == 4 && strncmp(t, "ui32", 4) == 0) {
        return (double)(((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) |
                        ((uint32_t)bytes[2] << 8) | (uint32_t)bytes[3]);
    }
    return NAN;
}

static double read_key_locked(const char *key) {
    unsigned char bytes[32];
    uint32_t size = 0;
    uint32_t type = 0;
    if (!read_raw_locked(fourcc(key), bytes, &size, &type)) {
        return NAN;
    }
    return decode_scalar(bytes, size, type);
}

static const char *kCPUKeys[] = {
    "TC0P", "TC0D", "TC0E", "TC0F",
    "Tc0a", "Tc0b", "Tc0x", "Tc0z",
    "Tp00", "Tp01", "Tp02", "Tp04", "Tp05", "Tp06", "Tp08", "Tp09",
    "Tp0A", "Tp0C", "Tp0D", "Tp0E", "Tp0G", "Tp0H", "Tp0K", "Tp0L",
    "Tp0O", "Tp0P", "Tp0R", "Tp0T", "Tp0U", "Tp0X", "Tp0a", "Tp0b",
    "Tp0d", "Tp0f", "Tp0g", "Tp0j", "Tp0l", "Tp0m", "Tp0n", "Tp0o",
    "Tp0p", "Tp0q", "Tp0r", "Tp0t", "Tp0u", "Tp0y",
    "Tp1h", "Tp1l", "Tp1p", "Tp1t",
    "Tpx0", "Tpx1", "Tpx2", "Tpx3"
};

static const char *kGPUKeys[] = {
    "TG0D", "TPCD",
    "Tg04", "Tg05", "Tg0C", "Tg0D", "Tg0K", "Tg0L", "Tg0P", "Tg0T",
    "Tg0U", "Tg0X", "Tg0b", "Tg0d", "Tg0e", "Tg0f", "Tg0g", "Tg0j",
    "Tg0v", "Tg1Y", "Tg1b", "Tg1c", "Tg1g", "Tg4b"
};

int macperf_smc_available(void) {
    pthread_mutex_lock(&g_lock);
    int ok = ensure_open_locked();
    pthread_mutex_unlock(&g_lock);
    return ok;
}

int macperf_smc_read_temps(double *cpu_max, double *gpu_max, double *battery,
                           int *cpu_count, int *gpu_count) {
    if (cpu_max == NULL || gpu_max == NULL || battery == NULL ||
        cpu_count == NULL || gpu_count == NULL) {
        return 0;
    }
    *cpu_max = 0.0;
    *gpu_max = 0.0;
    *battery = 0.0;
    *cpu_count = 0;
    *gpu_count = 0;

    pthread_mutex_lock(&g_lock);
    if (!ensure_open_locked()) {
        pthread_mutex_unlock(&g_lock);
        return 0;
    }

    int cpu_n = (int)(sizeof(kCPUKeys) / sizeof(kCPUKeys[0]));
    for (int i = 0; i < cpu_n; i++) {
        double value = read_key_locked(kCPUKeys[i]);
        if (isfinite(value) && value > 5.0 && value < 125.0) {
            if (value > *cpu_max) {
                *cpu_max = value;
            }
            (*cpu_count)++;
        }
    }

    int gpu_n = (int)(sizeof(kGPUKeys) / sizeof(kGPUKeys[0]));
    for (int i = 0; i < gpu_n; i++) {
        double value = read_key_locked(kGPUKeys[i]);
        if (isfinite(value) && value > 5.0 && value < 125.0) {
            if (value > *gpu_max) {
                *gpu_max = value;
            }
            (*gpu_count)++;
        }
    }

    double battery_value = read_key_locked("TB0T");
    if (isfinite(battery_value) && battery_value > 0.0 && battery_value < 90.0) {
        *battery = battery_value;
    }

    pthread_mutex_unlock(&g_lock);
    return (*cpu_count > 0 || *gpu_count > 0 || *battery > 0.0);
}

double macperf_smc_read_key(const char *key) {
    if (key == NULL || strlen(key) < 4) {
        return NAN;
    }
    pthread_mutex_lock(&g_lock);
    double value = NAN;
    if (ensure_open_locked()) {
        value = read_key_locked(key);
    }
    pthread_mutex_unlock(&g_lock);
    return value;
}
