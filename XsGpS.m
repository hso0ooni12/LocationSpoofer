#import "XsGpS.h"
#import "PersistenceManager.h"
#import "LSActivationManager.h"
#import "LSHooking.h"
#import "LSScheduleManager.h"
#import "RouteSimulator.h"

#import <objc/runtime.h>
#import <objc/message.h>
#import <os/log.h>
#import <math.h>

static _Thread_local BOOL ls_internalCreate = NO;
static BOOL ls_hooksBypassed = NO;
static NSHashTable *ls_swizzledDelegateClasses = nil;
static NSMutableSet *ls_swizzledDelegateMethodKeys = nil;
static NSMutableSet *ls_observedDelegateClasses = nil;
static dispatch_once_t ls_delegateTablesOnceToken;
static dispatch_once_t ls_hookSelectorsOnceToken;
static os_log_t ls_log = NULL;



static SEL ls_hookDidUpdateLocationsSEL = NULL;
static SEL ls_hookDidUpdateToLocationSEL = NULL;

static void LSHookDidUpdateLocations(id self, SEL _cmd, CLLocationManager *manager, NSArray<CLLocation *> *locations);
static void LSHookDidUpdateToLocation(id self, SEL _cmd, CLLocationManager *manager, CLLocation *newLocation, CLLocation *oldLocation);

BOOL LSIsInternalLocationCreate(void) {
    return ls_internalCreate;
}

void LSSetHooksBypassed(BOOL bypassed) {
    @synchronized([XsGpS class]) {
        ls_hooksBypassed = bypassed;
    }
}

static BOOL LSHooksBypassed(void) {
    @synchronized([XsGpS class]) {
        return ls_hooksBypassed;
    }
}

static BOOL LSScheduleAllowsSpoofing(void) {
    if (![LSScheduleManager isEnabled]) {
        return YES;
    }
    if (![LSScheduleManager isCurrentTimeWithinSchedule]) {
        return NO;
    }

    PersistenceManager *store = [PersistenceManager shared];
    if ([store hasStoredCoordinate] && ![store isSpoofingEnabled]) {
        [store setSpoofCoordinate:[store spoofCoordinate] enabled:YES];
    }
    return YES;
}

static BOOL LSShouldSpoof(void) {
    if (ls_internalCreate || LSHooksBypassed() || ![[LSActivationManager shared] isActivated]) {
        return NO;
    }
    if (!LSScheduleAllowsSpoofing()) {
        return NO;
    }
    return [[PersistenceManager shared] isSpoofingEnabled];
}

static double LSSafeFiniteDouble(double value, double fallback) {
    return isfinite(value) ? value : fallback;
}

static CLLocationDirection LSSanitizedCourse(CLLocationDirection course) {
    course = LSSafeFiniteDouble(course, 0.0);
    course = fmod(course, 360.0);
    if (course < 0.0) {
        course += 360.0;
    }
    return course;
}

static CLLocationSpeed LSSanitizedSpeed(CLLocationSpeed speed) {
    speed = LSSafeFiniteDouble(speed, 0.0);
    return MAX(0.0, speed);
}

static CLLocationAccuracy LSSanitizedHorizontalAccuracy(CLLocationAccuracy accuracy) {
    accuracy = LSSafeFiniteDouble(accuracy, 6.0);
    return MAX(3.0, accuracy);
}

static CLLocation *LSBuildSpoofedLocation(CLLocationCoordinate2D coordinate,
                                          CLLocationDirection course,
                                          double altitude,
                                          double horizontalAccuracy,
                                          double speed) {
    if (!CLLocationCoordinate2DIsValid(coordinate)) {
        coordinate = CLLocationCoordinate2DMake(37.7749, -122.4194);
    }

    CLLocationDirection safeCourse = LSSanitizedCourse(course);
    CLLocationSpeed safeSpeed = LSSanitizedSpeed(speed);
    CLLocationAccuracy safeHorizontalAccuracy = LSSanitizedHorizontalAccuracy(horizontalAccuracy);
    CLLocationDistance safeAltitude = LSSafeFiniteDouble(altitude, 0.0);

    ls_internalCreate = YES;
    CLLocation *location = [[CLLocation alloc] initWithCoordinate:coordinate
                                                         altitude:safeAltitude
                                               horizontalAccuracy:safeHorizontalAccuracy
                                                 verticalAccuracy:6.0
                                                            course:safeCourse
                                                             speed:safeSpeed
                                                         timestamp:[NSDate date]];
    ls_internalCreate = NO;
    return location;
}

