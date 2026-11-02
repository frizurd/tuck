// Bridge to macOS 27's menu bar visibility restriction (MenuBarClientCore).
// Adapted from Hidden Bar's HBNativeVisibilityShim (MIT, Dwarves Foundation):
// https://github.com/dwarvesf/hidden
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// True when the private framework and the expected classes and selectors exist.
BOOL TuckMenuBarVisibilityIsAvailable(void);

/// Keeps only these system items and app bundles in the menu bar until the returned
/// assertion is invalidated or this process exits. `completion` runs on the main queue.
void TuckMenuBarVisibilityActivate(NSArray<NSNumber *> *allowedSystemItems,
                                   NSArray<NSString *> *allowedBundleIdentifiers,
                                   void (^completion)(id _Nullable assertion, NSError * _Nullable error));

void TuckMenuBarVisibilityInvalidate(id assertion);

NS_ASSUME_NONNULL_END
