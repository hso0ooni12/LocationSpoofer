#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface LSActivationViewController : UIViewController
@property (nonatomic, copy, nullable) void (^onActivationAccepted)(void);
@property (nonatomic, copy, nullable) void (^onActivationSuccess)(void);
@property (nonatomic, copy, nullable) void (^onCancel)(void);
- (void)playPresentationAnimationIfNeeded;
@end

NS_ASSUME_NONNULL_END
