#import "LSHooking.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <math.h>

// ====================================================================
// Strong, fast k7gps UI hider v54
// ====================================================================
// The visible overlay in v53 means the other tweak is likely using a short
// "k7" class/module name or a separate UIWindow/root controller that does not
// expose the full "k7gps" text on its visible labels.  This version restores
// the effective broad class match from the older hook, but keeps it safer and
// faster by matching broad "k7" only on class/identifier/controller names and
// by avoiding our own XsGpS UI.

BOOL LSInstallInstanceHookWithIMP(Class cls, SEL originalSelector, SEL hookSelector, IMP hookIMP);

static IMP ls_originalWillMoveToWindowIMP = NULL;
static IMP ls_originalDidMoveToWindowIMP = NULL;
static IMP ls_originalDidAddSubviewIMP = NULL;
static IMP ls_originalWindowMakeKeyAndVisibleIMP = NULL;
static IMP ls_originalViewSetHiddenIMP = NULL;
static IMP ls_originalViewSetAlphaIMP = NULL;
static dispatch_once_t ls_k7HiderInstallOnceToken;
static NSMutableSet<NSString *> *ls_k7PositiveClassCache = nil;
static NSMutableSet<NSString *> *ls_k7NegativeClassCache = nil;
static BOOL ls_k7ScanPending = NO;
static const NSInteger kLSK7DeepScanDepth = 12;
static const NSInteger kLSK7LightScanDepth = 4;

static CGFloat LSK7ViewScreenAreaRatio(UIView *view);
static BOOL LSK7IsOurToolObject(id object);

static NSString *LSK7NormalizedOverlayText(NSString *string) {
    if (![string isKindOfClass:NSString.class] || string.length == 0) {
        return @"";
    }

    NSCharacterSet *trimSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSString *trimmed = [string stringByTrimmingCharactersInSet:trimSet];
    return trimmed.lowercaseString ?: @"";
}

static BOOL LSK7StringIsPlainGPSBubbleTitle(NSString *string) {
    NSString *normalized = LSK7NormalizedOverlayText(string);
    if (normalized.length == 0) {
        return NO;
    }

    // The competitor bubble shown by the user is a compact circular overlay
    // with the exact title "GPS".  Keep this intentionally exact; broad
    // matches like "Use GPS" would risk hiding normal app UI.
    return [normalized isEqualToString:@"gps"] ||
           [normalized isEqualToString:@"g.p.s"] ||
           [normalized isEqualToString:@"g p s"];
}

static BOOL LSK7StringHasK7GPS(NSString *string) {
    if (![string isKindOfClass:NSString.class] || string.length == 0) {
        return NO;
    }

    NSString *lower = string.lowercaseString;
    return [lower containsString:@"k7gps"] ||
           [lower containsString:@"k7 gps"] ||
           [lower containsString:@"k7-gps"] ||
           [lower containsString:@"k7_gps"] ||
           ([lower containsString:@"k7"] && [lower containsString:@"gps"]);
}

static BOOL LSK7StringHasBroadK7Token(NSString *string) {
    if (![string isKindOfClass:NSString.class] || string.length == 0) {
        return NO;
    }

    NSString *lower = string.lowercaseString;
    if (![lower containsString:@"k7"]) {
        return NO;
    }

    // Avoid matching our own code or common Apple/system classes if a future
    // framework happens to contain the token.
    NSArray<NSString *> *blockedPrefixes = @[
        @"maps", @"mk", @"ui", @"ns", @"_ui", @"_ns", @"wk", @"ca", @"av", @"cb"
    ];
    for (NSString *prefix in blockedPrefixes) {
        if ([lower hasPrefix:prefix]) {
            return NO;
        }
    }

    NSArray<NSString *> *blockedSubstrings = @[
        @"xsgps", @"mappicker", @"bluetoothspoofer", @"wifiscanner", @"uuidmanager"
    ];
    for (NSString *blocked in blockedSubstrings) {
        if ([lower containsString:blocked]) {
            return NO;
        }
    }
    return YES;
}

