#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface LSSettingsViewController : UIViewController

- (instancetype)initWithSubscriptionText:(NSString *)subscriptionText
                          spoofingActive:(BOOL)spoofingActive;

@property (nonatomic, copy, nullable) void (^onClearRecents)(void);
@property (nonatomic, copy, nullable) void (^onStopSpoofing)(void);

@end

NS_ASSUME_NONNULL_END
