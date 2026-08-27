#import "LSAppIdentifierProvider.h"

static NSString * const kLSActivationSuiteName = @"com.xsgps.dylib";
static NSString * const kLSLegacyActivationSuiteName = @"com.locationspoofer.dylib";
static NSString * const kLSOldAppUUIDKey = @"LSOldAppUUIDForTransfer";
static NSString * const kLSSavedCurrentAppUUIDKey = @"LSSavedCurrentAppUUID";
static NSString * const kLSTestApplicationUUIDKey = @"LSTestApplicationUUID";
static NSString * const kLSTestApplicationUUIDEnabledKey = @"LSTestApplicationUUIDEnabled";
static NSString * const kLSCustomAppUUIDKey = @"Custom_App_UUID";
static NSString * const kLSUUIDDiskStoreFileName = @"com.xsgps.uuid.plist";
static NSString * const kLSLegacyUUIDDiskStoreFileName = @"com.locationspoofer.uuid.plist";

// UUID الحقيقي للتطبيق بصيغة 32 خانة بدون شرطات؛ هذه هي الصيغة المطلوبة للنسخ والتفعيل.
static NSString * const kLSBundledApplicationUUID = @"6bb0cdeeb3574c5aa7fd6fb6179c8df0";

@implementation LSAppIdentifierProvider

+ (NSString *)uuidDiskStorePath {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSArray<NSString *> *preferredDirectories = @[@"/var/mobile/Library/Preferences", @"/var/jb/var/mobile/Library/Preferences"];
    for (NSString *directory in preferredDirectories) {
        BOOL isDirectory = NO;
        if ([fileManager fileExistsAtPath:directory isDirectory:&isDirectory] && isDirectory && [fileManager isWritableFileAtPath:directory]) {
            return [directory stringByAppendingPathComponent:kLSUUIDDiskStoreFileName];
        }
    }

    NSString *libraryDirectory = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    if (libraryDirectory.length > 0) {
        NSString *preferencesDirectory = [libraryDirectory stringByAppendingPathComponent:@"Preferences"];
        [fileManager createDirectoryAtPath:preferencesDirectory withIntermediateDirectories:YES attributes:nil error:nil];
        return [preferencesDirectory stringByAppendingPathComponent:kLSUUIDDiskStoreFileName];
    }

    return [NSTemporaryDirectory() stringByAppendingPathComponent:kLSUUIDDiskStoreFileName];
}

+ (NSArray<NSString *> *)uuidStoreSearchDirectories {
    NSMutableArray<NSString *> *directories = [NSMutableArray array];
    for (NSString *directory in @[@"/var/mobile/Library/Preferences", @"/var/jb/var/mobile/Library/Preferences"]) {
        if (directory.length > 0 && ![directories containsObject:directory]) {
            [directories addObject:directory];
        }
    }

    NSString *libraryDirectory = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    if (libraryDirectory.length > 0) {
        NSString *preferencesDirectory = [libraryDirectory stringByAppendingPathComponent:@"Preferences"];
        if (preferencesDirectory.length > 0 && ![directories containsObject:preferencesDirectory]) {
            [directories addObject:preferencesDirectory];
        }
    }

    NSString *temporaryDirectory = NSTemporaryDirectory();
    if (temporaryDirectory.length > 0 && ![directories containsObject:temporaryDirectory]) {
        [directories addObject:temporaryDirectory];
    }

    return directories.copy;
}

+ (NSDictionary *)legacyUUIDDiskStore {
    NSMutableDictionary *legacy = [NSMutableDictionary dictionary];
    NSArray<NSString *> *keys = @[
        kLSOldAppUUIDKey,
        kLSSavedCurrentAppUUIDKey,
        kLSTestApplicationUUIDKey,
        kLSTestApplicationUUIDEnabledKey,
        kLSCustomAppUUIDKey
    ];

    NSUserDefaults *legacyDefaults = [[NSUserDefaults alloc] initWithSuiteName:kLSLegacyActivationSuiteName];
    for (NSString *key in keys) {
        id value = [legacyDefaults objectForKey:key];
        if (value && value != NSNull.null) {
            legacy[key] = value;
        }
    }

    for (NSString *directory in [self uuidStoreSearchDirectories]) {
        NSString *path = [directory stringByAppendingPathComponent:kLSLegacyUUIDDiskStoreFileName];
        NSDictionary *dictionary = [NSDictionary dictionaryWithContentsOfFile:path];
        if (![dictionary isKindOfClass:NSDictionary.class]) {
            continue;
        }
        for (NSString *key in keys) {
            id value = dictionary[key];
            if (value && value != NSNull.null && !legacy[key]) {
                legacy[key] = value;
            }
        }
    }

    return legacy.copy;
}

