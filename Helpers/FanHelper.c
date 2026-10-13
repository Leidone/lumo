// Lumo fan helper — the only piece of Lumo that runs as root.
//
// Installed root-owned at /Library/PrivilegedHelperTools/app.lumo.fan and allowed through
// /etc/sudoers.d/lumo. It accepts exactly two commands and validates them strictly:
//   app.lumo.fan auto <fan>          hand the fan back to macOS
//   app.lumo.fan set <fan> <rpm>     manual speed, clamped to the fan's own min/max
// Exit codes: 0 ok, 64 usage, 69 SMC unavailable, 70 SMC refused the write.

#include <IOKit/IOKitLib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    UInt32 dataSize;
    UInt32 dataType;
    UInt8 dataAttributes;
} KeyInfo;

typedef struct {
    UInt32 key;
    UInt8 version[6];
    UInt16 limitsVersion;
    UInt16 limitsLength;
    UInt32 cpuPLimit;
    UInt32 gpuPLimit;
    UInt32 memPLimit;
    KeyInfo keyInfo;
    UInt8 result;
    UInt8 status;
    UInt8 data8;
    UInt32 data32;
    UInt8 bytes[32];
} KeyData;

enum { kHandleEvent = 2, kReadKey = 5, kWriteKey = 6, kReadKeyInfo = 9, kMaxFans = 4 };

static io_connect_t connection;

static UInt32 fourCC(const char *code) {
    return ((UInt32)code[0] << 24) | ((UInt32)code[1] << 16) | ((UInt32)code[2] << 8) | (UInt32)code[3];
}

static int call(KeyData *input, KeyData *output) {
    size_t size = sizeof(KeyData);
    memset(output, 0, sizeof(KeyData));
    kern_return_t result = IOConnectCallStructMethod(connection, kHandleEvent, input, sizeof(KeyData), output, &size);
    return result == kIOReturnSuccess && output->result == 0;
}

static int keyInfo(const char *key, KeyInfo *info) {
    KeyData input = {0}, output;
    input.key = fourCC(key);
    input.data8 = kReadKeyInfo;
    if (!call(&input, &output)) return 0;
    *info = output.keyInfo;
    return 1;
}

static int readValue(const char *key, double *value) {
    KeyInfo info;
    if (!keyInfo(key, &info)) return 0;
    KeyData input = {0}, output;
    input.key = fourCC(key);
    input.keyInfo.dataSize = info.dataSize;
    input.data8 = kReadKey;
    if (!call(&input, &output)) return 0;
    if (info.dataType == fourCC("flt ") && info.dataSize >= 4) {
        float number;
        memcpy(&number, output.bytes, 4);
        *value = number;
    } else if (info.dataType == fourCC("fpe2") && info.dataSize >= 2) {
        *value = (double)(((UInt16)output.bytes[0] << 8 | output.bytes[1]) >> 2);
    } else if (info.dataType == fourCC("ui8 ")) {
        *value = output.bytes[0];
    } else {
        return 0;
    }
    return 1;
}

static int writeValue(const char *key, double value) {
    KeyInfo info;
    if (!keyInfo(key, &info)) return 0;
    KeyData input = {0}, output;
    input.key = fourCC(key);
    input.keyInfo.dataSize = info.dataSize;
    input.data8 = kWriteKey;
    if (info.dataType == fourCC("flt ") && info.dataSize == 4) {
        float number = (float)value;
        memcpy(input.bytes, &number, 4);
    } else if (info.dataType == fourCC("fpe2") && info.dataSize == 2) {
        UInt16 raw = (UInt16)value << 2;
        input.bytes[0] = raw >> 8;
        input.bytes[1] = raw & 0xFF;
    } else if (info.dataType == fourCC("ui8 ") && info.dataSize == 1) {
        input.bytes[0] = (UInt8)value;
    } else {
        return 0;
    }
    return call(&input, &output);
}

/// Apple silicon names the mode key "F0md", Intel "F0Md".
static int setMode(int fan, int manual) {
    char key[5];
    snprintf(key, sizeof key, "F%dMd", fan);
    if (writeValue(key, manual)) return 1;
    snprintf(key, sizeof key, "F%dmd", fan);
    return writeValue(key, manual);
}

static int parseInt(const char *text, long low, long high, long *out) {
    char *end = NULL;
    long value = strtol(text, &end, 10);
    if (!text[0] || *end != '\0' || value < low || value > high) return 0;
    *out = value;
    return 1;
}

int main(int argc, char **argv) {
    long fan = 0, rpm = 0;
    int isAuto = argc == 3 && strcmp(argv[1], "auto") == 0;
    int isSet = argc == 4 && strcmp(argv[1], "set") == 0;
    if ((!isAuto && !isSet) || !parseInt(argv[2], 0, kMaxFans - 1, &fan) || (isSet && !parseInt(argv[3], 0, 20000, &rpm))) {
        fprintf(stderr, "usage: app.lumo.fan auto <fan> | set <fan> <rpm>\n");
        return 64;
    }

    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service || IOServiceOpen(service, mach_task_self(), 0, &connection) != kIOReturnSuccess) return 69;
    IOObjectRelease(service);

    double count = 0;
    if (!readValue("FNum", &count) || fan >= (long)count) {
        IOServiceClose(connection);
        return 64;
    }

    int ok;
    if (isAuto) {
        ok = setMode((int)fan, 0);
        writeValue("Ftst", 0); // Intel test mode off; absent on Apple silicon.
    } else {
        char key[5];
        double minimum = 0, maximum = 0;
        snprintf(key, sizeof key, "F%ldMn", fan);
        readValue(key, &minimum);
        snprintf(key, sizeof key, "F%ldMx", fan);
        readValue(key, &maximum);
        if (maximum <= 0) maximum = 7000;
        double target = rpm < minimum ? minimum : (rpm > maximum ? maximum : rpm);
        writeValue("Ftst", 1);
        ok = setMode((int)fan, 1);
        snprintf(key, sizeof key, "F%ldTg", fan);
        ok = writeValue(key, target) && ok;
    }
    IOServiceClose(connection);
    return ok ? 0 : 70;
}