static CLLocationCoordinate2D LSCoordinateByApplyingRandomMovement(CLLocationCoordinate2D baseCoordinate, double radiusMeters) {
    if (!CLLocationCoordinate2DIsValid(baseCoordinate) || radiusMeters <= 0.0) {
        return baseCoordinate;
    }

    double unitA = ((double)arc4random_uniform(UINT32_MAX) / (double)UINT32_MAX);
    double unitB = ((double)arc4random_uniform(UINT32_MAX) / (double)UINT32_MAX);
    double distance = sqrt(unitA) * radiusMeters;
    double bearing = unitB * 2.0 * M_PI;
    double latitudeRadians = baseCoordinate.latitude * M_PI / 180.0;
    double metersPerDegreeLatitude = 111111.0;
    double metersPerDegreeLongitude = MAX(1.0, metersPerDegreeLatitude * cos(latitudeRadians));

    double latitudeOffset = (distance * cos(bearing)) / metersPerDegreeLatitude;
    double longitudeOffset = (distance * sin(bearing)) / metersPerDegreeLongitude;

    CLLocationDegrees lat = MIN(90.0, MAX(-90.0, baseCoordinate.latitude + latitudeOffset));
    CLLocationDegrees lon = baseCoordinate.longitude + longitudeOffset;
    if (lon > 180.0) lon -= 360.0;
    if (lon < -180.0) lon += 360.0;
    return CLLocationCoordinate2DMake(lat, lon);
}

CLLocation *LSCreateSpoofedLocation(void) {
    PersistenceManager *store = [PersistenceManager shared];
    CLLocationCoordinate2D coordinate = [store spoofCoordinate];
    CLLocationDirection heading = store.heading;
    double altitude = store.altitude;
    double horizontalAccuracy = 6.0;
    double speed = 0.0;

    LSRouteSimulator *routeSimulator = [LSRouteSimulator shared];
    if (routeSimulator.isSimulating || routeSimulator.isPaused) {
        CLLocationCoordinate2D routeCoordinate = routeSimulator.currentCoordinate;
        if (CLLocationCoordinate2DIsValid(routeCoordinate)) {
            coordinate = routeCoordinate;
            heading = routeSimulator.currentHeading;
            horizontalAccuracy = [LSRouteSimulator horizontalAccuracyForMode:routeSimulator.transportMode];
            speed = routeSimulator.isPaused ? 0.0 : [LSRouteSimulator speedMetersPerSecondForMode:routeSimulator.transportMode
                                                                                   customSpeedKmh:routeSimulator.customSpeedKmh];
        }
    }

    if (!CLLocationCoordinate2DIsValid(coordinate)) {
        coordinate = CLLocationCoordinate2DMake(37.7749, -122.4194);
    }

    if (store.fluctuationEnabled && !routeSimulator.isSimulating) {
        double radius = store.fluctuationRadius > 0.0 ? store.fluctuationRadius : 10.0;
        coordinate = LSCoordinateByApplyingRandomMovement(coordinate, radius);
        horizontalAccuracy = MAX(6.0, radius / 2.0);
        speed = MAX(speed, 0.6);
    }

    return LSBuildSpoofedLocation(coordinate,
                                  heading,
                                  altitude,
                                  horizontalAccuracy,
                                  speed);
}