+ (NSMutableDictionary *)uuidDiskStore {
    static NSMutableDictionary *store = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSDictionary *dictionary = [NSDictionary dictionaryWithContentsOfFile:[self uuidDiskStorePath]];
        store = [dictionary isKindOfClass:NSDictionary.class] ? [dictionary mutableCopy] : [NSMutableDictionary dictionary];
        NSDictionary *legacy = [self legacyUUIDDiskStore];
        BOOL changed = NO;
        for (NSString *key in legacy.allKeys) {
            id value = legacy[key];
            if (value && value != NSNull.null && !store[key]) {
                store[key] = value;
                changed = YES;
            }
        }
        if (changed) {
            NSString *path = [self uuidDiskStorePath];
            NSString *directory = [path stringByDeletingLastPathComponent];
            if (directory.length > 0) {
                [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
            }
            [store writeToFile:path atomically:YES];
        }
    });
    return store;
}

+ (void)writeUUIDDiskStore {
    NSString *path = [self uuidDiskStorePath];
    if (path.length == 0) {
        return;
    }

    NSString *directory = [path stringByDeletingLastPathComponent];
    if (directory.length > 0) {
        [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    }
    [[self uuidDiskStore] writeToFile:path atomically:YES];
}

+ (NSUserDefaults *)sharedDefaults {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kLSActivationSuiteName];
    return defaults ?: NSUserDefaults.standardUserDefaults;
}

+ (NSArray<NSUserDefaults *> *)allWritableDefaults {
    NSUserDefaults *shared = [self sharedDefaults];
    NSUserDefaults *standard = NSUserDefaults.standardUserDefaults;
    if (shared == standard) {
        return @[standard];
    }
    return @[shared, standard];
}

+ (nullable id)objectForKey:(NSString *)key {
    id value = nil;
    for (NSUserDefaults *defaults in [self allWritableDefaults]) {
        value = [defaults objectForKey:key];
        if (value) {
            break;
        }
    }

    if (!value) {
        value = [self uuidDiskStore][key];
    }

    if (value && value != NSNull.null) {
        for (NSUserDefaults *defaults in [self allWritableDefaults]) {
            if (![defaults objectForKey:key]) {
                [defaults setObject:value forKey:key];
                [defaults synchronize];
            }
        }
        if (![self uuidDiskStore][key]) {
            [self uuidDiskStore][key] = value;
            [self writeUUIDDiskStore];
        }
    }

    return value;
}

+ (void)setObject:(id)object forKey:(NSString *)key {
    for (NSUserDefaults *defaults in [self allWritableDefaults]) {
        if (object) {
            [defaults setObject:object forKey:key];
        } else {
            [defaults removeObjectForKey:key];
        }
        [defaults synchronize];
    }

    if (object) {
        [self uuidDiskStore][key] = object;
    } else {
        [[self uuidDiskStore] removeObjectForKey:key];
    }
    [self writeUUIDDiskStore];
}

+ (void)setBool:(BOOL)value forKey:(NSString *)key {
    for (NSUserDefaults *defaults in [self allWritableDefaults]) {
        [defaults setBool:value forKey:key];
        [defaults synchronize];
    }
    [self uuidDiskStore][key] = @(value);
    [self writeUUIDDiskStore];
}

+ (void)removeObjectForKey:(NSString *)key {
    for (NSUserDefaults *defaults in [self allWritableDefaults]) {
        [defaults removeObjectForKey:key];
        [defaults synchronize];
    }
    [[self uuidDiskStore] removeObjectForKey:key];
    [self writeUUIDDiskStore];
}

+ (nullable NSString *)normalizedApplicationIdentifier:(NSString *)identifier {
    if (![identifier isKindOfClass:NSString.class]) {
        return nil;
    }

    NSString *trimmed = [identifier stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        return nil;
    }

    NSMutableString *compact = [NSMutableString stringWithCapacity:32];
    NSCharacterSet *hexSet = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
    for (NSUInteger index = 0; index < trimmed.length; index++) {
        unichar c = [trimmed characterAtIndex:index];
        if (c == '-' || c == ' ' || c == '\n' || c == '\t') {
            continue;
        }
        if (![hexSet characterIsMember:c]) {
            return nil;
        }
        [compact appendFormat:@"%C", c];
    }

    if (compact.length != 32) {
        return nil;
    }

    return compact.lowercaseString;
}

+ (nullable NSString *)hyphenatedUUIDStringFromIdentifier:(NSString *)identifier {
    NSString *compact = [self normalizedApplicationIdentifier:identifier];
    if (compact.length != 32) {
        return nil;
    }

    NSString *hyphenated = [NSString stringWithFormat:@"%@-%@-%@-%@-%@",
                            [compact substringWithRange:NSMakeRange(0, 8)],
                            [compact substringWithRange:NSMakeRange(8, 4)],
                            [compact substringWithRange:NSMakeRange(12, 4)],
                            [compact substringWithRange:NSMakeRange(16, 4)],
                            [compact substringWithRange:NSMakeRange(20, 12)]];
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:hyphenated];
    return uuid ? uuid.UUIDString : nil;
}

