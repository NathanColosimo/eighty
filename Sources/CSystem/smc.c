#include "CSystem.h"

#include <IOKit/IOKitLib.h>
#include <math.h>
#include <stdint.h>
#include <string.h>

// Layout of the AppleSMC user-client parameter block (80 bytes).
typedef struct {
  uint32_t key;
  uint8_t vers[6];
  uint8_t pad0[2];
  uint8_t pLimit[16];
  struct { uint32_t dataSize, dataType; uint8_t dataAttributes; } keyInfo;
  uint8_t result, status, data8;
  uint32_t data32;
  uint8_t bytes[32];
} SMCParam;
_Static_assert(sizeof(SMCParam) == 80, "AppleSMC expects an 80-byte parameter block");

enum { kSMCUserClient = 2, kReadBytes = 5, kReadKeyInfo = 9 };

static io_connect_t gConn;

static int smcOpen(void) {
  if (gConn) return 0;
  io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
  if (!svc) return -1;
  kern_return_t kr = IOServiceOpen(svc, mach_task_self(), 0, &gConn);
  IOObjectRelease(svc);
  return kr == KERN_SUCCESS ? 0 : -1;
}

static int call(SMCParam *in, SMCParam *out) {
  size_t size = sizeof(*out);
  kern_return_t kr = IOConnectCallStructMethod(gConn, kSMCUserClient, in, sizeof(*in), out, &size);
  return kr == KERN_SUCCESS && out->result == 0 ? 0 : -1;
}

static double readFloatKey(const char *name) {
  uint32_t key = (uint32_t)name[0] << 24 | (uint32_t)name[1] << 16 | (uint32_t)name[2] << 8 | (uint32_t)name[3];
  SMCParam in = {0}, out = {0};
  in.key = key;
  in.data8 = kReadKeyInfo;
  if (call(&in, &out) != 0 || out.keyInfo.dataSize != 4 || out.keyInfo.dataType != 0x666c7420 /* "flt " */) return NAN;
  uint32_t size = out.keyInfo.dataSize;
  memset(&in, 0, sizeof in);
  memset(&out, 0, sizeof out);
  in.key = key;
  in.keyInfo.dataSize = size;
  in.data8 = kReadBytes;
  if (call(&in, &out) != 0) return NAN;
  float value;
  memcpy(&value, out.bytes, sizeof value);
  return value;
}

double bg_battery_temp_c(void) {
  if (smcOpen() != 0) return NAN;
  static const char *keys[] = {"TB0T", "TB1T", "TB2T"};
  double hottest = NAN;
  for (size_t i = 0; i < sizeof keys / sizeof *keys; i++) {
    double t = readFloatKey(keys[i]);
    // Sensors read 0 or garbage when absent; real battery temps sit well inside this range.
    if (isfinite(t) && t > 0 && t < 100 && !(t <= hottest)) hottest = t;
  }
  return hottest;
}