static BOOL LSK7NameLooksLikeTarget(NSString *string, BOOL allowBroadK7) {
    return LSK7StringHasK7GPS(string) || (allowBroadK7 && LSK7StringHasBroadK7Token(string));
}

static NSString *LSK7ClassName(id object) {
    Class cls = object ? [object class] : Nil;
    return cls ? NSStringFromClass(cls) : nil;
}

static BOOL LSK7ObjectClassLooksLikeTarget(id object) {
    NSString *className = LSK7ClassName(object);
    if (className.length == 0) {
        return NO;
    }

    if ([ls_k7PositiveClassCache containsObject:className]) {
        return YES;
    }
    if ([ls_k7NegativeClassCache containsObject:className]) {
        return NO;
    }

    BOOL match = LSK7NameLooksLikeTarget(className, YES);
    if (match) {
        [ls_k7PositiveClassCache addObject:className];
    } else {
        [ls_k7NegativeClassCache addObject:className];
    }
    return match;
}

static BOOL LSK7ViewMetadataLooksLikeTarget(UIView *view) {
    if (!view) {
        return NO;
    }

    // Identifiers/class names may be short like "k7Button" or "K7Panel".
    if (LSK7NameLooksLikeTarget(view.accessibilityIdentifier, YES) ||
        LSK7NameLooksLikeTarget(view.restorationIdentifier, YES)) {
        return YES;
    }

    // Labels/titles are matched more narrowly to avoid hiding normal UI that
    // happens to contain "k7" as user-visible text.
    if (LSK7StringHasK7GPS(view.accessibilityLabel)) {
        return YES;
    }

    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        return LSK7StringHasK7GPS(label.text) || LSK7StringHasK7GPS(label.attributedText.string);
    }

    if ([view isKindOfClass:UIButton.class]) {
        UIButton *button = (UIButton *)view;
        return LSK7StringHasK7GPS([button titleForState:UIControlStateNormal]) ||
               LSK7StringHasK7GPS([button attributedTitleForState:UIControlStateNormal].string);
    }

    if ([view respondsToSelector:@selector(text)]) {
        id value = nil;
        @try {
            value = [view valueForKey:@"text"];
        } @catch (__unused NSException *exception) {
            value = nil;
        }
        if (LSK7StringHasK7GPS([value isKindOfClass:NSString.class] ? value : nil)) {
            return YES;
        }
    }

    return NO;
}

static BOOL LSK7ViewHasPlainGPSBubbleMarker(UIView *view) {
    if (!view) {
        return NO;
    }

    if (LSK7StringIsPlainGPSBubbleTitle(view.accessibilityLabel) ||
        LSK7StringIsPlainGPSBubbleTitle(view.accessibilityIdentifier) ||
        LSK7StringIsPlainGPSBubbleTitle(view.restorationIdentifier)) {
        return YES;
    }

    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        return LSK7StringIsPlainGPSBubbleTitle(label.text) ||
               LSK7StringIsPlainGPSBubbleTitle(label.attributedText.string);
    }

    if ([view isKindOfClass:UIButton.class]) {
        UIButton *button = (UIButton *)view;
        return LSK7StringIsPlainGPSBubbleTitle([button titleForState:UIControlStateNormal]) ||
               LSK7StringIsPlainGPSBubbleTitle([button attributedTitleForState:UIControlStateNormal].string) ||
               LSK7StringIsPlainGPSBubbleTitle([button titleForState:UIControlStateSelected]) ||
               LSK7StringIsPlainGPSBubbleTitle([button titleForState:UIControlStateHighlighted]);
    }

    if ([view respondsToSelector:@selector(text)]) {
        id value = nil;
        @try {
            value = [view valueForKey:@"text"];
        } @catch (__unused NSException *exception) {
            value = nil;
        }
        if (LSK7StringIsPlainGPSBubbleTitle([value isKindOfClass:NSString.class] ? value : nil)) {
            return YES;
        }
    }

    return NO;
}

