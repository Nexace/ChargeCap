#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <objc/runtime.h>

// Private ABI inspected on macOS 27.0.1 arm64. Refuse an unrecognized signature.
@interface NSObject (ChargeCapPowerUI)
- (instancetype)initWithClientName:(NSString *)name;
- (NSArray *)availableChargeLimitsWithError:(NSError **)error;
- (unsigned char)getMCLLimitWithError:(NSError **)error;
- (BOOL)setMCLLimit:(unsigned char)limit error:(NSError **)error;
- (NSUInteger)isSmartChargingCurrentlyEnabled:(NSError **)error;
- (BOOL)enableSmartCharging:(NSError **)error;
- (BOOL)disableSmartCharging:(NSError **)error;
@end

static BOOL ValidLimit(NSInteger value) {
    return value >= 80 && value <= 100 && value % 5 == 0;
}

static BOOL HasMethod(Class type, SEL selector, const char *encoding) {
    Method method = class_getInstanceMethod(type, selector);
    return method && strcmp(method_getTypeEncoding(method), encoding) == 0;
}

static id ChargeClient(NSError **error) {
    static void *framework;
    if (!framework) framework = dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", RTLD_LAZY | RTLD_LOCAL);
    Class type = framework ? NSClassFromString(@"PowerUISmartChargeClient") : Nil;
    if (!type || !HasMethod(type, @selector(initWithClientName:), "@24@0:8@16") ||
        !HasMethod(type, @selector(getMCLLimitWithError:), "C24@0:8^@16") ||
        !HasMethod(type, @selector(setMCLLimit:error:), "B28@0:8C16^@20") ||
        !HasMethod(type, @selector(availableChargeLimitsWithError:), "@24@0:8^@16")) {
        if (error) *error = [NSError errorWithDomain:@"ChargeCap" code:1 userInfo:@{NSLocalizedDescriptionKey:
            @"Charge limits aren’t available on this version of macOS. Open Battery Settings to check."}];
        return nil;
    }
    return [[type alloc] initWithClientName:@"ChargeCap"];
}

static NSString *ReadLimit(id client, NSInteger *limit) {
    if (!client) return @"macOS could not connect to battery charge controls.";
    NSError *error = nil;
    unsigned char value = [client getMCLLimitWithError:&error];
    if (error) return error.localizedDescription;
    if (!ValidLimit(value)) return @"macOS returned an unrecognized charge limit. Check Battery Settings.";
    *limit = value;
    return nil;
}

static NSString *ReadOptimized(id client, BOOL *enabled) {
    Class type = [client class];
    if (!HasMethod(type, @selector(isSmartChargingCurrentlyEnabled:), "Q24@0:8^@16"))
        return @"Optimized Battery Charging isn’t available on this macOS version.";
    NSError *error = nil;
    NSUInteger state = [client isSmartChargingCurrentlyEnabled:&error];
    if (error) return error.localizedDescription;
    if (state > 1) return @"macOS returned an unrecognized optimized charging state.";
    *enabled = state == 1;
    return nil;
}

static NSString *WriteOptimized(id client, BOOL enabled) {
    SEL selector = enabled ? @selector(enableSmartCharging:) : @selector(disableSmartCharging:);
    if (!HasMethod([client class], selector, "B24@0:8^@16"))
        return @"Optimized Battery Charging isn’t available on this macOS version.";
    NSError *error = nil;
    BOOL accepted = enabled ? [client enableSmartCharging:&error] : [client disableSmartCharging:&error];
    if (error || !accepted) return error.localizedDescription ?: @"macOS did not accept the optimized charging setting.";
    BOOL actual = NO;
    NSString *issue = ReadOptimized(client, &actual);
    if (issue) return issue;
    return actual == enabled ? nil : @"macOS did not confirm the optimized charging setting.";
}

static NSString *WriteLimit(id client, NSInteger value) {
    if (!ValidLimit(value)) return @"Choose 80%, 85%, 90%, 95%, or 100%.";
    if (!client) return @"macOS could not connect to battery charge controls.";
    NSError *error = nil;
    NSArray *available = [client availableChargeLimitsWithError:&error];
    if (error) return error.localizedDescription;
    if (![available isKindOfClass:[NSArray class]] || ![available containsObject:@(value)])
        return @"This charge limit isn’t currently available on your Mac.";
    if (![client setMCLLimit:(unsigned char)value error:&error])
        return error.localizedDescription ?: @"macOS did not accept this charge limit.";
    if (error) return error.localizedDescription;
    NSInteger actual = 0;
    NSString *readError = ReadLimit(client, &actual);
    if (readError) return readError;
    if (actual != value) return @"The charge limit changed elsewhere or macOS did not confirm it. Check Battery Settings.";
    return nil;
}
