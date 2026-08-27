#import "LSActivationManager.h"
#import "LSAppIdentifierProvider.h"

#import <CommonCrypto/CommonDigest.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <math.h>
#import <sys/utsname.h>

static NSString * const kLSActivationServerBaseURL = @"https://location-spoofer-api.hso0ooni14.workers.dev";

static NSString * const kLSActivationSuiteName = @"com.xsgps.dylib";
static NSString * const kLSActivationDiskStoreFileName = @"com.xsgps.activation.plist";
static NSString * const kLSLegacyActivationSuiteName = @"com.locationspoofer.dylib";
static NSString * const kLSLegacyActivationDiskStoreFileName = @"com.locationspoofer.activation.plist";
static NSString * const kLSActivationDeviceIDKey = @"LSActivationDeviceID";
static NSString * const kLSActivationCodeKey = @"LSActivationCode";
static NSString * const kLSActivationCodeHashKey = @"LSActivationCodeHash";
static NSString * const kLSActivationTokenKey = @"LSActivationToken";
static NSString * const kLSActivationDateKey = @"LSActivationDate";
static NSString * const kLSActivationLastServerMessageKey = @"LSActivationLastServerMessage";
static NSString * const kLSActivationExpiresAtKey = @"LSActivationExpiresAt";
static NSString * const kLSActivationPlanKey = @"LSActivationPlan";
static NSString * const kLSActivationLastDeviceInfoSyncKey = @"LSActivationLastDeviceInfoSync";

static const NSUInteger kLSActivationCodeLength = 10;
static const NSTimeInterval kLSActivationTimeout = 18.0;
static const char *kLSActivationLocalSecret = "LSv11-server-bound-local-token-4a9b5c1d";

@interface LSActivationManager ()
@property (nonatomic, strong) NSUserDefaults *defaults;
@property (nonatomic, strong) NSUserDefaults *fallbackDefaults;
@property (nonatomic, strong) NSMutableDictionary *diskStore;
@property (nonatomic, copy) NSString *diskStorePath;
@end

@implementation LSActivationManager

+ (instancetype)shared {
    static LSActivationManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[LSActivationManager alloc] initPrivate];
    });
    return manager;
}

+ (void)loadEarly {
    (void)[LSActivationManager shared];
}

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        _defaults = [[NSUserDefaults alloc] initWithSuiteName:kLSActivationSuiteName] ?: NSUserDefaults.standardUserDefaults;
        _fallbackDefaults = NSUserDefaults.standardUserDefaults;
        _diskStorePath = [self activationDiskStorePath];
        _diskStore = [[self loadActivationDiskStore] mutableCopy] ?: [NSMutableDictionary dictionary];
        [self migrateLegacyActivationStateIfNeeded];
        [self hydrateDefaultsFromDiskStoreIfNeeded];
        [self scheduleDeviceInfoSyncIfNeeded];
    }
    return self;
}

- (NSString *)activationDiskStorePath {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSArray<NSString *> *preferredDirectories = @[@"/var/mobile/Library/Preferences", @"/var/jb/var/mobile/Library/Preferences"];
    for (NSString *directory in preferredDirectories) {
        BOOL isDirectory = NO;
        if ([fileManager fileExistsAtPath:directory isDirectory:&isDirectory] && isDirectory && [fileManager isWritableFileAtPath:directory]) {
            return [directory stringByAppendingPathComponent:kLSActivationDiskStoreFileName];
        }
    }

    NSString *libraryDirectory = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    if (libraryDirectory.length > 0) {
        NSString *preferencesDirectory = [libraryDirectory stringByAppendingPathComponent:@"Preferences"];
        [fileManager createDirectoryAtPath:preferencesDirectory withIntermediateDirectories:YES attributes:nil error:nil];
        return [preferencesDirectory stringByAppendingPathComponent:kLSActivationDiskStoreFileName];
    }

    return [NSTemporaryDirectory() stringByAppendingPathComponent:kLSActivationDiskStoreFileName];
}

