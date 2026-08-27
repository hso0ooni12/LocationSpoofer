#import "LSActivationViewController.h"
#import "LSActivationManager.h"

static const CGFloat kLSActivationCardMaxWidth = 392.0;
static const CGFloat kLSActivationCardSideInset = 30.0;

@interface LSActivationViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UITextField *codeField;
@property (nonatomic, strong) UIButton *cancelButton;
@property (nonatomic, strong) UIButton *activateButton;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) NSLayoutConstraint *cardCenterYConstraint;
@property (nonatomic, assign) BOOL activationInProgress;
@property (nonatomic, assign) BOOL finishingSuccessfulActivation;
@property (nonatomic, assign) BOOL presentationAnimationPlayed;
@end

@implementation LSActivationViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    self.view.opaque = NO;
    self.view.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    self.view.accessibilityViewIsModal = YES;
    [self buildInterface];
    [self updateActivateButtonState];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleKeyboardWillChangeFrame:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleKeyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self playPresentationAnimationIfNeeded];
}

- (void)playPresentationAnimationIfNeeded {
    if (self.presentationAnimationPlayed || !self.cardView) {
        return;
    }

    self.presentationAnimationPlayed = YES;
    [self.view layoutIfNeeded];

    [UIView animateWithDuration:0.22
                          delay:0.0
                        options:(UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState)
                     animations:^{
        self.cardView.alpha = 1.0;
        self.cardView.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.cardView.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.cardView.bounds
                                                                cornerRadius:self.cardView.layer.cornerRadius].CGPath;
}

- (void)buildInterface {
    self.cardView = [[UIView alloc] init];
    self.cardView.translatesAutoresizingMaskIntoConstraints = NO;
    self.cardView.backgroundColor = [UIColor colorWithWhite:0.115 alpha:0.96];
    self.cardView.layer.cornerRadius = 38.0;
    if (@available(iOS 13.0, *)) {
        self.cardView.layer.cornerCurve = kCACornerCurveContinuous;
    }
    self.cardView.layer.shadowColor = UIColor.blackColor.CGColor;
    self.cardView.layer.shadowOpacity = 0.30;
    self.cardView.layer.shadowRadius = 24.0;
    self.cardView.layer.shadowOffset = CGSizeMake(0.0, 12.0);
    self.cardView.accessibilityIdentifier = @"xsgps_activation_card";
    self.cardView.alpha = 0.0;
    self.cardView.transform = CGAffineTransformMakeScale(0.965, 0.965);
    [self.view addSubview:self.cardView];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.text = @"تفعيل الأداة";
    self.titleLabel.textColor = UIColor.whiteColor;
    self.titleLabel.font = [UIFont systemFontOfSize:29.0 weight:UIFontWeightHeavy];
    self.titleLabel.textAlignment = NSTextAlignmentRight;
    self.titleLabel.numberOfLines = 1;
    self.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.titleLabel.minimumScaleFactor = 0.84;
    [self.cardView addSubview:self.titleLabel];

    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.subtitleLabel.text = @"أدخل كود التفعيل:";
    self.subtitleLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.62];
    self.subtitleLabel.font = [UIFont systemFontOfSize:22.0 weight:UIFontWeightRegular];
    self.subtitleLabel.textAlignment = NSTextAlignmentRight;
    self.subtitleLabel.numberOfLines = 1;
    self.subtitleLabel.adjustsFontSizeToFitWidth = YES;
    self.subtitleLabel.minimumScaleFactor = 0.82;
    [self.cardView addSubview:self.subtitleLabel];

    self.codeField = [[UITextField alloc] init];
    self.codeField.translatesAutoresizingMaskIntoConstraints = NO;
    self.codeField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"مثال: ABC123-4567"
                                                                           attributes:@{ NSForegroundColorAttributeName: [UIColor colorWithWhite:1.0 alpha:0.34] }];
    self.codeField.textAlignment = NSTextAlignmentRight;
    self.codeField.textColor = UIColor.whiteColor;
    self.codeField.tintColor = UIColor.whiteColor;
    self.codeField.font = [UIFont systemFontOfSize:21.0 weight:UIFontWeightMedium];
    self.codeField.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.14];
    self.codeField.layer.cornerRadius = 29.0;
    if (@available(iOS 13.0, *)) {
        self.codeField.layer.cornerCurve = kCACornerCurveContinuous;
    }
    self.codeField.layer.borderWidth = 0.0;
    self.codeField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    self.codeField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.codeField.spellCheckingType = UITextSpellCheckingTypeNo;
    self.codeField.keyboardAppearance = UIKeyboardAppearanceDark;
    self.codeField.keyboardType = UIKeyboardTypeASCIICapable;
    self.codeField.returnKeyType = UIReturnKeyGo;
    self.codeField.enablesReturnKeyAutomatically = YES;
    self.codeField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.codeField.textContentType = UITextContentTypeOneTimeCode;
    self.codeField.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    self.codeField.delegate = self;

    UIView *leftPadding = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 22.0, 1.0)];
    UIView *rightPadding = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 22.0, 1.0)];
    self.codeField.leftView = leftPadding;
    self.codeField.leftViewMode = UITextFieldViewModeAlways;
    self.codeField.rightView = rightPadding;
    self.codeField.rightViewMode = UITextFieldViewModeAlways;

    [self.codeField addTarget:self action:@selector(codeFieldChanged:) forControlEvents:UIControlEventEditingChanged];
    [self.cardView addSubview:self.codeField];

    self.messageLabel = [[UILabel alloc] init];
    self.messageLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.messageLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
    self.messageLabel.textColor = [UIColor colorWithRed:1.0 green:0.40 blue:0.40 alpha:1.0];
    self.messageLabel.textAlignment = NSTextAlignmentRight;
    self.messageLabel.numberOfLines = 0;
    self.messageLabel.hidden = YES;
    [self.cardView addSubview:self.messageLabel];

    self.cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.cancelButton setTitle:@"إلغاء" forState:UIControlStateNormal];
    [self configureActivationButton:self.cancelButton emphasized:NO];
    [self.cancelButton addTarget:self action:@selector(handleCancel) forControlEvents:UIControlEventTouchUpInside];
    [self.cardView addSubview:self.cancelButton];

    self.activateButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.activateButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.activateButton setTitle:@"تفعيل" forState:UIControlStateNormal];
    [self configureActivationButton:self.activateButton emphasized:YES];
    [self.activateButton addTarget:self action:@selector(handleActivate) forControlEvents:UIControlEventTouchUpInside];
    [self.cardView addSubview:self.activateButton];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.hidesWhenStopped = YES;
    self.spinner.color = UIColor.whiteColor;
    [self.activateButton addSubview:self.spinner];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    self.cardCenterYConstraint = [self.cardView.centerYAnchor constraintEqualToAnchor:safe.centerYAnchor constant:-10.0];

    NSLayoutConstraint *preferredWidth = [self.cardView.widthAnchor constraintEqualToAnchor:safe.widthAnchor constant:-(kLSActivationCardSideInset * 2.0)];
    preferredWidth.priority = UILayoutPriorityDefaultHigh;
    NSLayoutConstraint *maxWidth = [self.cardView.widthAnchor constraintLessThanOrEqualToConstant:kLSActivationCardMaxWidth];
    maxWidth.priority = UILayoutPriorityRequired;

    [NSLayoutConstraint activateConstraints:@[
        [self.cardView.leadingAnchor constraintGreaterThanOrEqualToAnchor:safe.leadingAnchor constant:kLSActivationCardSideInset],
        [self.cardView.trailingAnchor constraintLessThanOrEqualToAnchor:safe.trailingAnchor constant:-kLSActivationCardSideInset],
        [self.cardView.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        self.cardCenterYConstraint,
        preferredWidth,
        maxWidth,

        [self.titleLabel.topAnchor constraintEqualToAnchor:self.cardView.topAnchor constant:28.0],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:34.0],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-34.0],

        [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:14.0],
        [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:34.0],
        [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-34.0],

        [self.codeField.topAnchor constraintEqualToAnchor:self.subtitleLabel.bottomAnchor constant:20.0],
        [self.codeField.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:34.0],
        [self.codeField.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-34.0],
        [self.codeField.heightAnchor constraintEqualToConstant:58.0],

        [self.messageLabel.topAnchor constraintEqualToAnchor:self.codeField.bottomAnchor constant:8.0],
        [self.messageLabel.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:34.0],
        [self.messageLabel.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-34.0],

        [self.cancelButton.topAnchor constraintEqualToAnchor:self.messageLabel.bottomAnchor constant:16.0],
        [self.cancelButton.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:34.0],
        [self.cancelButton.heightAnchor constraintEqualToConstant:56.0],
        [self.cancelButton.widthAnchor constraintEqualToAnchor:self.activateButton.widthAnchor],

        [self.activateButton.topAnchor constraintEqualToAnchor:self.cancelButton.topAnchor],
        [self.activateButton.leadingAnchor constraintEqualToAnchor:self.cancelButton.trailingAnchor constant:14.0],
        [self.activateButton.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-34.0],
        [self.activateButton.heightAnchor constraintEqualToAnchor:self.cancelButton.heightAnchor],
        [self.activateButton.bottomAnchor constraintEqualToAnchor:self.cardView.bottomAnchor constant:-28.0],

        [self.spinner.centerYAnchor constraintEqualToAnchor:self.activateButton.centerYAnchor],
        [self.spinner.trailingAnchor constraintEqualToAnchor:self.activateButton.trailingAnchor constant:-20.0]
    ]];
}

