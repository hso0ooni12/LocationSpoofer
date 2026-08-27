#import "LSSettingsViewController.h"
#import "LSActivationManager.h"
#import "LSAppIdentifierProvider.h"
#import <stdlib.h>
#import "LSFloatingPanel.h"

@interface LSSettingsViewController ()
@property (nonatomic, copy) NSString *subscriptionText;
@property (nonatomic, assign) BOOL spoofingActive;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIStackView *stackView;
@property (nonatomic, strong) UIButton *clearRecentsButton;
@property (nonatomic, strong) UIButton *stopSpoofButton;
@end

@implementation LSSettingsViewController

- (instancetype)initWithSubscriptionText:(NSString *)subscriptionText
                          spoofingActive:(BOOL)spoofingActive {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _subscriptionText = [subscriptionText copy] ?: @"";
        _spoofingActive = spoofingActive;
        self.modalPresentationStyle = UIModalPresentationOverFullScreen;
        self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    self.view.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    [self buildInterface];
}

- (UIView *)cardView {
    UIView *view = [[UIView alloc] init];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    view.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    view.layer.cornerRadius = 24.0;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    view.layer.borderColor = UIColor.separatorColor.CGColor;
    return view;
}

- (UILabel *)labelWithText:(NSString *)text font:(UIFont *)font color:(UIColor *)color {
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = text;
    label.font = font;
    label.textColor = color;
    label.numberOfLines = 1;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.82;
    label.textAlignment = NSTextAlignmentRight;
    return label;
}

- (UIButton *)buttonWithTitle:(NSString *)title color:(UIColor *)color action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightBold];
    button.backgroundColor = color;
    button.layer.cornerRadius = 16.0;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    [button.heightAnchor constraintEqualToConstant:48.0].active = YES;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}