- (NSArray<NSString *> *)activationStoreSearchDirectories {
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

- (NSDictionary *)loadLegacyActivationDiskStore {
    NSMutableDictionary *legacy = [NSMutableDictionary dictionary];
    NSArray<NSString *> *keys = @[
        kLSActivationDeviceIDKey,
        kLSActivationCodeKey,
        kLSActivationCodeHashKey,
        kLSActivationTokenKey,
        kLSActivationDateKey,
        kLSActivationLastServerMessageKey,
        kLSActivationExpiresAtKey,
        kLSActivationPlanKey,
        kLSActivationLastDeviceInfoSyncKey
    ];

    NSUserDefaults *legacyDefaults = [[NSUserDefaults alloc] initWithSuiteName:kLSLegacyActivationSuiteName];
    for (NSString *key in keys) {
        id value = [legacyDefaults objectForKey:key];
        if (value && value != NSNull.null) {
            legacy[key] = value;
        }
    }

    for (NSString *directory in [self activationStoreSearchDirectories]) {
        NSString *path = [directory stringByAppendingPathComponent:kLSLegacyActivationDiskStoreFileName];
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

- (void)migrateLegacyActivationStateIfNeeded {
    NSDictionary *legacy = [self loadLegacyActivationDiskStore];
    if (legacy.count == 0) {
        return;
    }

    BOOL changed = NO;
    for (NSString *key in legacy.allKeys) {
        id value = legacy[key];
        if (!value || value == NSNull.null || self.diskStore[key]) {
            continue;
        }
        self.diskStore[key] = value;
        changed = YES;
    }

    if (changed) {
        [self writeActivationDiskStore];
    }
}

- (NSDictionary *)loadActivationDiskStore {
    if (self.diskStorePath.length == 0) {
        return @{};
    }
    NSDictionary *dictionary = [NSDictionary dictionaryWithContentsOfFile:self.diskStorePath];
    return [dictionary isKindOfClass:NSDictionary.class] ? dictionary : @{};
}

- (void)writeActivationDiskStore {
    if (self.diskStorePath.length == 0) {
        return;
    }

    NSString *directory = [self.diskStorePath stringByDeletingLastPathComponent];
    if (directory.length > 0) {
        [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    }
    [self.diskStore writeToFile:self.diskStorePath atomically:YES];
}

- (void)hydrateDefaultsFromDiskStoreIfNeeded {
    if (self.diskStore.count == 0) {
        return;
    }

    for (NSString *key in self.diskStore.allKeys) {
        id value = self.diskStore[key];
        if (!value || value == NSNull.null) {
            continue;
        }
        for (NSUserDefaults *defaults in [self allActivationDefaults]) {
            if (![defaults objectForKey:key]) {
                [defaults setObject:value forKey:key];
                [defaults synchronize];
            }
        }
    }
}

- (NSArray<NSUserDefaults *> *)allActivationDefaults {
    if (self.defaults == self.fallbackDefaults) {
        return @[self.defaults];
    }
    return @[self.defaults, self.fallbackDefaults];
}

- (id)objectForActivationKey:(NSString *)key {
    id value = nil;
    for (NSUserDefaults *defaults in [self allActivationDefaults]) {
        value = [defaults objectForKey:key];
        if (value) {
            break;
        }
    }

    if (!value) {
        value = self.diskStore[key];
    }

    if (value && value != NSNull.null) {
        // عكس القيمة بين الـ suite والـ standard وملف Plist ثابت حتى لا تضيع عند إعادة فتح التطبيق أو تغيّر بيئة الحقن.
        BOOL diskNeedsWrite = !self.diskStore[key];
        for (NSUserDefaults *defaults in [self allActivationDefaults]) {
            if (![defaults objectForKey:key]) {
                [defaults setObject:value forKey:key];
                [defaults synchronize];
            }
        }
        if (diskNeedsWrite) {
            self.diskStore[key] = value;
            [self writeActivationDiskStore];
        }
    }
    return value;
}

- (NSString *)stringForActivationKey:(NSString *)key {
    id value = [self objectForActivationKey:key];
    return [value isKindOfClass:NSString.class] ? (NSString *)value : nil;
}

- (void)setActivationObject:(id)object forKey:(NSString *)key {
    for (NSUserDefaults *defaults in [self allActivationDefaults]) {
        if (object) {
            [defaults setObject:object forKey:key];
        } else {
            [defaults removeObjectForKey:key];
        }
        [defaults synchronize];
    }

    if (object) {
        self.diskStore[key] = object;
    } else {
        [self.diskStore removeObjectForKey:key];
    }
    [self writeActivationDiskStore];
}

- (void)removeActivationObjectForKey:(NSString *)key {
    for (NSUserDefaults *defaults in [self allActivationDefaults]) {
        [defaults removeObjectForKey:key];
        [defaults synchronize];
    }
    [self.diskStore removeObjectForKey:key];
    [self writeActivationDiskStore];
}

- (void)synchronizeActivationDefaults {
    for (NSUserDefaults *defaults in [self allActivationDefaults]) {
        [defaults synchronize];
    }
    [self writeActivationDiskStore];
}

- (NSString *)preferredDeviceIdentifier {
    NSString *identifier = [LSAppIdentifierProvider applicationIdentifierForClipboard];
    if (identifier.length >= 8) {
        return identifier;
    }

    NSString *vendorIdentifier = UIDevice.currentDevice.identifierForVendor.UUIDString;
    NSString *normalizedVendorIdentifier = [LSAppIdentifierProvider normalizedApplicationIdentifier:vendorIdentifier];
    if (normalizedVendorIdentifier.length >= 8) {
        return normalizedVendorIdentifier;
    }

    return NSUUID.UUID.UUIDString;
}

- (NSArray<NSString *> *)activationDeviceIdentifierCandidates {
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    void (^append)(NSString *) = ^(NSString *value) {
        if (value.length == 0) {
            return;
        }
        if (![candidates containsObject:value]) {
            [candidates addObject:value];
        }
        NSString *normalized = [LSAppIdentifierProvider normalizedApplicationIdentifier:value];
        if (normalized.length > 0 && ![candidates containsObject:normalized]) {
            [candidates addObject:normalized];
        }
    };

    append([self preferredDeviceIdentifier]);
    append([self stringForActivationKey:kLSActivationDeviceIDKey]);
    append(UIDevice.currentDevice.identifierForVendor.UUIDString);
    return candidates.copy;
}

- (NSString *)deviceIdentifier {
    @synchronized (self) {
        NSString *identifier = [self preferredDeviceIdentifier];
        NSString *stored = [self stringForActivationKey:kLSActivationDeviceIDKey];
        if (![stored isEqualToString:identifier] && identifier.length >= 8) {
            [self setActivationObject:identifier forKey:kLSActivationDeviceIDKey];
        }
        return identifier.length >= 8 ? identifier : (stored.length >= 8 ? stored : NSUUID.UUID.UUIDString);
    }
}

- (BOOL)isActivated {
    @synchronized (self) {
        NSString *storedCode = [self stringForActivationKey:kLSActivationCodeKey];
        NSString *codeHash = [self stringForActivationKey:kLSActivationCodeHashKey];
        NSString *token = [self stringForActivationKey:kLSActivationTokenKey];

        if (storedCode.length != kLSActivationCodeLength ||
            codeHash.length != CC_SHA256_DIGEST_LENGTH * 2) {
            return NO;
        }

        // تأكد أن الهاش يطابق الكود المحفوظ. إذا كان التوكن المحلي ناقص أو تغيّر معرف التطبيق، نعيد بناءه بدل طلب الكود كل مرة.
        NSString *storedCodeHash = [self sha256HexForString:storedCode];
        if (![storedCodeHash isEqualToString:codeHash]) {
            return NO;
        }

        BOOL tokenMatches = NO;
        if (token.length == CC_SHA256_DIGEST_LENGTH * 2) {
            for (NSString *candidateDeviceID in [self activationDeviceIdentifierCandidates]) {
                NSString *expected = [self activationTokenForCodeHash:codeHash deviceID:candidateDeviceID];
                if ([token isEqualToString:expected]) {
                    tokenMatches = YES;
                    break;
                }
            }
        }

        if (!tokenMatches) {
            NSString *repairDeviceID = [self stringForActivationKey:kLSActivationDeviceIDKey];
            if (repairDeviceID.length < 8) {
                repairDeviceID = [self preferredDeviceIdentifier];
            }
            if (repairDeviceID.length >= 8) {
                NSString *repairedToken = [self activationTokenForCodeHash:codeHash deviceID:repairDeviceID];
                if (repairedToken.length == CC_SHA256_DIGEST_LENGTH * 2) {
                    [self setActivationObject:repairDeviceID forKey:kLSActivationDeviceIDKey];
                    [self setActivationObject:repairedToken forKey:kLSActivationTokenKey];
                    tokenMatches = YES;
                }
            }
        }

        if (!tokenMatches) {
            return NO;
        }

        NSDate *expiresAt = self.expirationDate;
        if (expiresAt && [expiresAt timeIntervalSinceNow] <= 0.0) {
            return NO;
        }

        return YES;
    }
}

- (NSDate *)expirationDate {
    id value = [self objectForActivationKey:kLSActivationExpiresAtKey];
    return [value isKindOfClass:NSDate.class] ? (NSDate *)value : nil;
}

- (NSInteger)daysRemaining {
    NSDate *expiresAt = self.expirationDate;
    if (!expiresAt) {
        return -1;
    }
    NSTimeInterval seconds = [expiresAt timeIntervalSinceNow];
    if (seconds <= 0.0) {
        return 0;
    }
    return (NSInteger)ceil(seconds / 86400.0);
}

- (NSString *)subscriptionStatusText {
    if (!self.isActivated) {
        return @"";
    }

    NSDate *expiresAt = self.expirationDate;
    if (expiresAt) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"ar"];
        formatter.dateFormat = @"yyyy/MM/dd";
        NSInteger days = self.daysRemaining;
        NSString *dayText = days == 1 ? @"يوم واحد" : [NSString stringWithFormat:@"%ld يوم", (long)days];
        return [NSString stringWithFormat:@"متبقي %@ · ينتهي %@", dayText, [formatter stringFromDate:expiresAt]];
    }

    NSString *plan = [self stringForActivationKey:kLSActivationPlanKey];
    if (plan.length > 0) {
        return [NSString stringWithFormat:@"الاشتراك مفعل · %@", plan];
    }

    return @"الاشتراك مفعل";
}

- (BOOL)activateWithCode:(NSString *)code errorMessage:(NSString **)errorMessage {
    NSString *normalized = [self normalizedCodeFromString:code];
    if (normalized.length != kLSActivationCodeLength) {
        if (errorMessage) {
            *errorMessage = @"الكود يجب أن يكون 10 خانات من حروف وأرقام";
        }
        return NO;
    }

    NSString *serverMessage = nil;
    NSDictionary *serverResponse = [self activationResponseWithCode:normalized errorMessage:&serverMessage];
    if (!serverResponse) {
        if (errorMessage) {
            *errorMessage = serverMessage.length > 0 ? serverMessage : @"تعذر التحقق من الكود عبر السيرفر";
        }
        return NO;
    }

    NSString *codeHash = [self sha256HexForString:normalized];
    NSString *token = [self activationTokenForCodeHash:codeHash deviceID:self.deviceIdentifier];

    @synchronized (self) {
        [self setActivationObject:normalized forKey:kLSActivationCodeKey];
        [self setActivationObject:codeHash forKey:kLSActivationCodeHashKey];
        [self setActivationObject:token forKey:kLSActivationTokenKey];
        [self setActivationObject:[NSDate date] forKey:kLSActivationDateKey];
        if (serverMessage.length > 0) {
            [self setActivationObject:serverMessage forKey:kLSActivationLastServerMessageKey];
        }

        NSDate *expiresAt = [self expirationDateFromActivationResponse:serverResponse];
        if (expiresAt) {
            [self setActivationObject:expiresAt forKey:kLSActivationExpiresAtKey];
        } else {
            [self removeActivationObjectForKey:kLSActivationExpiresAtKey];
        }

        NSString *plan = [self stringFromResponse:serverResponse keys:@[@"plan", @"subscription", @"tier", @"name"]];
        if (plan.length > 0) {
            [self setActivationObject:plan forKey:kLSActivationPlanKey];
        } else {
            [self removeActivationObjectForKey:kLSActivationPlanKey];
        }
        [self synchronizeActivationDefaults];
    }

    return YES;
}


- (void)scheduleDeviceInfoSyncIfNeeded {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [self syncDeviceInfoWithServerIfNeeded];
    });
}