- (void)configureActivationButton:(UIButton *)button emphasized:(BOOL)emphasized {
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [button setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.45] forState:UIControlStateDisabled];
    button.titleLabel.font = [UIFont systemFontOfSize:22.0 weight:UIFontWeightBold];
    button.backgroundColor = emphasized ? [UIColor colorWithWhite:1.0 alpha:0.18] : [UIColor colorWithWhite:1.0 alpha:0.15];
    button.layer.cornerRadius = 28.0;
    if (@available(iOS 13.0, *)) {
        button.layer.cornerCurve = kCACornerCurveContinuous;
    }
}

- (void)codeFieldChanged:(UITextField *)textField {
    NSString *normalized = [[LSActivationManager shared] normalizedCodeFromString:textField.text ?: @""];
    if (![textField.text isEqualToString:normalized]) {
        textField.text = normalized;
    }
    self.messageLabel.text = @"";
    self.messageLabel.hidden = YES;
    [self updateActivateButtonState];
}

- (void)updateActivateButtonState {
    if (self.activationInProgress || self.finishingSuccessfulActivation) {
        self.activateButton.enabled = NO;
        self.cancelButton.enabled = NO;
        self.activateButton.alpha = 0.72;
        self.cancelButton.alpha = 0.72;
        return;
    }

    self.activateButton.enabled = YES;
    self.cancelButton.enabled = YES;
    self.activateButton.alpha = 1.0;
    self.cancelButton.alpha = 1.0;
}

