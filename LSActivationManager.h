#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LSActivationManager : NSObject

+ (instancetype)shared;
+ (void)loadEarly;

@property (nonatomic, readonly, getter=isActivated) BOOL activated;
@property (nonatomic, readonly) NSString *deviceIdentifier;
@property (nonatomic, readonly) NSString *subscriptionStatusText;
@property (nonatomic, readonly) NSInteger daysRemaining;
@property (nonatomic, readonly, nullable) NSDate *expirationDate;

- (BOOL)activateWithCode:(NSString *)code errorMessage:(NSString * _Nullable * _Nullable)errorMessage;
- (NSString *)normalizedCodeFromString:(NSString *)string;

@end

NS_ASSUME_NONNULL_END
