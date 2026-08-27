#import <Foundation/Foundation.h>
#import <SystemConfiguration/CaptiveNetwork.h>
#import <dlfcn.h>
#import <objc/runtime.h>

static NSString * const kLSWiFiActiveNetworkKey = @"LSWiFiActiveNetworkV1";
static NSString * const kLSWiFiDefaultsSuiteName = @"com.xsgps.dylib";

static NSString *LSWiFiNormalizedBSSIDString(NSString *value) {
    if (![value isKindOfClass:NSString.class]) {
        return @"";
    }

    NSString *clean = [[value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    clean = [[clean stringByReplacingOccurrencesOfString:@"-" withString:@":"] stringByReplacingOccurrencesOfString:@" " withString:@""];
    if (clean.length == 12 && ![clean containsString:@":"]) {
        NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:6];
        for (NSUInteger index = 0; index < 12; index += 2) {
            [parts addObject:[clean substringWithRange:NSMakeRange(index, 2)]];
        }
        clean = [parts componentsJoinedByString:@":"];
    }

    NSArray<NSString *> *parts = [clean componentsSeparatedByString:@":"];
    if (parts.count != 6) {
        return @"";
    }

    NSCharacterSet *hexSet = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"];
    for (NSString *part in parts) {
        if (part.length != 2) {
            return @"";
        }
        for (NSUInteger index = 0; index < part.length; index++) {
            if (![hexSet characterIsMember:[part characterAtIndex:index]]) {
                return @"";
            }
        }
    }
    return clean;
}

typedef CFArrayRef (*LSCNCopySupportedInterfacesFunc)(void);
typedef CFDictionaryRef (*LSCNCopyCurrentNetworkInfoFunc)(CFStringRef interfaceName);

typedef void (^LSNEHotspotCompletion)(id network);
typedef void (*LSNEHotspotFetchIMP)(id self, SEL _cmd, LSNEHotspotCompletion completionHandler);

@interface LSWiFiFakeHotspotNetwork : NSObject
@property (nonatomic, copy) NSString *SSID;
@property (nonatomic, copy) NSString *BSSID;
@property (nonatomic, assign, getter=isSecure) BOOL secure;
@property (nonatomic, assign) double signalStrength;
@end

@implementation LSWiFiFakeHotspotNetwork
- (NSString *)description {
    return [NSString stringWithFormat:@"<NEHotspotNetwork SSID=%@ BSSID=%@ secure=%@>", self.SSID ?: @"", self.BSSID ?: @"", self.secure ? @"YES" : @"NO"];
}
@end

static NSUserDefaults *LSWiFiToolDefaults(void) {
    return [[NSUserDefaults alloc] initWithSuiteName:kLSWiFiDefaultsSuiteName] ?: NSUserDefaults.standardUserDefaults;
}

static NSString *LSWiFiStringValue(NSDictionary<NSString *, id> *network, NSString *key) {
    id value = network[key];
    if (![value isKindOfClass:NSString.class]) { return @""; }
    return [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
}

static NSDictionary<NSString *, id> *LSWiFiActiveNetwork(void) {
    NSDictionary *network = [LSWiFiToolDefaults() dictionaryForKey:kLSWiFiActiveNetworkKey];
    if (![network isKindOfClass:NSDictionary.class]) {
        network = [NSUserDefaults.standardUserDefaults dictionaryForKey:kLSWiFiActiveNetworkKey];
    }
    if (![network isKindOfClass:NSDictionary.class]) { return nil; }

    NSString *ssid = LSWiFiStringValue(network, @"ssid");
    NSString *bssid = LSWiFiNormalizedBSSIDString(LSWiFiStringValue(network, @"bssid"));
    if (ssid.length == 0 && bssid.length == 0) { return nil; }

    NSNumber *rssi = [network[@"rssi"] isKindOfClass:NSNumber.class] ? network[@"rssi"] : @0;
    NSNumber *secure = [network[@"secure"] isKindOfClass:NSNumber.class] ? network[@"secure"] : @YES;
    return @{
        @"ssid": ssid.length ? ssid : @"Hidden Wi-Fi",
        @"bssid": bssid.length ? bssid : @"00:00:00:00:00:00",
        @"rssi": rssi ?: @0,
        @"secure": secure ?: @YES
    };
}

static NSDictionary *LSWiFiCaptiveDictionaryFromNetwork(NSDictionary<NSString *, id> *network) {
    NSString *ssid = LSWiFiStringValue(network, @"ssid");
    NSString *bssid = LSWiFiNormalizedBSSIDString(LSWiFiStringValue(network, @"bssid"));
    NSNumber *rssi = [network[@"rssi"] isKindOfClass:NSNumber.class] ? network[@"rssi"] : @0;
    NSString *safeSSID = ssid.length ? ssid : @"Hidden Wi-Fi";
    NSString *safeBSSID = bssid.length ? bssid : @"00:00:00:00:00:00";
    NSData *ssidData = [safeSSID dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];

    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[(__bridge NSString *)kCNNetworkInfoKeySSID] = safeSSID;
    info[(__bridge NSString *)kCNNetworkInfoKeyBSSID] = safeBSSID;
    info[@"SSIDDATA"] = ssidData;
    info[@"RSSI"] = rssi ?: @0;
    return info;
}

static LSWiFiFakeHotspotNetwork *LSWiFiFakeHotspotFromNetwork(NSDictionary<NSString *, id> *network) {
    NSDictionary *captive = LSWiFiCaptiveDictionaryFromNetwork(network);
    LSWiFiFakeHotspotNetwork *fake = [[LSWiFiFakeHotspotNetwork alloc] init];
    fake.SSID = captive[(__bridge NSString *)kCNNetworkInfoKeySSID] ?: @"Hidden Wi-Fi";
    fake.BSSID = captive[(__bridge NSString *)kCNNetworkInfoKeyBSSID] ?: @"00:00:00:00:00:00";
    NSNumber *secure = [network[@"secure"] isKindOfClass:NSNumber.class] ? network[@"secure"] : @YES;
    NSNumber *rssi = [network[@"rssi"] isKindOfClass:NSNumber.class] ? network[@"rssi"] : @0;
    fake.secure = secure.boolValue;
    double value = rssi.doubleValue;
    fake.signalStrength = value == 0.0 ? 0.70 : MAX(0.05, MIN(1.0, (100.0 + value) / 65.0));
    return fake;
}

static LSCNCopySupportedInterfacesFunc LSOriginalCNCopySupportedInterfaces(void) {
    static LSCNCopySupportedInterfacesFunc original = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        original = (LSCNCopySupportedInterfacesFunc)dlsym(RTLD_NEXT, "CNCopySupportedInterfaces");
    });
    return original;
}