- (void)handleActivate {
    if (self.activationInProgress) {
        return;
    }

    NSString *code = [[LSActivationManager shared] normalizedCodeFromString:self.codeField.text ?: @""];
    self.codeField.text = code;
    if (code.length == 0) {
        [self showErrorMessage:@"أدخل كود التفعيل أولاً"];
        [self.codeField becomeFirstResponder];
        [self shakeCard];
        return;
    }

    [self.view endEditing:YES];
    [self showErrorMessage:nil];
    self.activationInProgress = YES;
    [self updateActivateButtonState];
    [self.spinner startAnimating];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *error = nil;
        BOOL success = [[LSActivationManager shared] activateWithCode:code errorMessage:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) {
                [self finishSuccessfulActivationTransition];
                return;
            }

            self.activationInProgress = NO;
            [self.spinner stopAnimating];
            [self updateActivateButtonState];
            [self showErrorMessage:error ?: @"تعذر التفعيل"];
            [self.codeField becomeFirstResponder];
            [self shakeCard];
        });
    });
}

- (void)finishSuccessfulActivationTransition {
    if (self.finishingSuccessfulActivation) {
        return;
    }

    self.activationInProgress = NO;
    self.finishingSuccessfulActivation = YES;
    [self.view endEditing:YES];
    [self.spinner stopAnimating];
    [self showErrorMessage:nil];
    [self updateActivateButtonState];

    void (^acceptedBlock)(void) = [self.onActivationAccepted copy];
    void (^successBlock)(void) = [self.onActivationSuccess copy];

    // اكشف اللوحة الرئيسية فور تأكيد نجاح الكود، قبل انتظار أنيميشن اختفاء الكرت.
    // هذا يمنع بقاء واجهة التفعيل فوق شاشة فارغة ويجعل الانتقال مباشرًا.
    if (acceptedBlock) {
        acceptedBlock();
    }

    [UIView animateWithDuration:0.14
                          delay:0.0
                        options:(UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState)
                     animations:^{
        self.cardView.alpha = 0.0;
        self.cardView.transform = CGAffineTransformConcat(CGAffineTransformMakeTranslation(0.0, -6.0),
                                                          CGAffineTransformMakeScale(0.98, 0.98));
    } completion:^(__unused BOOL finished) {
        // v69: LSActivationViewController is normally embedded as a child overlay
        // inside MapPickerViewController.  In that mode, presentingViewController
        // can still be inherited from the parent modal hierarchy; calling dismiss
        // here dismisses the whole XsGpS panel right after it appears.
        // Only call UIKit dismissal when this controller itself is the presented VC.
        BOOL isEmbeddedChild = (self.parentViewController != nil);
        BOOL isDirectlyPresented = (self.presentingViewController.presentedViewController == self);
        if (!isEmbeddedChild && isDirectlyPresented) {
            [self dismissViewControllerAnimated:NO completion:successBlock];
        } else if (successBlock) {
            successBlock();
        }
    }];
}