- (void)syncDeviceInfoWithServerIfNeeded {
    if (!self.isActivated) {
        return;
    }

    NSDate *lastSync = nil;
    id lastValue = [self objectForActivationKey:kLSActivationLastDeviceInfoSyncKey];
    if ([lastValue isKindOfClass:NSDate.class]) {
        lastSync = (NSDate *)lastValue;
    }
    if (lastSync && fabs([lastSync timeIntervalSinceNow]) < 21600.0) {
        return;
    }

    NSString *storedCode = [self stringForActivationKey:kLSActivationCodeKey];
    NSString *normalized = [self normalizedCodeFromString:storedCode];
    if (normalized.length != kLSActivationCodeLength) {
        return;
    }

    NSMutableDictionary *payload = [[self deviceInfoPayload] mutableCopy];
    payload[@"code"] = normalized;
    payload[@"device_id"] = self.deviceIdentifier ?: @"";

    NSString *error = nil;
    NSDictionary *response = [self postJSONToPath:@"/verify" payload:payload.copy errorMessage:&error];
    id okValue = response[@"ok"];
    if ([okValue respondsToSelector:@selector(boolValue)] && [okValue boolValue]) {
        [self setActivationObject:[NSDate date] forKey:kLSActivationLastDeviceInfoSyncKey];
    }
}

