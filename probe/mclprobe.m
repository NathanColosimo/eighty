// Read-only probe of macOS's built-in charge limit (PowerUIAgent "MCL").
// Uses the private PowerUI framework the same way batt does. Never sets anything.
//   clang -O2 -fobjc-arc -framework Foundation -o mclprobe mclprobe.m
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/message.h>

int main(void) {
  @autoreleasepool {
    if (!dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/Versions/A/PowerUI", RTLD_NOW)) {
      printf("PowerUI framework missing\n"); return 1;
    }
    Class cls = NSClassFromString(@"PowerUISmartChargeClient");
    if (!cls) { printf("PowerUISmartChargeClient missing\n"); return 1; }
    id c = ((id (*)(id, SEL, id))objc_msgSend)([cls alloc], sel_registerName("initWithClientName:"), @"eighty-probe");

    BOOL supported = ((BOOL (*)(id, SEL))objc_msgSend)(c, sel_registerName("isMCLSupported"));
    printf("isMCLSupported: %d\n", supported);

    NSError *err = nil;
    id limits = ((id (*)(id, SEL, NSError **))objc_msgSend)(c, sel_registerName("availableChargeLimitsWithError:"), &err);
    printf("availableChargeLimits: %s %s\n", [[limits description] UTF8String] ?: "nil", err ? [[err description] UTF8String] : "");

    err = nil;
    unsigned char limit = ((unsigned char (*)(id, SEL, NSError **))objc_msgSend)(c, sel_registerName("getMCLLimitWithError:"), &err);
    printf("getMCLLimit: %u %s\n", limit, err ? [[err description] UTF8String] : "");

    err = nil;
    unsigned long long on = ((unsigned long long (*)(id, SEL, NSError **))objc_msgSend)(c, sel_registerName("isMCLCurrentlyEnabled:"), &err);
    printf("isMCLCurrentlyEnabled: %llu %s\n", on, err ? [[err description] UTF8String] : "");
  }
  return 0;
}