- (UIView *)uuidSettingsCard {
    UIControl *card = [[UIControl alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    card.layer.cornerRadius = 22.0;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    card.layer.borderColor = UIColor.separatorColor.CGColor;
    [card addTarget:self action:@selector(handleUUIDSettingsTapped:) forControlEvents:UIControlEventTouchUpInside];

    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"person.crop.circle.badge.checkmark"]];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.tintColor = UIColor.systemOrangeColor;
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    [card addSubview:iconView];

    UILabel *titleLabel = [self labelWithText:@"UUID" font:[UIFont systemFontOfSize:18.0 weight:UIFontWeightBlack] color:UIColor.labelColor];
    titleLabel.textAlignment = NSTextAlignmentRight;
    [card addSubview:titleLabel];

    NSString *status = [LSAppIdentifierProvider isReplacementIdentifierEnabled] ? @"Token مخصص مفعل" : @"يستخدم الافتراضي";
    UIColor *statusColor = [LSAppIdentifierProvider isReplacementIdentifierEnabled] ? UIColor.systemGreenColor : UIColor.secondaryLabelColor;
    UILabel *statusLabel = [self labelWithText:status font:[UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold] color:statusColor];
    statusLabel.textAlignment = NSTextAlignmentRight;
    [card addSubview:statusLabel];

    UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.left"]];
    chevron.translatesAutoresizingMaskIntoConstraints = NO;
    chevron.tintColor = UIColor.tertiaryLabelColor;
    chevron.contentMode = UIViewContentModeScaleAspectFit;
    [card addSubview:chevron];

    [NSLayoutConstraint activateConstraints:@[
        [card.heightAnchor constraintEqualToConstant:76.0],

        [iconView.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],
        [iconView.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:30.0],
        [iconView.heightAnchor constraintEqualToConstant:30.0],

        [chevron.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [chevron.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [chevron.widthAnchor constraintEqualToConstant:16.0],
        [chevron.heightAnchor constraintEqualToConstant:16.0],

        [titleLabel.trailingAnchor constraintEqualToAnchor:iconView.leadingAnchor constant:-12.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:chevron.trailingAnchor constant:12.0],
        [titleLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:15.0],

        [statusLabel.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
        [statusLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [statusLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:4.0]
    ]];

    return card;
}

- (NSString *)remainingSubscriptionText {
    LSActivationManager *manager = [LSActivationManager shared];
    if (![manager isActivated]) {
        return @"غير مفعل";
    }

    NSInteger days = manager.daysRemaining;
    if (days >= 0) {
        if (days == 0) {
            return @"ينتهي اليوم";
        }
        NSString *dayText = days == 1 ? @"يوم واحد" : [NSString stringWithFormat:@"%ld يوم", (long)days];
        return [NSString stringWithFormat:@"متبقي %@", dayText];
    }
    return @"غير محدد من السيرفر";
}

- (void)addCardWithTitle:(NSString *)title value:(NSString *)value tint:(UIColor *)tint {
    UIView *card = [self cardView];
    UILabel *titleLabel = [self labelWithText:title font:[UIFont systemFontOfSize:17.0 weight:UIFontWeightBold] color:UIColor.labelColor];
    UILabel *valueLabel = [self labelWithText:value font:[UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold] color:tint];
    [card addSubview:titleLabel];
    [card addSubview:valueLabel];
    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:16.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [titleLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],
        [valueLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:8.0],
        [valueLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [valueLabel.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
        [valueLabel.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16.0]
    ]];
    [self.stackView addArrangedSubview:card];
}

- (void)buildInterface {
    UIView *panel = [self ls_xsgps_installFloatingPanelWithBackgroundColor:UIColor.systemGroupedBackgroundColor];
    [self ls_xsgps_addGrabberToFloatingPanel:panel color:[UIColor colorWithWhite:0.45 alpha:0.35]];

    self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.closeButton setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    self.closeButton.tintColor = UIColor.tertiaryLabelColor;
    [self.closeButton addTarget:self action:@selector(handleClose) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:self.closeButton];

    self.titleLabel = [self labelWithText:@"إعدادات XsGpS" font:[UIFont systemFontOfSize:26.0 weight:UIFontWeightBlack] color:UIColor.labelColor];
    [panel addSubview:self.titleLabel];

    self.subtitleLabel = [self labelWithText:@"تحكم سريع في الأداة" font:[UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium] color:UIColor.secondaryLabelColor];
    [panel addSubview:self.subtitleLabel];

    self.stackView = [[UIStackView alloc] init];
    self.stackView.translatesAutoresizingMaskIntoConstraints = NO;
    self.stackView.axis = UILayoutConstraintAxisVertical;
    self.stackView.spacing = 12.0;
    [panel addSubview:self.stackView];

    UIColor *blue = [UIColor colorWithRed:0.16 green:0.36 blue:0.92 alpha:1.0];
    NSString *state = self.subscriptionText.length > 0 ? self.subscriptionText : @"الاشتراك مفعل";
    [self addCardWithTitle:@"حالة الاشتراك" value:state tint:blue];
    [self addCardWithTitle:@"المدة المتبقية" value:[self remainingSubscriptionText] tint:blue];

    [self.stackView addArrangedSubview:[self uuidSettingsCard]];

    self.clearRecentsButton = [self buttonWithTitle:@"مسح المواقع الأخيرة" color:[UIColor colorWithRed:0.94 green:0.62 blue:0.18 alpha:1.0] action:@selector(handleClearRecents)];
    [self.stackView addArrangedSubview:self.clearRecentsButton];

    self.stopSpoofButton = [self buttonWithTitle:@"إيقاف تغيير الموقع الآن" color:UIColor.systemRedColor action:@selector(handleStopSpoofing)];
    self.stopSpoofButton.hidden = !self.spoofingActive;
    [self.stackView addArrangedSubview:self.stopSpoofButton];

    UILayoutGuide *safe = panel.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.closeButton.topAnchor constraintEqualToAnchor:safe.topAnchor constant:10.0],
        [self.closeButton.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:18.0],
        [self.closeButton.widthAnchor constraintEqualToConstant:36.0],
        [self.closeButton.heightAnchor constraintEqualToConstant:36.0],
        [self.titleLabel.topAnchor constraintEqualToAnchor:safe.topAnchor constant:14.0],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-22.0],
        [self.titleLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.closeButton.trailingAnchor constant:12.0],
        [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:4.0],
        [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],
        [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:22.0],
        [self.stackView.topAnchor constraintEqualToAnchor:self.subtitleLabel.bottomAnchor constant:18.0],
        [self.stackView.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:20.0],
        [self.stackView.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-20.0],
        [self.stackView.bottomAnchor constraintLessThanOrEqualToAnchor:safe.bottomAnchor constant:-22.0]
    ]];
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"موافق" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showRestartAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"إعادة التشغيل" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [weakSelf restartApplicationProcess];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"لاحقاً" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}


