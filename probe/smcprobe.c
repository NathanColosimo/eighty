// Read-only SMC probe: lists keys matching a prefix and decodes values.
// Never writes to the SMC.
//   clang -O2 -framework IOKit -o smcprobe smcprobe.c
//   ./smcprobe            # battery temps + charge-control keys
//   ./smcprobe all T      # every key starting with T
#include <IOKit/IOKitLib.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } SMCVers;
typedef struct { uint16_t version, length; uint32_t cpuPLimit, gpuPLimit, memPLimit; } SMCPLimit;
typedef struct { uint32_t dataSize, dataType; uint8_t dataAttributes; } SMCKeyInfo;
typedef struct {
  uint32_t key;
  SMCVers vers;
  SMCPLimit pLimitData;
  SMCKeyInfo keyInfo;
  uint8_t result, status, data8;
  uint32_t data32;
  uint8_t bytes[32];
} SMCParam;

enum { kSMCUserClient = 2, kReadBytes = 5, kReadIndex = 8, kReadKeyInfo = 9 };

static io_connect_t conn;

static uint32_t fourcc(const char *s) { return (uint32_t)s[0] << 24 | (uint32_t)s[1] << 16 | (uint32_t)s[2] << 8 | (uint32_t)s[3]; }
static void unfourcc(uint32_t v, char out[5]) { for (int i = 0; i < 4; i++) out[i] = (char)(v >> (24 - 8 * i)); out[4] = 0; }

static kern_return_t call(SMCParam *in, SMCParam *out) {
  size_t outSize = sizeof(*out);
  return IOConnectCallStructMethod(conn, kSMCUserClient, in, sizeof(*in), out, &outSize);
}

// Returns 0 on success; fills info and bytes.
static int readKey(uint32_t key, SMCKeyInfo *info, uint8_t bytes[32]) {
  SMCParam in = {0}, out = {0};
  in.key = key; in.data8 = kReadKeyInfo;
  if (call(&in, &out) != KERN_SUCCESS || out.result != 0) return -1;
  *info = out.keyInfo;
  memset(&in, 0, sizeof in); memset(&out, 0, sizeof out);
  in.key = key; in.keyInfo.dataSize = info->dataSize; in.data8 = kReadBytes;
  kern_return_t kr = call(&in, &out);
  if (kr != KERN_SUCCESS) return (int)kr;
  if (out.result != 0) return 1000 + out.result;
  memcpy(bytes, out.bytes, 32);
  return 0;
}

static void show(uint32_t key) {
  SMCKeyInfo info; uint8_t b[32];
  char k[5], t[5]; unfourcc(key, k);
  int rc = readKey(key, &info, b);
  if (rc == -1) { printf("%s  (absent)\n", k); return; }
  unfourcc(info.dataType, t);
  if (rc != 0) { printf("%s  %-4s size=%u  READ FAILED rc=%d\n", k, t, info.dataSize, rc); return; }
  printf("%s  %-4s size=%-2u attr=0x%02x  raw=", k, t, info.dataSize, info.dataAttributes);
  for (uint32_t i = 0; i < info.dataSize && i < 32; i++) printf("%02x", b[i]);
  if (!strcmp(t, "flt ") && info.dataSize == 4) { float f; memcpy(&f, b, 4); printf("  = %.2f", f); }
  if (!strcmp(t, "ui8 ")) printf("  = %u", b[0]);
  if (!strcmp(t, "sp78")) printf("  = %.2f", (int16_t)(b[0] << 8 | b[1]) / 256.0);
  printf("\n");
}

int main(int argc, char **argv) {
  io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
  if (!svc || IOServiceOpen(svc, mach_task_self(), 0, &conn) != KERN_SUCCESS) { fprintf(stderr, "cannot open AppleSMC\n"); return 1; }

  if (argc == 3 && !strcmp(argv[1], "all")) {
    SMCKeyInfo info; uint8_t b[32];
    readKey(fourcc("#KEY"), &info, b);
    uint32_t n = (uint32_t)b[0] << 24 | b[1] << 16 | b[2] << 8 | b[3];
    printf("%u keys\n", n);
    size_t plen = strlen(argv[2]);
    for (uint32_t i = 0; i < n; i++) {
      SMCParam in = {0}, out = {0};
      in.data8 = kReadIndex; in.data32 = i;
      if (call(&in, &out) != KERN_SUCCESS) continue;
      char k[5]; unfourcc(out.key, k);
      if (!strncmp(k, argv[2], plen)) show(out.key);
    }
    return 0;
  }

  const char *keys[] = {
    // battery temperature candidates
    "TB0T", "TB1T", "TB2T", "TB3T",
    // charge control (legacy, Tahoe, macOS 27 firmware limit)
    "CH0B", "CH0C", "CHTE", "bfF0", "bfD0", "bfE0",
    // adapter (wall power) control
    "CH0I", "CH0J", "CHIE",
    // battery %, wall power present, battery power
    "BUIC", "AC-W", "PPBR", "B0AC",
  };
  for (size_t i = 0; i < sizeof keys / sizeof *keys; i++) show(fourcc(keys[i]));
  return 0;
}
