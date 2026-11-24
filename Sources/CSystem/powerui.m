// PowerUI.framework is private, so it is loaded at runtime and called through
// the ObjC runtime. Selectors and preference keys match macOS 27 (see the
// batt project's pkg/powerui for the same mechanism).
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <notify.h>
#import <objc/message.h>
#include <unistd.h>

#include "CSystem.h"

static CFStringRef const kDomain = CFSTR("com.apple.smartcharging.topoffprotection");

static int fail(char *err, int errlen, NSString *message) {
  if (err && errlen > 0) strlcpy(err, message.UTF8String, (size_t)errlen);
  return -1;
}

static int failWith(char *err, int errlen, NSError *error, NSString *fallback) {
  return fail(err, errlen, error ? error.localizedDescription : fallback);
}

static id client(void) {
  static id instance;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    if (!dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/Versions/A/PowerUI", RTLD_NOW)) return;
    Class cls = NSClassFromString(@"PowerUISmartChargeClient");
    if (!cls) return;
    id c = ((id (*)(id, SEL, id))objc_msgSend)([cls alloc], sel_registerName("initWithClientName:"), @"eighty");
    for (NSString *sel in @[ @"getMCLLimitWithError:", @"isMCLCurrentlyEnabled:", @"enableMCL:", @"disableMCL:" ]) {
      if (![c respondsToSelector:NSSelectorFromString(sel)]) return;
    }
    instance = c;
  });
  return instance;
}

int bg_limit_read(int *limit, int *enabled, char *err, int errlen) {
  @autoreleasepool {
    id c = client();
    if (!c) return fail(err, errlen, @"macOS charge-limit service is unavailable");
    NSError *error = nil;
    unsigned char value = ((unsigned char (*)(id, SEL, NSError **))objc_msgSend)(c, sel_registerName("getMCLLimitWithError:"), &error);
    if (error) return failWith(err, errlen, error, @"");
    unsigned long long on = ((unsigned long long (*)(id, SEL, NSError **))objc_msgSend)(c, sel_registerName("isMCLCurrentlyEnabled:"), &error);
    if (error) return failWith(err, errlen, error, @"");
    *limit = value;
    *enabled = on ? 1 : 0;
    return 0;
  }
}

static int callBool(const char *selector, char *err, int errlen) {
  id c = client();
  if (!c) return fail(err, errlen, @"macOS charge-limit service is unavailable");
  NSError *error = nil;
  BOOL ok = ((BOOL (*)(id, SEL, NSError **))objc_msgSend)(c, sel_registerName(selector), &error);
  if (!ok || error) return failWith(err, errlen, error, [NSString stringWithFormat:@"%s failed", selector]);
  return 0;
}

int bg_limit_disable(char *err, int errlen) {
  @autoreleasepool {
    return callBool("disableMCL:", err, errlen);
  }
}

int bg_limit_set_exact(int limit, char *err, int errlen) {
  @autoreleasepool {
    if (limit < 10 || limit > 99) return fail(err, errlen, @"exact target must be 10-99");
    if (geteuid() != 0) return fail(err, errlen, @"setting an exact charge target needs root");

    int current = 0, enabled = 0;
    if (bg_limit_read(&current, &enabled, err, errlen) != 0) return -1;
    // enableMCL resets the target to Apple's 80% default; the preference
    // reload below replaces it.
    if (!enabled && callBool("enableMCL:", err, errlen) != 0) return -1;

    // Root's own preference domain, which the root PowerUIAgent reads.
    CFPreferencesSetValue(CFSTR("MCLFeatureState"), (__bridge CFNumberRef)@1, kDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSetValue(CFSTR("mclLimitValue"), (__bridge CFNumberRef)@(limit), kDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (!CFPreferencesSynchronize(kDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)) {
      return fail(err, errlen, @"could not save the charge target");
    }
    if (notify_post("com.apple.smartcharging.defaultschanged") != NOTIFY_STATUS_OK) {
      return fail(err, errlen, @"could not tell PowerUIAgent about the new target");
    }
    return 0;
  }
}