static BOOL LSIsSystemFrameworkBundle(NSBundle *bundle) {
    NSString *path = bundle.bundlePath;
    if (path.length == 0) {
        return YES;
    }
    if ([path hasPrefix:@"/System/"]) {
        return YES;
    }
    if ([path hasPrefix:@"/private/preboot/Cryptexes/"]) {
        return YES;
    }
    if ([path hasPrefix:@"/usr/"]) {
        return YES;
    }
    return NO;
}

static void LSInitializeDelegateTables(void) {
    dispatch_once(&ls_delegateTablesOnceToken, ^{
        ls_swizzledDelegateClasses = [NSHashTable weakObjectsHashTable];
        ls_swizzledDelegateMethodKeys = [NSMutableSet set];
        ls_observedDelegateClasses = [NSMutableSet set];
    });
}

static void LSInitializeDelegateHookSelectors(void) {
    dispatch_once(&ls_hookSelectorsOnceToken, ^{
        NSString *suffix = NSUUID.UUID.UUIDString;
        NSString *locationsName = [NSString stringWithFormat:@"lsp_locationManager_%@:didUpdateLocations:", suffix];
        NSString *legacyName = [NSString stringWithFormat:@"lsp_locationManager_%@:didUpdateToLocation:fromLocation:", suffix];
        ls_hookDidUpdateLocationsSEL = sel_registerName(locationsName.UTF8String);
        ls_hookDidUpdateToLocationSEL = sel_registerName(legacyName.UTF8String);
    });
}

static NSString *LSSwizzledDelegateMethodKey(Class cls, SEL selector) {
    return [NSString stringWithFormat:@"%@|%@", NSStringFromClass(cls), NSStringFromSelector(selector)];
}

static BOOL LSShouldSwizzleDelegateClass(Class delegateClass) {
    if (!delegateClass || delegateClass == [NSObject class]) {
        return NO;
    }

    NSString *className = NSStringFromClass(delegateClass);
    if (className.length == 0 || [className hasPrefix:@"_"]) {
        return NO;
    }

    if (LSIsSystemFrameworkBundle([NSBundle bundleForClass:delegateClass])) {
        return NO;
    }

    LSInitializeDelegateTables();
    @synchronized(ls_swizzledDelegateClasses) {
        return [ls_observedDelegateClasses containsObject:delegateClass];
    }
}

static void LSObserveDelegateClass(Class delegateClass) {
    if (!delegateClass || delegateClass == [NSObject class]) {
        return;
    }

    if (LSIsSystemFrameworkBundle([NSBundle bundleForClass:delegateClass])) {
        return;
    }

    LSInitializeDelegateTables();
    @synchronized(ls_swizzledDelegateClasses) {
        [ls_observedDelegateClasses addObject:delegateClass];
    }
}

static void LSSwizzleDelegateForClass(Class delegateClass) {
    if (!delegateClass || !LSShouldSwizzleDelegateClass(delegateClass)) {
        return;
    }

    LSInitializeDelegateHookSelectors();

    LSInitializeDelegateTables();
    @synchronized(ls_swizzledDelegateClasses) {
        SEL locationsSelector = @selector(locationManager:didUpdateLocations:);
        Class locationsClass = LSClassDefiningInstanceMethod(delegateClass, locationsSelector);
        if (locationsClass) {
            NSString *locationsKey = LSSwizzledDelegateMethodKey(locationsClass, locationsSelector);
            if (![ls_swizzledDelegateMethodKeys containsObject:locationsKey] &&
                LSInstallInstanceHookWithIMP(locationsClass,
                                             locationsSelector,
                                             ls_hookDidUpdateLocationsSEL,
                                             (IMP)LSHookDidUpdateLocations)) {
                [ls_swizzledDelegateClasses addObject:locationsClass];
                [ls_swizzledDelegateMethodKeys addObject:locationsKey];
            }
        }

        SEL legacySelector = @selector(locationManager:didUpdateToLocation:fromLocation:);
        Class legacyClass = LSClassDefiningInstanceMethod(delegateClass, legacySelector);
        if (legacyClass) {
            NSString *legacyKey = LSSwizzledDelegateMethodKey(legacyClass, legacySelector);
            if (![ls_swizzledDelegateMethodKeys containsObject:legacyKey] &&
                LSInstallInstanceHookWithIMP(legacyClass,
                                             legacySelector,
                                             ls_hookDidUpdateToLocationSEL,
                                             (IMP)LSHookDidUpdateToLocation)) {
                [ls_swizzledDelegateClasses addObject:legacyClass];
                [ls_swizzledDelegateMethodKeys addObject:legacyKey];
            }
        }
    }
}