static BOOL LSK7ViewIsInsideNormalReusableAppChrome(UIView *view) {
    for (UIView *candidate = view; candidate; candidate = candidate.superview) {
        if ([candidate isKindOfClass:UITableViewCell.class] ||
            [candidate isKindOfClass:UICollectionViewCell.class] ||
            [candidate isKindOfClass:UINavigationBar.class] ||
            [candidate isKindOfClass:UITabBar.class] ||
            [candidate isKindOfClass:UIToolbar.class]) {
            return YES;
        }
    }
    return NO;
}

static BOOL LSK7ViewHasCompactFloatingGeometry(UIView *view) {
    if (!view || [view isKindOfClass:UIWindow.class]) {
        return NO;
    }

    CGRect bounds = view.bounds;
    if (CGRectIsEmpty(bounds)) {
        return NO;
    }

    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);
    if (!isfinite(width) || !isfinite(height)) {
        return NO;
    }
    CGFloat minSide = MIN(width, height);
    CGFloat maxSide = MAX(width, height);
    if (minSide < 36.0 || maxSide > 220.0) {
        return NO;
    }

    CGFloat aspect = maxSide / MAX(1.0, minSide);
    if (aspect > 1.55) {
        return NO;
    }

    if (LSK7ViewScreenAreaRatio(view) > 0.12) {
        return NO;
    }

    CGFloat cornerRadius = view.layer.cornerRadius;
    BOOL roundish = cornerRadius >= (minSide * 0.28);
    BOOL compactControl = [view isKindOfClass:UIControl.class] && maxSide <= 180.0;
    BOOL visiblePanel = view.backgroundColor != nil && view.alpha > 0.01;
    return roundish || compactControl || visiblePanel;
}

static BOOL LSK7ViewHasStrongFloatingBubbleShape(UIView *view) {
    if (!view || !LSK7ViewHasCompactFloatingGeometry(view)) {
        return NO;
    }

    CGRect bounds = view.bounds;
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);
    CGFloat minSide = MIN(width, height);
    CGFloat maxSide = MAX(width, height);
    CGFloat aspect = maxSide / MAX(1.0, minSide);
    BOOL roundish = view.layer.cornerRadius >= (minSide * 0.28);
    BOOL compactControl = [view isKindOfClass:UIControl.class] && maxSide <= 180.0 && aspect <= 1.35;
    return roundish || compactControl;
}

static BOOL LSK7ViewWindowContextAllowsPlainGPSHide(UIView *view) {
    UIWindow *window = view.window;
    if (!window || LSK7IsOurToolObject(window) || LSK7IsOurToolObject(window.rootViewController)) {
        return NO;
    }

    if (window.windowLevel > UIWindowLevelNormal + 0.5) {
        return YES;
    }

    // Some floating tweak buttons are hosted inside a normal-level pass-through
    // window.  For the plain "GPS" marker, only allow hiding if the candidate
    // itself looks like a compact floating bubble and is not normal app chrome.
    return !LSK7ViewIsInsideNormalReusableAppChrome(view) && LSK7ViewHasStrongFloatingBubbleShape(view);
}

static UIView *LSK7PlainGPSBubbleHideCandidateForMarkedView(UIView *markedView) {
    if (!markedView || LSK7IsOurToolObject(markedView) || !LSK7ViewHasPlainGPSBubbleMarker(markedView)) {
        return nil;
    }

    if (LSK7ViewIsInsideNormalReusableAppChrome(markedView)) {
        return nil;
    }

    UIView *candidate = nil;
    UIView *view = markedView;
    NSInteger climbs = 7;
    while (view && climbs >= 0) {
        if ([view isKindOfClass:UIWindow.class] || LSK7IsOurToolObject(view)) {
            break;
        }

        if (LSK7ViewHasCompactFloatingGeometry(view)) {
            candidate = view;
        }

        UIView *parent = view.superview;
        if (!parent || [parent isKindOfClass:UIWindow.class]) {
            break;
        }

        // Do not climb into a full-screen app/root container.  The goal is to
        // remove the floating bubble shell, not blank the host application.
        if (LSK7ViewScreenAreaRatio(parent) > 0.18) {
            break;
        }

        view = parent;
        climbs -= 1;
    }

    if (!candidate) {
        candidate = markedView;
    }

    return LSK7ViewWindowContextAllowsPlainGPSHide(candidate) ? candidate : nil;
}

