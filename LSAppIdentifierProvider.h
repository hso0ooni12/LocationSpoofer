#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface LSAppIdentifierProvider : NSObject

+ (NSString *)currentApplicationIdentifier;
+ (nullable NSString *)savedCurrentApplicationIdentifier;
+ (nullable NSString *)storedLegacyApplicationIdentifier;
+ (nullable NSString *)replacementApplicationIdentifier;
+ (BOOL)isReplacementIdentifierEnabled;
+ (NSString *)applicationIdentifierForTestMode;
+ (NSString *)applicationIdentifierForClipboard;
+ (nullable NSString *)activeIdentifierForVendorString;
+ (BOOL)isReplacementIdentifierAppliedInCurrentProcess;
+ (nullable NSString *)normalizedApplicationIdentifier:(NSString *)identifier;
+ (nullable NSString *)hyphenatedUUIDStringFromIdentifier:(NSString *)identifier;
+ (BOOL)saveReplacementApplicationIdentifier:(NSString *)identifier errorMessage:(NSString * _Nullable * _Nullable)errorMessage;
+ (void)clearReplacementApplicationIdentifier;

@end

NS_ASSUME_NONNULL_END