static LSCNCopyCurrentNetworkInfoFunc LSOriginalCNCopyCurrentNetworkInfo(void) {
    static LSCNCopyCurrentNetworkInfoFunc original = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        original = (LSCNCopyCurrentNetworkInfoFunc)dlsym(RTLD_NEXT, "CNCopyCurrentNetworkInfo");
    });
    return original;
}

static CFArrayRef LSHookedCNCopySupportedInterfaces(void) {
    if (LSWiFiActiveNetwork()) {
        return CFBridgingRetain(@[@"en0"]);
    }

    LSCNCopySupportedInterfacesFunc original = LSOriginalCNCopySupportedInterfaces();
    return original ? original() : NULL;
}

static CFDictionaryRef LSHookedCNCopyCurrentNetworkInfo(CFStringRef interfaceName) {
    (void)interfaceName;
    NSDictionary<NSString *, id> *network = LSWiFiActiveNetwork();
    if (network) {
        return CFBridgingRetain(LSWiFiCaptiveDictionaryFromNetwork(network));
    }

    LSCNCopyCurrentNetworkInfoFunc original = LSOriginalCNCopyCurrentNetworkInfo();
    return original ? original(interfaceName) : NULL;
}

static LSNEHotspotFetchIMP LSOriginalNEHotspotFetchCurrent = NULL;

static void LSHookedNEHotspotFetchCurrent(id self, SEL _cmd, LSNEHotspotCompletion completionHandler) {
    NSDictionary<NSString *, id> *network = LSWiFiActiveNetwork();
    if (network) {
        if (completionHandler) {
            completionHandler(LSWiFiFakeHotspotFromNetwork(network));
        }
        return;
    }

    if (LSOriginalNEHotspotFetchCurrent) {
        LSOriginalNEHotspotFetchCurrent(self, _cmd, completionHandler);
    } else if (completionHandler) {
        completionHandler(nil);
    }
}

static void LSInstallNEHotspotNetworkHook(void) {
    dlopen("/System/Library/Frameworks/NetworkExtension.framework/NetworkExtension", RTLD_LAZY);
    Class hotspotClass = NSClassFromString(@"NEHotspotNetwork");
    if (!hotspotClass) { return; }
    SEL selector = NSSelectorFromString(@"fetchCurrentWithCompletionHandler:");
    Method method = class_getClassMethod(hotspotClass, selector);
    if (!method) { return; }
    IMP originalIMP = method_getImplementation(method);
    if (originalIMP == (IMP)LSHookedNEHotspotFetchCurrent) { return; }
    LSOriginalNEHotspotFetchCurrent = (LSNEHotspotFetchIMP)originalIMP;
    method_setImplementation(method, (IMP)LSHookedNEHotspotFetchCurrent);
}

__attribute__((constructor)) static void LSInitializeWiFiSpoofer(void) {
    LSInstallNEHotspotNetworkHook();
}

__attribute__((used)) static struct {
    const void *replacement;
    const void *replacee;
} ls_wifi_interposers[] __attribute__((section("__DATA,__interpose"))) = {
    { (const void *)LSHookedCNCopySupportedInterfaces, (const void *)CNCopySupportedInterfaces },
    { (const void *)LSHookedCNCopyCurrentNetworkInfo, (const void *)CNCopyCurrentNetworkInfo }
};