static BOOL LSK7ViewControllerLooksLikeTarget(UIViewController *controller, NSInteger depth) {
    if (!controller || depth < 0) {
        return NO;
    }

    if (LSK7ObjectClassLooksLikeTarget(controller) ||
        LSK7NameLooksLikeTarget(controller.restorationIdentifier, YES) ||
        LSK7StringHasK7GPS(controller.title)) {
        return YES;
    }

    for (UIViewController *child in [controller.childViewControllers copy]) {
        if (LSK7ViewControllerLooksLikeTarget(child, depth - 1)) {
            return YES;
        }
    }

    if (controller.presentedViewController && LSK7ViewControllerLooksLikeTarget(controller.presentedViewController, depth - 1)) {
        return YES;
    }

    return NO;
}

static BOOL LSK7IsOurToolObject(id object) {
    NSString *name = LSK7ClassName(object).lowercaseString;
    if (name.length == 0) {
        return NO;
    }
    return [name containsString:@"xsgps"] ||
           [name containsString:@"lsoverlay"] ||
           [name containsString:@"mappicker"] ||
           [name containsString:@"lssettings"] ||
           [name containsString:@"lswifi"] ||
           [name containsString:@"lsbluetooth"] ||
           [name containsString:@"lsbookmarks"] ||
           [name containsString:@"lsschedule"] ||
           [name containsString:@"lsactivation"];
}

static BOOL LSK7WindowLooksLikeTarget(UIWindow *window) {
    if (!window || LSK7IsOurToolObject(window) || LSK7IsOurToolObject(window.rootViewController)) {
        return NO;
    }

    if (LSK7ObjectClassLooksLikeTarget(window) ||
        LSK7NameLooksLikeTarget(window.accessibilityIdentifier, YES) ||
        LSK7NameLooksLikeTarget(window.restorationIdentifier, YES) ||
        LSK7StringHasK7GPS(window.accessibilityLabel)) {
        return YES;
    }

    return LSK7ViewControllerLooksLikeTarget(window.rootViewController, 6);
}

static void LSK7HideView(UIView *view) {
    if (!view || LSK7IsOurToolObject(view)) {
        return;
    }

    view.hidden = YES;
    view.alpha = 0.0;
    view.userInteractionEnabled = NO;
    view.accessibilityElementsHidden = YES;
}

static void LSK7HideWindow(UIWindow *window) {
    if (!window || LSK7IsOurToolObject(window) || LSK7IsOurToolObject(window.rootViewController)) {
        return;
    }

    window.hidden = YES;
    window.alpha = 0.0;
    window.userInteractionEnabled = NO;
    window.accessibilityElementsHidden = YES;
    window.windowLevel = -100000.0;
}

static CGFloat LSK7ViewScreenAreaRatio(UIView *view) {
    if (!view) {
        return 1.0;
    }
    CGRect bounds = view.bounds;
    if (CGRectIsEmpty(bounds)) {
        return 0.0;
    }
    CGSize screenSize = UIScreen.mainScreen.bounds.size;
    CGFloat viewArea = MAX(1.0, bounds.size.width * bounds.size.height);
    CGFloat screenArea = MAX(1.0, screenSize.width * screenSize.height);
    return viewArea / screenArea;
}