- (void)handleCancel {
    if (self.activationInProgress) {
        return;
    }

    [self.view endEditing:YES];
    void (^cancelBlock)(void) = self.onCancel;
    BOOL isEmbeddedChild = (self.parentViewController != nil);
    BOOL isDirectlyPresented = (self.presentingViewController.presentedViewController == self);
    if (!isEmbeddedChild && isDirectlyPresented) {
        [self dismissViewControllerAnimated:YES completion:cancelBlock];
    } else if (cancelBlock) {
        cancelBlock();
    }
}

- (void)showErrorMessage:(NSString *)message {
    BOOL hasMessage = message.length > 0;
    self.messageLabel.text = hasMessage ? message : @"";
    self.messageLabel.hidden = !hasMessage;
}

- (void)shakeCard {
    CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    animation.duration = 0.32;
    animation.values = @[ @0, @-10, @10, @-7, @7, @0 ];
    [self.cardView.layer addAnimation:animation forKey:@"ls_activation_shake"];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    (void)textField;
    [self handleActivate];
    return YES;
}

- (void)handleKeyboardWillChangeFrame:(NSNotification *)notification {
    CGRect keyboardEndFrame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect convertedFrame = [self.view convertRect:keyboardEndFrame fromView:nil];
    CGFloat overlap = CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(convertedFrame);
    CGFloat offset = overlap > 0.0 ? -MIN(110.0, overlap * 0.32) : -10.0;
    [self animateKeyboardOffset:offset notification:notification];
}

- (void)handleKeyboardWillHide:(NSNotification *)notification {
    [self animateKeyboardOffset:-10.0 notification:notification];
}

- (void)animateKeyboardOffset:(CGFloat)offset notification:(NSNotification *)notification {
    self.cardCenterYConstraint.constant = offset;

    NSTimeInterval duration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    if (duration <= 0.0) {
        duration = 0.25;
    }

    UIViewAnimationOptions options = UIViewAnimationOptionCurveEaseInOut;
    NSNumber *curveNumber = notification.userInfo[UIKeyboardAnimationCurveUserInfoKey];
    if (curveNumber) {
        options = (UIViewAnimationOptions)(curveNumber.integerValue << 16);
    }

    [UIView animateWithDuration:duration delay:0.0 options:options animations:^{
        [self.view layoutIfNeeded];
    } completion:nil];
}

@end
