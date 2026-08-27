#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UIViewController (LSFloatingPanel)

- (UIView *)ls_xsgps_installFloatingPanelWithBackgroundColor:(UIColor *)backgroundColor;
- (UIView *)ls_xsgps_installFloatingPanelWithBackgroundColor:(UIColor *)backgroundColor
                                          horizontalMargin:(CGFloat)horizontalMargin
                                            verticalMargin:(CGFloat)verticalMargin
                                             cornerRadius:(CGFloat)cornerRadius;
- (UIView *)ls_xsgps_addGrabberToFloatingPanel:(UIView *)panel color:(UIColor *)color;

@end

NS_ASSUME_NONNULL_END