static BOOL LSK7ViewIsSafeContainerToHide(UIView *view, BOOL strongMatch) {
    if (!view || [view isKindOfClass:UIWindow.class] || LSK7IsOurToolObject(view)) {
        return NO;
    }

    CGFloat ratio = LSK7ViewScreenAreaRatio(view);
    if (strongMatch) {
        // If the parent is the direct root of the normal application window,
        // do not blank the host app.  For elevated tweak windows, or compact
        // overlay panels, allow a larger wrapper so no empty k7gps shell remains.
        if ([view.superview isKindOfClass:UIWindow.class]) {
            UIWindow *window = (UIWindow *)view.superview;
            if (window.windowLevel > UIWindowLevelNormal + 0.5) {
                return YES;
            }
            return ratio <= 0.92;
        }
        return YES;
    }

    return ratio <= 0.80;
}

static UIView *LSK7BestHideCandidateForMatchedView(UIView *matchedView, BOOL strongMatch) {
    if (!matchedView || LSK7IsOurToolObject(matchedView)) {
        return nil;
    }

    UIView *candidate = matchedView;
    UIView *parent = matchedView.superview;
    NSInteger climbs = strongMatch ? 8 : 3;
    while (parent && climbs > 0 && LSK7ViewIsSafeContainerToHide(parent, strongMatch)) {
        if (LSK7IsOurToolObject(parent)) {
            break;
        }
        candidate = parent;
        parent = parent.superview;
        climbs -= 1;
    }
    return candidate;
}

static BOOL LSK7HideMatchingViewsInTree(UIView *view, NSInteger depth) {
    if (!view || depth < 0 || LSK7IsOurToolObject(view)) {
        return NO;
    }

    if ([view isKindOfClass:UIWindow.class] && LSK7WindowLooksLikeTarget((UIWindow *)view)) {
        LSK7HideWindow((UIWindow *)view);
        return YES;
    }

    BOOL classMatch = LSK7ObjectClassLooksLikeTarget(view);
    BOOL metadataMatch = classMatch ? NO : LSK7ViewMetadataLooksLikeTarget(view);
    UIView *plainGPSBubbleCandidate = (classMatch || metadataMatch) ? nil : LSK7PlainGPSBubbleHideCandidateForMarkedView(view);
    BOOL hidAny = NO;

    if (classMatch || metadataMatch) {
        UIView *candidate = LSK7BestHideCandidateForMatchedView(view, classMatch || LSK7NameLooksLikeTarget(view.accessibilityIdentifier, YES));
        if (candidate) {
            LSK7HideView(candidate);
            hidAny = YES;
        }
    }

    if (plainGPSBubbleCandidate) {
        LSK7HideView(plainGPSBubbleCandidate);
        hidAny = YES;
    }

    if (depth == 0 || view.hidden) {
        return hidAny;
    }

    NSArray<UIView *> *children = [view.subviews copy];
    for (UIView *child in children) {
        hidAny = LSK7HideMatchingViewsInTree(child, depth - 1) || hidAny;
    }
    return hidAny;
}

static BOOL LSK7WindowHasTargetSubview(UIWindow *window) {
    if (!window || LSK7IsOurToolObject(window) || LSK7IsOurToolObject(window.rootViewController)) {
        return NO;
    }
    return LSK7HideMatchingViewsInTree(window, kLSK7DeepScanDepth);
}

static NSArray<UIWindow *> *LSK7VisibleWindowsSnapshot(void) {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    UIApplication *application = UIApplication.sharedApplication;
    if (!application) {
        return windows;
    }

    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in application.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) {
                continue;
            }
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (window && !window.hidden && window.alpha > 0.01) {
                    [windows addObject:window];
                }
            }
        }
    }

    for (UIWindow *window in application.windows) {
        if (window && !window.hidden && window.alpha > 0.01 && ![windows containsObject:window]) {
            [windows addObject:window];
        }
    }
    return windows;
}

static void LSK7PerformGlobalScan(void) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            LSK7PerformGlobalScan();
        });
        return;
    }

    ls_k7ScanPending = NO;
    for (UIWindow *window in LSK7VisibleWindowsSnapshot()) {
        if (LSK7WindowLooksLikeTarget(window)) {
            LSK7HideWindow(window);
        } else {
            BOOL found = LSK7WindowHasTargetSubview(window);
            if (found && window.windowLevel > UIWindowLevelNormal + 0.5 && !LSK7IsOurToolObject(window.rootViewController)) {
                // Most tweak overlays live in a dedicated elevated window.  If
                // a k7 element is found there, hide the whole overlay window so
                // no empty side panel remains.
                LSK7HideWindow(window);
            }
        }
    }
}