- (NSString *)normalizedCodeFromString:(NSString *)string {
    if (string.length == 0) {
        return @"";
    }

    NSMutableString *result = [NSMutableString stringWithCapacity:kLSActivationCodeLength];
    NSString *uppercase = string.uppercaseString;

    for (NSUInteger i = 0; i < uppercase.length && result.length < kLSActivationCodeLength; i++) {
        unichar c = [uppercase characterAtIndex:i];
        BOOL isDigit = (c >= '0' && c <= '9');
        BOOL isUppercaseLetter = (c >= 'A' && c <= 'Z');
        if (isDigit || isUppercaseLetter) {
            [result appendFormat:@"%C", c];
        }
    }

    return result.copy;
}

- (BOOL)sendActivationRequestWithCode:(NSString *)code errorMessage:(NSString **)errorMessage {
    return [self activationResponseWithCode:code errorMessage:errorMessage] != nil;
}

- (NSDictionary *)activationResponseWithCode:(NSString *)code errorMessage:(NSString **)errorMessage {
    NSMutableDictionary *payload = [[self deviceInfoPayload] mutableCopy];
    payload[@"code"] = code ?: @"";
    payload[@"device_id"] = self.deviceIdentifier ?: @"";

    NSDictionary *response = [self postJSONToPath:@"/activate" payload:payload.copy errorMessage:errorMessage];
    if (!response) {
        return nil;
    }

    id okValue = response[@"ok"];
    NSString *message = [response[@"message"] isKindOfClass:NSString.class] ? response[@"message"] : nil;
    if (message.length > 0 && errorMessage) {
        *errorMessage = message;
    }

    BOOL accepted = [okValue respondsToSelector:@selector(boolValue)] && [okValue boolValue];
    return accepted ? response : nil;
}

