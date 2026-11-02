// Adapted from Hidden Bar's HBNativeVisibilityShim (MIT, Dwarves Foundation):
// https://github.com/dwarvesf/hidden
//
// MenuBarClientCore backs macOS 27's assessment (exam lockdown) mode, which can limit
// the menu bar to an allow-list. Everything is resolved at runtime, so a macOS release
// that changes it makes Tuck fall back to its own method instead of failing to launch.
#import "TuckMenuBarVisibility.h"
#import <dlfcn.h>
#import <objc/message.h>

static NSString *const FrameworkPath = @"/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore";
static NSString *const ConfigurationClass = @"MBAssessmentModeConfiguration";
static NSString *const AssertionClass = @"MBAssessmentModeAssertion";

static SEL ConfigurationInit(void) { return NSSelectorFromString(@"initWithAllowedSystemItems:allowedBundleIdentifiers:"); }
static SEL Activate(void) { return NSSelectorFromString(@"activateWithConfiguration:completionHandler:"); }
static SEL Invalidate(void) { return NSSelectorFromString(@"invalidate"); }

static NSError *VisibilityError(NSString *reason) {
    return [NSError errorWithDomain:@"TuckMenuBarVisibility" code:1 userInfo:@{NSLocalizedDescriptionKey: reason}];
}

BOOL TuckMenuBarVisibilityIsAvailable(void) {
    if (!dlopen(FrameworkPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL)) return NO;
    Class configuration = NSClassFromString(ConfigurationClass);
    Class assertion = NSClassFromString(AssertionClass);
    return configuration && assertion
        && [configuration instancesRespondToSelector:ConfigurationInit()]
        && [assertion instancesRespondToSelector:Activate()]
        && [assertion instancesRespondToSelector:Invalidate()];
}

void TuckMenuBarVisibilityActivate(NSArray<NSNumber *> *allowedSystemItems,
                                   NSArray<NSString *> *allowedBundleIdentifiers,
                                   void (^completion)(id _Nullable, NSError * _Nullable)) {
    void (^finish)(id, NSError *) = ^(id assertion, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(assertion, error); });
    };
    if (!TuckMenuBarVisibilityIsAvailable()) {
        finish(nil, VisibilityError(@"MenuBarClientCore is unavailable on this macOS"));
        return;
    }
    @try {
        // Both must be NSArrays: the framework indexes into them.
        id configuration = ((id (*)(id, SEL, NSArray *, NSArray *))objc_msgSend)(
            [NSClassFromString(ConfigurationClass) alloc], ConfigurationInit(),
            [allowedSystemItems copy], [allowedBundleIdentifiers copy]);
        id assertion = [[NSClassFromString(AssertionClass) alloc] init];
        if (!configuration || !assertion) {
            finish(nil, VisibilityError(@"Could not create the visibility configuration"));
            return;
        }
        ((void (*)(id, SEL, id, void (^)(NSError *)))objc_msgSend)(
            assertion, Activate(), configuration, ^(NSError *error) {
                finish(error ? nil : assertion, error);
            });
    } @catch (NSException *exception) {
        finish(nil, VisibilityError([NSString stringWithFormat:@"%@: %@", exception.name, exception.reason]));
    }
}

void TuckMenuBarVisibilityInvalidate(id assertion) {
    @try {
        if ([assertion respondsToSelector:Invalidate()]) {
            ((void (*)(id, SEL))objc_msgSend)(assertion, Invalidate());
        }
    } @catch (NSException *exception) {
        NSLog(@"Tuck: invalidating the menu bar restriction raised %@", exception.reason);
    }
}
