#import "LSUUIDResetManager.h"
#import "LSAppIdentifierProvider.h"
#import <Security/Security.h>
#import <WebKit/WebKit.h>
#include <stdlib.h>

@implementation LSUUIDResetManager

+ (BOOL)shouldPreserveToolFileAtPath:(NSString *)path {
    NSString *name = path.lastPathComponent.lowercaseString ?: @"";
    if ([name hasPrefix:@"com.xsgps."]) {
        return YES;
    }
    if ([name containsString:@"xsgps"]) {
        return YES;
    }
    return NO;
}

+ (void)removeContentsAtPath:(NSString *)path preserveToolFiles:(BOOL)preserveToolFiles {
    if (path.length == 0) {
        return;
    }

    NSFileManager *fileManager = NSFileManager.defaultManager;
    BOOL isDirectory = NO;
    if (![fileManager fileExistsAtPath:path isDirectory:&isDirectory] || !isDirectory) {
        return;
    }

    NSArray<NSString *> *children = [fileManager contentsOfDirectoryAtPath:path error:nil] ?: @[];
    for (NSString *child in children) {
        @autoreleasepool {
            NSString *childPath = [path stringByAppendingPathComponent:child];
            if (preserveToolFiles && [self shouldPreserveToolFileAtPath:childPath]) {
                continue;
            }
            [fileManager removeItemAtPath:childPath error:nil];
        }
    }
}

+ (void)deleteHostKeychainItems {
    NSArray *classes = @[
        (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecClassInternetPassword,
        (__bridge id)kSecClassCertificate,
        (__bridge id)kSecClassKey,
        (__bridge id)kSecClassIdentity
    ];

    for (id secClass in classes) {
        NSMutableDictionary *query = [@{(__bridge id)kSecClass: secClass} mutableCopy];
        SecItemDelete((__bridge CFDictionaryRef)query);

        query[(__bridge id)kSecAttrSynchronizable] = (__bridge id)kSecAttrSynchronizableAny;
        SecItemDelete((__bridge CFDictionaryRef)query);
    }
}

+ (void)clearURLAndWebStorage {
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
    NSArray<NSHTTPCookie *> *cookies = [NSHTTPCookieStorage.sharedHTTPCookieStorage.cookies copy] ?: @[];
    for (NSHTTPCookie *cookie in cookies) {
        [NSHTTPCookieStorage.sharedHTTPCookieStorage deleteCookie:cookie];
    }

    if (@available(iOS 9.0, *)) {
        NSSet *types = [NSSet setWithArray:@[
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeCookies,
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeSessionStorage,
            WKWebsiteDataTypeIndexedDBDatabases,
            WKWebsiteDataTypeWebSQLDatabases
        ]];
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        [[WKWebsiteDataStore defaultDataStore] removeDataOfTypes:types modifiedSince:[NSDate distantPast] completionHandler:^{
            dispatch_semaphore_signal(semaphore);
        }];
        dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)));
    }
}

+ (void)clearHostApplicationDataPreservingToolState {
    // نحفظ UUID البديل في مخزن الأداة الثابت قبل تنظيف بيانات التطبيق حتى لا يضيع.
    NSString *replacementUUID = [LSAppIdentifierProvider replacementApplicationIdentifier];
    if (replacementUUID.length > 0) {
        NSString *errorMessage = nil;
        [LSAppIdentifierProvider saveReplacementApplicationIdentifier:replacementUUID errorMessage:&errorMessage];
    }

    NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier;
    if (bundleIdentifier.length > 0) {
        [NSUserDefaults.standardUserDefaults removePersistentDomainForName:bundleIdentifier];
        [NSUserDefaults.standardUserDefaults synchronize];
    }

    [self clearURLAndWebStorage];

    NSArray<NSString *> *documentsDirectories = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    for (NSString *directory in documentsDirectories) {
        [self removeContentsAtPath:directory preserveToolFiles:NO];
    }

    NSArray<NSString *> *libraryDirectories = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    for (NSString *libraryDirectory in libraryDirectories) {
        NSArray<NSString *> *libraryChildren = [NSFileManager.defaultManager contentsOfDirectoryAtPath:libraryDirectory error:nil] ?: @[];
        for (NSString *child in libraryChildren) {
            NSString *childPath = [libraryDirectory stringByAppendingPathComponent:child];
            if ([child isEqualToString:@"Preferences"]) {
                [self removeContentsAtPath:childPath preserveToolFiles:YES];
            } else {
                [NSFileManager.defaultManager removeItemAtPath:childPath error:nil];
            }
        }
    }

    [self removeContentsAtPath:NSTemporaryDirectory() preserveToolFiles:NO];
    [self deleteHostKeychainItems];

    // إعادة كتابة UUID بعد التنظيف حتى يقرأه الهوك عند الفتح التالي.
    if (replacementUUID.length > 0) {
        NSString *errorMessage = nil;
        [LSAppIdentifierProvider saveReplacementApplicationIdentifier:replacementUUID errorMessage:&errorMessage];
    }
}

+ (void)restartAfterApplyingUUID {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self clearHostApplicationDataPreservingToolState];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            exit(0);
        });
    });
}

@end