- (NSDictionary *)postJSONToPath:(NSString *)path payload:(NSDictionary *)payload errorMessage:(NSString **)errorMessage {
    NSString *urlString = [kLSActivationServerBaseURL stringByAppendingString:path ?: @""];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        if (errorMessage) {
            *errorMessage = @"رابط السيرفر غير صحيح";
        }
        return nil;
    }

    NSError *jsonError = nil;
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:payload ?: @{} options:0 error:&jsonError];
    if (!bodyData || jsonError) {
        if (errorMessage) {
            *errorMessage = @"تعذر تجهيز بيانات التفعيل";
        }
        return nil;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = kLSActivationTimeout;
    request.HTTPBody = bodyData;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    __block NSData *responseData = nil;
    __block NSURLResponse *urlResponse = nil;
    __block NSError *requestError = nil;

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        responseData = data;
        urlResponse = response;
        requestError = error;
        dispatch_semaphore_signal(semaphore);
    }];

    [task resume];

    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kLSActivationTimeout * NSEC_PER_SEC));
    long waitResult = dispatch_semaphore_wait(semaphore, timeout);
    if (waitResult != 0) {
        [task cancel];
        if (errorMessage) {
            *errorMessage = @"انتهت مهلة الاتصال بالسيرفر";
        }
        return nil;
    }

    if (requestError) {
        if (errorMessage) {
            *errorMessage = @"تعذر الاتصال بالسيرفر، تأكد من الإنترنت";
        }
        return nil;
    }

    NSInteger statusCode = 0;
    if ([urlResponse isKindOfClass:NSHTTPURLResponse.class]) {
        statusCode = ((NSHTTPURLResponse *)urlResponse).statusCode;
    }

    if (responseData.length == 0) {
        if (errorMessage) {
            *errorMessage = @"السيرفر لم يرجع نتيجة";
        }
        return nil;
    }

    NSError *parseError = nil;
    id object = [NSJSONSerialization JSONObjectWithData:responseData options:0 error:&parseError];
    if (![object isKindOfClass:NSDictionary.class]) {
        if (errorMessage) {
            *errorMessage = @"رد السيرفر غير مفهوم";
        }
        return nil;
    }

    NSDictionary *dictionary = (NSDictionary *)object;
    NSString *serverMessage = [dictionary[@"message"] isKindOfClass:NSString.class] ? dictionary[@"message"] : nil;
    if (statusCode >= 400) {
        if (errorMessage) {
            *errorMessage = serverMessage.length > 0 ? serverMessage : @"رفض السيرفر عملية التفعيل";
        }
        return dictionary;
    }

    if (parseError && errorMessage) {
        *errorMessage = @"تعذر قراءة رد السيرفر";
    }

    return dictionary;
}