static void LSSwizzleDelegateIfNeeded(id delegate) {
    if (!delegate) {
        return;
    }

    Class delegateClass = [delegate class];
    LSObserveDelegateClass(delegateClass);
    LSSwizzleDelegateForClass(delegateClass);
}

static void LSHookDidUpdateLocations(id self, SEL _cmd, CLLocationManager *manager, NSArray<CLLocation *> *locations) {
    (void)_cmd;
    NSArray<CLLocation *> *deliveredLocations = locations;
    if (LSShouldSpoof()) {
        deliveredLocations = @[LSCreateSpoofedLocation()];
    }

    void (*originalIMP)(id, SEL, CLLocationManager *, NSArray<CLLocation *> *) =
        (void (*)(id, SEL, CLLocationManager *, NSArray<CLLocation *> *))objc_msgSend;
    originalIMP(self, ls_hookDidUpdateLocationsSEL, manager, deliveredLocations);
}

static void LSHookDidUpdateToLocation(id self, SEL _cmd, CLLocationManager *manager, CLLocation *newLocation, CLLocation *oldLocation) {
    (void)_cmd;
    CLLocation *deliveredLocation = newLocation;
    if (LSShouldSpoof()) {
        deliveredLocation = LSCreateSpoofedLocation();
    }

    void (*originalIMP)(id, SEL, CLLocationManager *, CLLocation *, CLLocation *) =
        (void (*)(id, SEL, CLLocationManager *, CLLocation *, CLLocation *))objc_msgSend;
    originalIMP(self, ls_hookDidUpdateToLocationSEL, manager, deliveredLocation, oldLocation);
}

static const void *kLSSyntheticUpdateTimerKey = &kLSSyntheticUpdateTimerKey;