static void LSK7ScheduleScanAfter(NSTimeInterval delay) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        LSK7PerformGlobalScan();
    });
}

static void LSK7ScheduleThrottledScan(void) {
    if (ls_k7ScanPending) {
        return;
    }
    ls_k7ScanPending = YES;
    LSK7ScheduleScanAfter(0.04);
}

static void LSK7ScheduleBurstScans(void) {
    // Short launch/activation burst catches windows that appear after our dylib
    // constructor.  No permanent repeating timer is left running.
    LSK7ScheduleScanAfter(0.00);
    LSK7ScheduleScanAfter(0.02);
    LSK7ScheduleScanAfter(0.05);
    LSK7ScheduleScanAfter(0.10);
    LSK7ScheduleScanAfter(0.20);
    LSK7ScheduleScanAfter(0.35);
    LSK7ScheduleScanAfter(0.60);
    LSK7ScheduleScanAfter(1.00);
    LSK7ScheduleScanAfter(1.80);
    LSK7ScheduleScanAfter(3.00);
}

static void LSK7ProcessAppearingView(UIView *view, NSInteger depth) {
    if (!view || LSK7IsOurToolObject(view)) {
        return;
    }

    BOOL hiddenNow = LSK7HideMatchingViewsInTree(view, depth);
    if (!hiddenNow) {
        LSK7ScheduleThrottledScan();
    }
}

static void LSK7HookedWillMoveToWindow(UIView *self, SEL _cmd, UIWindow *newWindow) {
    if (newWindow) {
        LSK7ProcessAppearingView(self, kLSK7LightScanDepth);
    }

    if (ls_originalWillMoveToWindowIMP) {
        ((void (*)(id, SEL, UIWindow *))ls_originalWillMoveToWindowIMP)(self, _cmd, newWindow);
    }
}

static void LSK7HookedDidMoveToWindow(UIView *self, SEL _cmd) {
    if (ls_originalDidMoveToWindowIMP) {
        ((void (*)(id, SEL))ls_originalDidMoveToWindowIMP)(self, _cmd);
    }

    if (self.window) {
        LSK7ProcessAppearingView(self, kLSK7LightScanDepth);
    }
}

static void LSK7HookedDidAddSubview(UIView *self, SEL _cmd, UIView *subview) {
    if (ls_originalDidAddSubviewIMP) {
        ((void (*)(id, SEL, UIView *))ls_originalDidAddSubviewIMP)(self, _cmd, subview);
    }

    if (subview) {
        LSK7ProcessAppearingView(subview, kLSK7LightScanDepth);
    }
}

static void LSK7HookedWindowMakeKeyAndVisible(UIWindow *self, SEL _cmd) {
    if (ls_originalWindowMakeKeyAndVisibleIMP) {
        ((void (*)(id, SEL))ls_originalWindowMakeKeyAndVisibleIMP)(self, _cmd);
    }

    if (LSK7WindowLooksLikeTarget(self)) {
        LSK7HideWindow(self);
    } else {
        LSK7HideMatchingViewsInTree(self, kLSK7DeepScanDepth);
        LSK7ScheduleThrottledScan();
    }
}

static void LSK7ReSuppressViewIfNeeded(UIView *view) {
    if (!view || LSK7IsOurToolObject(view)) {
        return;
    }

    NSInteger depth = [view isKindOfClass:UIWindow.class] ? kLSK7DeepScanDepth : kLSK7LightScanDepth;
    LSK7ProcessAppearingView(view, depth);
}

static void LSK7HookedViewSetHidden(UIView *self, SEL _cmd, BOOL hidden) {
    if (ls_originalViewSetHiddenIMP) {
        ((void (*)(id, SEL, BOOL))ls_originalViewSetHiddenIMP)(self, _cmd, hidden);
    }

    if (!hidden && self.window) {
        LSK7ReSuppressViewIfNeeded(self);
    }
}