- (NSString *)stringFromResponse:(NSDictionary *)response keys:(NSArray<NSString *> *)keys {
    for (NSString *key in keys) {
        id value = response[key];
        if ([value isKindOfClass:NSString.class] && [(NSString *)value length] > 0) {
            return (NSString *)value;
        }
        if ([value respondsToSelector:@selector(stringValue)] && ![value isKindOfClass:NSDictionary.class]) {
            NSString *stringValue = [value stringValue];
            if (stringValue.length > 0) {
                return stringValue;
            }
        }
    }

    NSArray<NSString *> *nestedKeys = @[@"data", @"code", @"license", @"subscription", @"result"];
    for (NSString *nestedKey in nestedKeys) {
        id nested = response[nestedKey];
        if ([nested isKindOfClass:NSDictionary.class]) {
            NSString *nestedString = [self stringFromResponse:(NSDictionary *)nested keys:keys];
            if (nestedString.length > 0) {
                return nestedString;
            }
        }
    }
    return nil;
}

- (NSDate *)expirationDateFromActivationResponse:(NSDictionary *)response {
    id value = nil;
    NSArray<NSString *> *dateKeys = @[@"expires_at", @"expiresAt", @"expiration", @"expires", @"end_date", @"valid_until"];
    for (NSString *key in dateKeys) {
        value = response[key];
        if (value) {
            break;
        }
    }

    NSDate *date = [self dateFromServerValue:value];
    if (date) {
        return date;
    }

    NSArray<NSString *> *daysKeys = @[@"days_remaining", @"remaining_days", @"days", @"valid_days"];
    for (NSString *key in daysKeys) {
        id daysValue = response[key];
        if ([daysValue respondsToSelector:@selector(doubleValue)]) {
            double days = MAX([daysValue doubleValue], 0.0);
            return [NSDate dateWithTimeIntervalSinceNow:days * 86400.0];
        }
    }

    NSArray<NSString *> *nestedKeys = @[@"data", @"code", @"license", @"subscription", @"result"];
    for (NSString *nestedKey in nestedKeys) {
        id nested = response[nestedKey];
        if ([nested isKindOfClass:NSDictionary.class]) {
            NSDate *nestedDate = [self expirationDateFromActivationResponse:(NSDictionary *)nested];
            if (nestedDate) {
                return nestedDate;
            }
        }
    }

    return nil;
}