static void LSStopSyntheticUpdates(CLLocationManager *manager) {
    NSTimer *timer = objc_getAssociatedObject(manager, kLSSyntheticUpdateTimerKey);
    if (timer) {
        [timer invalidate];
        objc_setAssociatedObject(manager, kLSSyntheticUpdateTimerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void LSDeliverSyntheticUpdate(CLLocationManager *manager) {
    if (!manager || !LSShouldSpoof()) {
        return;
    }
    id<CLLocationManagerDelegate> delegate = manager.delegate;
    if (!delegate) {
        return;
    }
    CLLocation *location = LSCreateSpoofedLocation();
    if ([delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
        void (*sendLocations)(id, SEL, CLLocationManager *, NSArray<CLLocation *> *) =
            (void (*)(id, SEL, CLLocationManager *, NSArray<CLLocation *> *))objc_msgSend;
        sendLocations(delegate, @selector(locationManager:didUpdateLocations:), manager, @[location]);
    }
    if ([delegate respondsToSelector:@selector(locationManager:didUpdateToLocation:fromLocation:)]) {
        void (*sendLegacy)(id, SEL, CLLocationManager *, CLLocation *, CLLocation *) =
            (void (*)(id, SEL, CLLocationManager *, CLLocation *, CLLocation *))objc_msgSend;
        sendLegacy(delegate, @selector(locationManager:didUpdateToLocation:fromLocation:), manager, location, nil);
    }
}

static void LSStartSyntheticUpdates(CLLocationManager *manager) {
    if (!manager || objc_getAssociatedObject(manager, kLSSyntheticUpdateTimerKey)) {
        return;
    }
    __weak CLLocationManager *weakManager = manager;
    NSTimer *timer = [NSTimer timerWithTimeInterval:1.2 repeats:YES block:^(__unused NSTimer *timer) {
        CLLocationManager *strongManager = weakManager;
        if (!strongManager) {
            [timer invalidate];
            return;
        }
        LSDeliverSyntheticUpdate(strongManager);
    }];
    objc_setAssociatedObject(manager, kLSSyntheticUpdateTimerKey, timer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
}

@interface CLLocationManager (LSHooks)
- (void)lsp_setDelegate:(id<CLLocationManagerDelegate>)delegate;
- (CLLocation *)lsp_location;
- (void)lsp_startUpdatingLocation;
- (void)lsp_stopUpdatingLocation;
@end

@implementation CLLocationManager (LSHooks)

- (void)lsp_setDelegate:(id<CLLocationManagerDelegate>)delegate {
    [self lsp_setDelegate:delegate];
    if (delegate) {
        LSSwizzleDelegateIfNeeded(delegate);
    }
}

- (CLLocation *)lsp_location {
    if (LSShouldSpoof()) {
        return LSCreateSpoofedLocation();
    }
    return [self lsp_location];
}

- (void)lsp_startUpdatingLocation {
    [self lsp_startUpdatingLocation];
    LSStartSyntheticUpdates(self);
}

- (void)lsp_stopUpdatingLocation {
    LSStopSyntheticUpdates(self);
    [self lsp_stopUpdatingLocation];
}

@end

static void LSExchangeInstanceMethods(Class cls, SEL originalSelector, SEL swizzledSelector) {
    Method originalMethod = class_getInstanceMethod(cls, originalSelector);
    Method swizzledMethod = class_getInstanceMethod(cls, swizzledSelector);
    if (!originalMethod || !swizzledMethod) {
        return;
    }

    static NSMutableSet<NSString *> *exchangedKeys = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        exchangedKeys = [NSMutableSet set];
    });

    NSString *key = [NSString stringWithFormat:@"%p|%@|%@", cls, NSStringFromSelector(originalSelector), NSStringFromSelector(swizzledSelector)];
    @synchronized(exchangedKeys) {
        if ([exchangedKeys containsObject:key]) {
            return;
        }
        method_exchangeImplementations(originalMethod, swizzledMethod);
        [exchangedKeys addObject:key];
    }
}

static void LSInstallCLLocationManagerHooks(void) {
    Class managerClass = NSClassFromString(@"CLLocationManager");
    if (!managerClass) {
        if (ls_log) {
            os_log_error(ls_log, "CLLocationManager class missing at hook install");
        }
        return;
    }

    if (!class_getInstanceMethod(managerClass, @selector(setDelegate:))) {
        if (ls_log) {
            os_log_error(ls_log, "CLLocationManager setDelegate: missing at hook install");
        }
        return;
    }

    LSExchangeInstanceMethods(managerClass, @selector(setDelegate:), @selector(lsp_setDelegate:));

    if (class_getInstanceMethod(managerClass, @selector(location))) {
        LSExchangeInstanceMethods(managerClass, @selector(location), @selector(lsp_location));
    }
    if (class_getInstanceMethod(managerClass, @selector(startUpdatingLocation))) {
        LSExchangeInstanceMethods(managerClass, @selector(startUpdatingLocation), @selector(lsp_startUpdatingLocation));
    }
    if (class_getInstanceMethod(managerClass, @selector(stopUpdatingLocation))) {
        LSExchangeInstanceMethods(managerClass, @selector(stopUpdatingLocation), @selector(lsp_stopUpdatingLocation));
    }
}

@implementation XsGpS

+ (void)installHooks {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ls_log = os_log_create("com.xsgps.dylib", "hooks");
        LSInitializeDelegateHookSelectors();
        LSInstallCLLocationManagerHooks();
    });
}

@end