static void LSK7HookedViewSetAlpha(UIView *self, SEL _cmd, CGFloat alpha) {
    if (ls_originalViewSetAlphaIMP) {
        ((void (*)(id, SEL, CGFloat))ls_originalViewSetAlphaIMP)(self, _cmd, alpha);
    }

    if (alpha > 0.01 && self.window && !self.hidden) {
        LSK7ReSuppressViewIfNeeded(self);
    }
}

static void LSK7InstallHiderHooks(void) {
    dispatch_once(&ls_k7HiderInstallOnceToken, ^{
        ls_k7PositiveClassCache = [NSMutableSet set];
        ls_k7NegativeClassCache = [NSMutableSet set];

        Class uiViewClass = objc_getClass("UIView");
        if (uiViewClass) {
            Method willMove = class_getInstanceMethod(uiViewClass, @selector(willMoveToWindow:));
            if (willMove) {
                ls_originalWillMoveToWindowIMP = method_getImplementation(willMove);
                LSInstallInstanceHookWithIMP(uiViewClass,
                                             @selector(willMoveToWindow:),
                                             @selector(ls_k7gps_v54WillMoveToWindow:),
                                             (IMP)LSK7HookedWillMoveToWindow);
            }

            Method didMove = class_getInstanceMethod(uiViewClass, @selector(didMoveToWindow));
            if (didMove) {
                ls_originalDidMoveToWindowIMP = method_getImplementation(didMove);
                LSInstallInstanceHookWithIMP(uiViewClass,
                                             @selector(didMoveToWindow),
                                             @selector(ls_k7gps_v54DidMoveToWindow),
                                             (IMP)LSK7HookedDidMoveToWindow);
            }

            Method didAddSubview = class_getInstanceMethod(uiViewClass, @selector(didAddSubview:));
            if (didAddSubview) {
                ls_originalDidAddSubviewIMP = method_getImplementation(didAddSubview);
                LSInstallInstanceHookWithIMP(uiViewClass,
                                             @selector(didAddSubview:),
                                             @selector(ls_k7gps_v54DidAddSubview:),
                                             (IMP)LSK7HookedDidAddSubview);
            }

            Method setHidden = class_getInstanceMethod(uiViewClass, @selector(setHidden:));
            if (setHidden) {
                ls_originalViewSetHiddenIMP = method_getImplementation(setHidden);
                LSInstallInstanceHookWithIMP(uiViewClass,
                                             @selector(setHidden:),
                                             @selector(ls_k7gps_v55SetHidden:),
                                             (IMP)LSK7HookedViewSetHidden);
            }

            Method setAlpha = class_getInstanceMethod(uiViewClass, @selector(setAlpha:));
            if (setAlpha) {
                ls_originalViewSetAlphaIMP = method_getImplementation(setAlpha);
                LSInstallInstanceHookWithIMP(uiViewClass,
                                             @selector(setAlpha:),
                                             @selector(ls_k7gps_v55SetAlpha:),
                                             (IMP)LSK7HookedViewSetAlpha);
            }
        }

        Class uiWindowClass = objc_getClass("UIWindow");
        if (uiWindowClass) {
            Method makeKey = class_getInstanceMethod(uiWindowClass, @selector(makeKeyAndVisible));
            if (makeKey) {
                ls_originalWindowMakeKeyAndVisibleIMP = method_getImplementation(makeKey);
                LSInstallInstanceHookWithIMP(uiWindowClass,
                                             @selector(makeKeyAndVisible),
                                             @selector(ls_k7gps_v54MakeKeyAndVisible),
                                             (IMP)LSK7HookedWindowMakeKeyAndVisible);
            }
        }

        NSArray<NSString *> *windowNotifications = @[
            UIWindowDidBecomeVisibleNotification,
            UIWindowDidBecomeKeyNotification,
            UIApplicationDidFinishLaunchingNotification,
            UIApplicationDidBecomeActiveNotification
        ];
        for (NSString *name in windowNotifications) {
            [[NSNotificationCenter defaultCenter] addObserverForName:name
                                                              object:nil
                                                               queue:[NSOperationQueue mainQueue]
                                                          usingBlock:^(__unused NSNotification *note) {
                LSK7ScheduleBurstScans();
            }];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            LSK7ScheduleBurstScans();
        });
    });
}