- (NSDate *)dateFromServerValue:(id)value {
    if (!value || value == NSNull.null) {
        return nil;
    }
    if ([value isKindOfClass:NSDate.class]) {
        return (NSDate *)value;
    }
    if ([value isKindOfClass:NSNumber.class]) {
        NSTimeInterval timestamp = [(NSNumber *)value doubleValue];
        if (timestamp > 100000000000.0) {
            timestamp = timestamp / 1000.0;
        }
        return [NSDate dateWithTimeIntervalSince1970:timestamp];
    }
    if (![value isKindOfClass:NSString.class]) {
        return nil;
    }

    NSString *string = [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (string.length == 0) {
        return nil;
    }

    if (@available(iOS 10.0, *)) {
        NSISO8601DateFormatter *isoFormatter = [[NSISO8601DateFormatter alloc] init];
        NSDate *isoDate = [isoFormatter dateFromString:string];
        if (isoDate) {
            return isoDate;
        }
    }

    NSArray<NSString *> *formats = @[@"yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ", @"yyyy-MM-dd'T'HH:mm:ssZZZZZ", @"yyyy-MM-dd HH:mm:ss", @"yyyy-MM-dd"];
    for (NSString *format in formats) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = NSTimeZone.localTimeZone;
        formatter.dateFormat = format;
        NSDate *date = [formatter dateFromString:string];
        if (date) {
            return date;
        }
    }

    NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
    numberFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    NSNumber *timestamp = [numberFormatter numberFromString:string];
    if (timestamp) {
        return [self dateFromServerValue:timestamp];
    }

    return nil;
}


- (NSDictionary *)deviceInfoPayload {
    UIDevice *device = UIDevice.currentDevice;
    NSString *deviceName = [self safeDeviceInfoString:device.name maxLength:120];
    NSString *systemName = [self safeDeviceInfoString:device.systemName maxLength:40];
    NSString *iosVersion = [self safeDeviceInfoString:device.systemVersion maxLength:40];
    NSString *deviceModel = [self safeDeviceInfoString:[self deviceHardwareModel] maxLength:80];
    NSString *udid = [self safeDeviceInfoString:[self deviceUDID] maxLength:128];
    NSString *appVersion = [self safeDeviceInfoString:[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] maxLength:40];

    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[@"device_name"] = deviceName.length ? deviceName : @"غير معروف";
    info[@"device_udid"] = udid.length ? udid : (self.deviceIdentifier ?: @"");
    info[@"ios_version"] = iosVersion.length ? iosVersion : @"غير معروف";
    info[@"system_name"] = systemName.length ? systemName : @"iOS";
    info[@"device_model"] = deviceModel.length ? deviceModel : (device.model ?: @"iPhone");
    if (appVersion.length > 0) {
        info[@"app_version"] = appVersion;
    }
    return info.copy;
}