+ (NSString *)currentApplicationIdentifier {
    NSString *normalized = [self normalizedApplicationIdentifier:kLSBundledApplicationUUID];
    if (normalized.length > 0) {
        return normalized;
    }

    NSString *value = UIDevice.currentDevice.identifierForVendor.UUIDString;
    NSString *fallback = [self normalizedApplicationIdentifier:value];
    return fallback.length > 0 ? fallback : @"غير قادر على القراءة";
}

+ (nullable NSString *)savedCurrentApplicationIdentifier {
    NSString *value = [self objectForKey:kLSSavedCurrentAppUUIDKey];
    return [self normalizedApplicationIdentifier:value];
}

+ (nullable NSString *)storedLegacyApplicationIdentifier {
    NSString *value = [self objectForKey:kLSOldAppUUIDKey];
    return [self normalizedApplicationIdentifier:value];
}

+ (nullable NSString *)replacementApplicationIdentifier {
    NSArray<NSString *> *keys = @[kLSTestApplicationUUIDKey, kLSOldAppUUIDKey, kLSCustomAppUUIDKey];
    for (NSString *key in keys) {
        NSString *value = [self objectForKey:key];
        NSString *normalized = [self normalizedApplicationIdentifier:value];
        if (normalized.length > 0) {
            return normalized;
        }
    }
    return nil;
}

+ (BOOL)isReplacementIdentifierEnabled {
    BOOL enabled = NO;
    for (NSUserDefaults *defaults in [self allWritableDefaults]) {
        enabled = enabled || [defaults boolForKey:kLSTestApplicationUUIDEnabledKey];
    }
    return enabled && [self replacementApplicationIdentifier].length > 0;
}

+ (NSString *)applicationIdentifierForTestMode {
    NSString *replacement = [self replacementApplicationIdentifier];
    if ([self isReplacementIdentifierEnabled] && replacement.length > 0) {
        return replacement;
    }
    return [self currentApplicationIdentifier];
}

+ (NSString *)applicationIdentifierForClipboard {
    NSString *identifier = [self applicationIdentifierForTestMode];
    NSString *normalized = [self normalizedApplicationIdentifier:identifier];
    return normalized.length > 0 ? normalized : identifier;
}

+ (nullable NSString *)activeIdentifierForVendorString {
    NSUUID *uuid = UIDevice.currentDevice.identifierForVendor;
    NSString *value = uuid.UUIDString;
    return [self normalizedApplicationIdentifier:value];
}

+ (BOOL)isReplacementIdentifierAppliedInCurrentProcess {
    NSString *replacement = [self replacementApplicationIdentifier];
    NSString *active = [self activeIdentifierForVendorString];
    return replacement.length == 32 && active.length == 32 && [replacement isEqualToString:active];
}

+ (BOOL)saveReplacementApplicationIdentifier:(NSString *)identifier errorMessage:(NSString * _Nullable * _Nullable)errorMessage {
    NSString *normalized = [self normalizedApplicationIdentifier:identifier];
    if (normalized.length != 32) {
        if (errorMessage) {
            *errorMessage = @"صيغة المعرّف غير صحيحة. الصق UUID من 32 خانة مثل 6bb0cdeeb3574c5aa7fd6fb6179c8df0 أو بصيغة 00000000-0000-0000-0000-000000000000.";
        }
        return NO;
    }

    NSString *hyphenated = [self hyphenatedUUIDStringFromIdentifier:normalized];
    if (hyphenated.length == 0) {
        if (errorMessage) {
            *errorMessage = @"صيغة UUID غير صحيحة.";
        }
        return NO;
    }

    [self setObject:normalized forKey:kLSOldAppUUIDKey];
    [self setObject:normalized forKey:kLSTestApplicationUUIDKey];
    // هذا المفتاح تقرأه دالة Hook الخاصة بـ identifierForVendor ويجب أن يبقى بصيغة NSUUID ذات الشرطات.
    [self setObject:hyphenated forKey:kLSCustomAppUUIDKey];
    [self setBool:YES forKey:kLSTestApplicationUUIDEnabledKey];
    return YES;
}

+ (void)clearReplacementApplicationIdentifier {
    [self removeObjectForKey:kLSOldAppUUIDKey];
    [self removeObjectForKey:kLSTestApplicationUUIDKey];
    [self removeObjectForKey:kLSCustomAppUUIDKey];
    [self setBool:NO forKey:kLSTestApplicationUUIDEnabledKey];
}

@end