__attribute__((constructor(102)))
static void LSK7GPSHiderConstructor(void) {
    LSK7InstallHiderHooks();
}


static NSMutableSet<NSString *> *LSInstalledHookKeys(void) {
    static NSMutableSet<NSString *> *keys = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = [NSMutableSet set];
    });
    return keys;
}

static NSString *LSHookRegistryKey(Class cls, SEL originalSelector, SEL hookSelector) {
    return [NSString stringWithFormat:@"%p|%@|%@", cls, NSStringFromSelector(originalSelector), NSStringFromSelector(hookSelector)];
}

Class LSClassDefiningInstanceMethod(Class cls, SEL selector) {
    if (!cls || !selector) {
        return Nil;
    }

    for (Class candidate = cls; candidate && candidate != [NSObject class]; candidate = class_getSuperclass(candidate)) {
        if (LSClassDefinesInstanceMethodLocally(candidate, selector)) {
            return candidate;
        }
    }
    return Nil;
}

BOOL LSClassDefinesInstanceMethodLocally(Class cls, SEL selector) {
    if (!cls || !selector) {
        return NO;
    }

    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(cls, &methodCount);
    if (!methods) {
        return NO;
    }

    BOOL found = NO;
    for (unsigned int index = 0; index < methodCount; index++) {
        if (method_getName(methods[index]) == selector) {
            found = YES;
            break;
        }
    }
    free(methods);
    return found;
}

static Method LSGetInstanceMethodDefinedOnClass(Class cls, SEL selector) {
    if (!cls || !selector) {
        return NULL;
    }

    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(cls, &methodCount);
    if (!methods) {
        return NULL;
    }

    Method found = NULL;
    for (unsigned int index = 0; index < methodCount; index++) {
        if (method_getName(methods[index]) == selector) {
            found = methods[index];
            break;
        }
    }
    free(methods);
    return found;
}

BOOL LSInstallInstanceHookWithIMP(Class cls, SEL originalSelector, SEL hookSelector, IMP hookIMP) {
    if (!cls || !originalSelector || !hookSelector || !hookIMP) {
        return NO;
    }

    @synchronized(LSInstalledHookKeys()) {
        NSString *registryKey = LSHookRegistryKey(cls, originalSelector, hookSelector);
        if ([LSInstalledHookKeys() containsObject:registryKey]) {
            return YES;
        }

        Method originalMethod = LSGetInstanceMethodDefinedOnClass(cls, originalSelector);
        if (!originalMethod) {
            return NO;
        }

        if (!LSClassDefinesInstanceMethodLocally(cls, hookSelector)) {
            if (!class_addMethod(cls,
                                 hookSelector,
                                 hookIMP,
                                 method_getTypeEncoding(originalMethod))) {
                return NO;
            }
        }

        Method hookMethod = LSGetInstanceMethodDefinedOnClass(cls, hookSelector);
        if (!hookMethod) {
            return NO;
        }

        method_exchangeImplementations(originalMethod, hookMethod);
        [LSInstalledHookKeys() addObject:registryKey];
        return YES;
    }
}

BOOL LSInstallInstanceHook(Class cls, SEL originalSelector, SEL hookSelector, Class templateClass) {
    if (!templateClass) {
        return NO;
    }

    Method templateMethod = class_getInstanceMethod(templateClass, hookSelector);
    if (!templateMethod) {
        return NO;
    }

    return LSInstallInstanceHookWithIMP(cls,
                                      originalSelector,
                                      hookSelector,
                                      method_getImplementation(templateMethod));
}
