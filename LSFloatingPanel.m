#import "LSFloatingPanel.h"

@implementation UIViewController (LSFloatingPanel)

- (UIView *)ls_xsgps_installFloatingPanelWithBackgroundColor:(UIColor *)backgroundColor {
    return [self ls_xsgps_installFloatingPanelWithBackgroundColor:backgroundColor
                                                 horizontalMargin:14.0
                                                   verticalMargin:10.0
                                                    cornerRadius:30.0];
}

- (UIView *)ls_xsgps_installFloatingPanelWithBackgroundColor:(UIColor *)backgroundColor
                                          horizontalMargin:(CGFloat)horizontalMargin
                                            verticalMargin:(CGFloat)verticalMargin
                                             cornerRadius:(CGFloat)cornerRadius {
    self.view.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.42];
    self.view.opaque = NO;
    self.view.clipsToBounds = NO;

    UIView *panel = [[UIView alloc] init];
    panel.translatesAutoresizingMaskIntoConstraints = NO;
    panel.backgroundColor = backgroundColor ?: UIColor.systemBackgroundColor;
    panel.layer.cornerRadius = cornerRadius;
    panel.layer.cornerCurve = kCACornerCurveContinuous;
    panel.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    panel.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.16].CGColor;
    panel.layer.shadowColor = UIColor.blackColor.CGColor;
    panel.layer.shadowOpacity = 0.38;
    panel.layer.shadowRadius = 28.0;
    panel.layer.shadowOffset = CGSizeMake(0.0, 14.0);
    panel.clipsToBounds = NO;
    [self.view addSubview:panel];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [panel.topAnchor constraintEqualToAnchor:safe.topAnchor constant:verticalMargin],
        [panel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:horizontalMargin],
        [panel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-horizontalMargin],
        [panel.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-verticalMargin]
    ]];

    return panel;
}

- (UIView *)ls_xsgps_addGrabberToFloatingPanel:(UIView *)panel color:(UIColor *)color {
    UIView *grabber = [[UIView alloc] init];
    grabber.translatesAutoresizingMaskIntoConstraints = NO;
    grabber.backgroundColor = color ?: [UIColor colorWithWhite:1.0 alpha:0.34];
    grabber.layer.cornerRadius = 2.5;
    grabber.layer.cornerCurve = kCACornerCurveContinuous;
    [panel addSubview:grabber];

    [NSLayoutConstraint activateConstraints:@[
        [grabber.topAnchor constraintEqualToAnchor:panel.topAnchor constant:8.0],
        [grabber.centerXAnchor constraintEqualToAnchor:panel.centerXAnchor],
        [grabber.widthAnchor constraintEqualToConstant:58.0],
        [grabber.heightAnchor constraintEqualToConstant:5.0]
    ]];

    return grabber;
}

@end