- (void)handleUUIDSettingsTapped:(UIView *)sender {
    NSString *active = [LSAppIdentifierProvider applicationIdentifierForTestMode];
    NSString *message = [NSString stringWithFormat:@"UUID الحالي داخل الأداة:\n%@", active];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"UUID" message:message preferredStyle:UIAlertControllerStyleActionSheet];

    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"Use Token" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [weakSelf presentUUIDTokenInput];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Use Default" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [weakSelf handleUseDefaultUUID];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    if (popover) {
        popover.sourceView = sender ?: self.view;
        popover.sourceRect = sender ? sender.bounds : CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1.0, 1.0);
        popover.permittedArrowDirections = UIPopoverArrowDirectionAny;
    }

    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)presentUUIDTokenInput {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Use Token" message:@"الصق UUID المخصص ليتم حفظه داخل إعدادات الأداة." preferredStyle:UIAlertControllerStyleAlert];
    NSString *currentReplacement = [LSAppIdentifierProvider replacementApplicationIdentifier];
    NSString *clipboard = [UIPasteboard.generalPasteboard.string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *clipboardUUID = clipboard.length > 0 ? [LSAppIdentifierProvider normalizedApplicationIdentifier:clipboard] : nil;

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"6bb0cdeeb3574c5aa7fd6fb6179c8df0";
        textField.text = currentReplacement ?: (clipboardUUID ?: @"");
        textField.textAlignment = NSTextAlignmentCenter;
        textField.font = [UIFont monospacedSystemFontOfSize:13.0 weight:UIFontWeightMedium];
        textField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];

    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"تطبيق" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *value = alert.textFields.firstObject.text ?: @"";
        NSString *errorMessage = nil;
        BOOL saved = [LSAppIdentifierProvider saveReplacementApplicationIdentifier:value errorMessage:&errorMessage];
        if (!saved) {
            [weakSelf showAlertWithTitle:@"تعذر الحفظ" message:errorMessage ?: @"UUID غير صحيح."];
            return;
        }
        [weakSelf showRestartAlertWithTitle:@"تم حفظ UUID" message:@"تم حفظ Token داخل الأداة. أعد تشغيل التطبيق لتطبيق الإعداد الجديد."];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)handleUseDefaultUUID {
    [LSAppIdentifierProvider clearReplacementApplicationIdentifier];
    [self showRestartAlertWithTitle:@"Use Default" message:@"تم الرجوع إلى UUID الافتراضي داخل الأداة. أعد تشغيل التطبيق لتطبيق التغيير."];
}

- (void)restartApplicationProcess {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        exit(0);
    });
}

- (void)handleClearRecents {
    if (self.onClearRecents) self.onClearRecents();
    [self.clearRecentsButton setTitle:@"تم مسح المواقع الأخيرة" forState:UIControlStateNormal];
    self.clearRecentsButton.backgroundColor = UIColor.systemGreenColor;
}

- (void)handleStopSpoofing {
    if (self.onStopSpoofing) self.onStopSpoofing();
    self.stopSpoofButton.hidden = YES;
}

- (void)handleClose { [self dismissViewControllerAnimated:YES completion:nil]; }

@end