- (NSString *)safeDeviceInfoString:(id)value maxLength:(NSUInteger)maxLength {
    NSString *string = nil;
    if ([value isKindOfClass:NSString.class]) {
        string = (NSString *)value;
    } else if ([value respondsToSelector:@selector(stringValue)]) {
        string = [value stringValue];
    }

    string = [string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (string.length == 0) {
        return @"";
    }

    NSMutableString *clean = [NSMutableString stringWithCapacity:MIN(string.length, maxLength ?: string.length)];
    NSCharacterSet *controlSet = NSCharacterSet.controlCharacterSet;
    for (NSUInteger i = 0; i < string.length && clean.length < maxLength; i++) {
        unichar c = [string characterAtIndex:i];
        if (![controlSet characterIsMember:c]) {
            [clean appendFormat:@"%C", c];
        }
    }
    return clean.copy;
}

- (NSString *)deviceHardwareModel {
    struct utsname systemInfo;
    if (uname(&systemInfo) == 0) {
        NSString *machine = [NSString stringWithUTF8String:systemInfo.machine];
        if (machine.length > 0) {
            return machine;
        }
    }
    return UIDevice.currentDevice.model ?: @"iPhone";
}

- (NSString *)deviceUDID {
    NSArray<NSString *> *gestaltKeys = @[@"UniqueDeviceID", @"SerialNumber"];
    for (NSString *key in gestaltKeys) {
        NSString *value = [self mobileGestaltStringForKey:key];
        if (value.length >= 8) {
            return value;
        }
    }

    NSString *activeIdentifier = [LSAppIdentifierProvider activeIdentifierForVendorString];
    if (activeIdentifier.length >= 8) {
        return activeIdentifier;
    }

    return self.deviceIdentifier ?: UIDevice.currentDevice.identifierForVendor.UUIDString;
}

- (NSString *)mobileGestaltStringForKey:(NSString *)key {
    if (key.length == 0) {
        return nil;
    }

    typedef CFTypeRef (*MGCopyAnswerFunction)(CFStringRef key);
    static MGCopyAnswerFunction mgCopyAnswer = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *handle = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY);
        if (handle) {
            mgCopyAnswer = (MGCopyAnswerFunction)dlsym(handle, "MGCopyAnswer");
        }
    });

    if (!mgCopyAnswer) {
        return nil;
    }

    CFTypeRef answer = mgCopyAnswer((__bridge CFStringRef)key);
    if (!answer) {
        return nil;
    }

    id object = CFBridgingRelease(answer);
    if ([object isKindOfClass:NSString.class]) {
        return [self safeDeviceInfoString:object maxLength:128];
    }
    if ([object isKindOfClass:NSData.class]) {
        const unsigned char *bytes = ((NSData *)object).bytes;
        NSUInteger length = ((NSData *)object).length;
        NSMutableString *hex = [NSMutableString stringWithCapacity:length * 2];
        for (NSUInteger i = 0; i < length; i++) {
            [hex appendFormat:@"%02x", bytes[i]];
        }
        return hex.copy;
    }
    if ([object respondsToSelector:@selector(stringValue)]) {
        return [self safeDeviceInfoString:[object stringValue] maxLength:128];
    }
    return nil;
}

- (NSString *)activationTokenForCodeHash:(NSString *)codeHash deviceID:(NSString *)deviceID {
    NSString *payload = [NSString stringWithFormat:@"%@|%@|%s", codeHash ?: @"", deviceID ?: @"", kLSActivationLocalSecret];
    return [self sha256HexForString:payload];
}

- (NSString *)sha256HexForString:(NSString *)string {
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH] = {0};
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);

    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return hex.copy;
}

@end
