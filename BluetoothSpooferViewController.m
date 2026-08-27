#import "BluetoothSpooferViewController.h"
#import "BluetoothSpooferManager.h"
#import "LSFloatingPanel.h"

@interface BluetoothSpooferViewController () <BluetoothSpooferDelegate>
@property (nonatomic, strong) BluetoothSpooferManager *spooferManager;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIView *statusCard;
@property (nonatomic, strong) UILabel *statusTitleLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIView *savedSignalCard;
@property (nonatomic, strong) UILabel *savedSignalTitleLabel;
@property (nonatomic, strong) UILabel *uuidLabel;
@property (nonatomic, strong) UIButton *clearSignalButton;
@property (nonatomic, strong) UIButton *uuidCopyButton;
@property (nonatomic, strong) UIStackView *signalActionsRow;
@property (nonatomic, strong) UIStackView *actionStack;
@property (nonatomic, strong) UIButton *scanButton;
@property (nonatomic, strong) UIButton *spoofButton;
@property (nonatomic, strong) UILabel *hintLabel;
@end

@implementation BluetoothSpooferViewController

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.modalPresentationStyle = UIModalPresentationOverFullScreen;
        self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    }
    return self;
}


- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    self.view.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    self.spooferManager = [[BluetoothSpooferManager alloc] init];
    self.spooferManager.delegate = self;
    [self buildInterface];
    [self refreshInterface];
}

- (UIButton *)primaryButtonWithTitle:(NSString *)title color:(UIColor *)color action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.backgroundColor = color;
    button.titleLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightBold];
    button.layer.cornerRadius = 18.0;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    [button.heightAnchor constraintEqualToConstant:54.0].active = YES;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (UIView *)cardView {
    UIView *view = [[UIView alloc] init];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    view.backgroundColor = UIColor.whiteColor;
    view.layer.cornerRadius = 24.0;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    view.layer.borderColor = [UIColor colorWithWhite:0.88 alpha:1.0].CGColor;
    view.layer.shadowColor = UIColor.blackColor.CGColor;
    view.layer.shadowOpacity = 0.06;
    view.layer.shadowRadius = 16.0;
    view.layer.shadowOffset = CGSizeMake(0.0, 8.0);
    return view;
}

- (void)buildInterface {
    UIView *panel = [self ls_xsgps_installFloatingPanelWithBackgroundColor:[UIColor colorWithWhite:0.95 alpha:1.0]];
    [self ls_xsgps_addGrabberToFloatingPanel:panel color:[UIColor colorWithWhite:0.45 alpha:0.35]];

    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.showsVerticalScrollIndicator = NO;
    [panel addSubview:self.scrollView];

    self.contentView = [[UIView alloc] init];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.contentView];

    self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.closeButton setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    self.closeButton.tintColor = UIColor.tertiaryLabelColor;
    [self.closeButton addTarget:self action:@selector(closeButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.closeButton];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.text = @"البلوتوث";
    self.titleLabel.font = [UIFont systemFontOfSize:32.0 weight:UIFontWeightBlack];
    [self.contentView addSubview:self.titleLabel];

    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.subtitleLabel.text = @"نسخ الإشارة، حفظها، ثم بثها بشكل مرتب وواضح";
    self.subtitleLabel.textColor = UIColor.secondaryLabelColor;
    self.subtitleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
    self.subtitleLabel.numberOfLines = 2;
    [self.contentView addSubview:self.subtitleLabel];

    self.statusCard = [self cardView];
    [self.contentView addSubview:self.statusCard];

    self.statusTitleLabel = [[UILabel alloc] init];
    self.statusTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusTitleLabel.text = @"حالة البلوتوث";
    self.statusTitleLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightBold];
    [self.statusCard addSubview:self.statusTitleLabel];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    self.statusLabel.textColor = UIColor.whiteColor;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.backgroundColor = [UIColor colorWithWhite:0.45 alpha:1.0];
    self.statusLabel.layer.cornerRadius = 18.0;
    self.statusLabel.layer.cornerCurve = kCACornerCurveContinuous;
    self.statusLabel.clipsToBounds = YES;
    self.statusLabel.numberOfLines = 2;
    [self.statusCard addSubview:self.statusLabel];

    self.savedSignalCard = [self cardView];
    [self.contentView addSubview:self.savedSignalCard];

    self.savedSignalTitleLabel = [[UILabel alloc] init];
    self.savedSignalTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.savedSignalTitleLabel.text = @"الإشارة المحفوظة";
    self.savedSignalTitleLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightBold];
    [self.savedSignalCard addSubview:self.savedSignalTitleLabel];

    self.uuidLabel = [[UILabel alloc] init];
    self.uuidLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.uuidLabel.font = [UIFont monospacedSystemFontOfSize:14.0 weight:UIFontWeightMedium];
    self.uuidLabel.textColor = UIColor.secondaryLabelColor;
    self.uuidLabel.numberOfLines = 3;
    [self.savedSignalCard addSubview:self.uuidLabel];

    self.clearSignalButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.clearSignalButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.clearSignalButton setTitle:@"حذف الإشارة المحفوظة" forState:UIControlStateNormal];
    [self.clearSignalButton setTitleColor:UIColor.systemRedColor forState:UIControlStateNormal];
    self.clearSignalButton.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightBold];
    self.clearSignalButton.layer.cornerRadius = 14.0;
    self.clearSignalButton.layer.cornerCurve = kCACornerCurveContinuous;
    self.clearSignalButton.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.clearSignalButton.layer.borderColor = UIColor.systemRedColor.CGColor;
    [self.clearSignalButton.heightAnchor constraintEqualToConstant:44.0].active = YES;
    [self.clearSignalButton addTarget:self action:@selector(clearSignalButtonTapped) forControlEvents:UIControlEventTouchUpInside];

    self.uuidCopyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.uuidCopyButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.uuidCopyButton setTitle:@"نسخ UUID" forState:UIControlStateNormal];
    [self.uuidCopyButton setTitleColor:[UIColor colorWithRed:0.16 green:0.36 blue:0.92 alpha:1.0] forState:UIControlStateNormal];
    self.uuidCopyButton.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightBold];
    self.uuidCopyButton.layer.cornerRadius = 14.0;
    self.uuidCopyButton.layer.cornerCurve = kCACornerCurveContinuous;
    self.uuidCopyButton.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.uuidCopyButton.layer.borderColor = [UIColor colorWithRed:0.16 green:0.36 blue:0.92 alpha:1.0].CGColor;
    [self.uuidCopyButton.heightAnchor constraintEqualToConstant:44.0].active = YES;
    [self.uuidCopyButton addTarget:self action:@selector(handleCopyUUIDTapped) forControlEvents:UIControlEventTouchUpInside];

    self.signalActionsRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.uuidCopyButton, self.clearSignalButton]];
    self.signalActionsRow.translatesAutoresizingMaskIntoConstraints = NO;
    self.signalActionsRow.axis = UILayoutConstraintAxisHorizontal;
    self.signalActionsRow.spacing = 10.0;
    self.signalActionsRow.distribution = UIStackViewDistributionFillEqually;
    [self.savedSignalCard addSubview:self.signalActionsRow];

    self.actionStack = [[UIStackView alloc] init];
    self.actionStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.actionStack.axis = UILayoutConstraintAxisVertical;
    self.actionStack.spacing = 12.0;
    [self.contentView addSubview:self.actionStack];

    self.scanButton = [self primaryButtonWithTitle:@"نسخ وحفظ الإشارة القريبة" color:[UIColor colorWithRed:0.16 green:0.36 blue:0.92 alpha:1.0] action:@selector(scanButtonTapped)];
    self.spoofButton = [self primaryButtonWithTitle:@"تفعيل بث الإشارة المحفوظة" color:[UIColor colorWithRed:0.17 green:0.68 blue:0.39 alpha:1.0] action:@selector(spoofButtonTapped)];
    [self.actionStack addArrangedSubview:self.scanButton];
    [self.actionStack addArrangedSubview:self.spoofButton];

    self.hintLabel = [[UILabel alloc] init];
    self.hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.hintLabel.text = @"1) انسخ الإشارة أولاً\n2) تأكد من حفظ UUID\n3) فعّل البث أو أوقفه وقت ما تريد";
    self.hintLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
    self.hintLabel.textColor = UIColor.secondaryLabelColor;
    self.hintLabel.numberOfLines = 0;
    self.hintLabel.textAlignment = NSTextAlignmentRight;
    [self.contentView addSubview:self.hintLabel];

    UILayoutGuide *safe = panel.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],

        [self.contentView.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor],
        [self.contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor],
        [self.contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor],
        [self.contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor],
        [self.contentView.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor],

        [self.closeButton.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:16.0],
        [self.closeButton.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:24.0],
        [self.closeButton.widthAnchor constraintEqualToConstant:36.0],
        [self.closeButton.heightAnchor constraintEqualToConstant:36.0],

        [self.titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:20.0],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-24.0],
        [self.titleLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.closeButton.trailingAnchor constant:16.0],

        [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:4.0],
        [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],
        [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:24.0],

        [self.statusCard.topAnchor constraintEqualToAnchor:self.subtitleLabel.bottomAnchor constant:18.0],
        [self.statusCard.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20.0],
        [self.statusCard.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20.0],

        [self.statusTitleLabel.topAnchor constraintEqualToAnchor:self.statusCard.topAnchor constant:18.0],
        [self.statusTitleLabel.trailingAnchor constraintEqualToAnchor:self.statusCard.trailingAnchor constant:-18.0],
        [self.statusTitleLabel.leadingAnchor constraintEqualToAnchor:self.statusCard.leadingAnchor constant:18.0],

        [self.statusLabel.topAnchor constraintEqualToAnchor:self.statusTitleLabel.bottomAnchor constant:12.0],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.statusCard.leadingAnchor constant:18.0],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.statusCard.trailingAnchor constant:-18.0],
        [self.statusLabel.heightAnchor constraintEqualToConstant:70.0],
        [self.statusLabel.bottomAnchor constraintEqualToAnchor:self.statusCard.bottomAnchor constant:-18.0],

        [self.savedSignalCard.topAnchor constraintEqualToAnchor:self.statusCard.bottomAnchor constant:14.0],
        [self.savedSignalCard.leadingAnchor constraintEqualToAnchor:self.statusCard.leadingAnchor],
        [self.savedSignalCard.trailingAnchor constraintEqualToAnchor:self.statusCard.trailingAnchor],

        [self.savedSignalTitleLabel.topAnchor constraintEqualToAnchor:self.savedSignalCard.topAnchor constant:18.0],
        [self.savedSignalTitleLabel.trailingAnchor constraintEqualToAnchor:self.savedSignalCard.trailingAnchor constant:-18.0],
        [self.savedSignalTitleLabel.leadingAnchor constraintEqualToAnchor:self.savedSignalCard.leadingAnchor constant:18.0],

        [self.uuidLabel.topAnchor constraintEqualToAnchor:self.savedSignalTitleLabel.bottomAnchor constant:10.0],
        [self.uuidLabel.leadingAnchor constraintEqualToAnchor:self.savedSignalCard.leadingAnchor constant:18.0],
        [self.uuidLabel.trailingAnchor constraintEqualToAnchor:self.savedSignalCard.trailingAnchor constant:-18.0],

        [self.signalActionsRow.topAnchor constraintEqualToAnchor:self.uuidLabel.bottomAnchor constant:12.0],
        [self.signalActionsRow.leadingAnchor constraintEqualToAnchor:self.savedSignalCard.leadingAnchor constant:18.0],
        [self.signalActionsRow.trailingAnchor constraintEqualToAnchor:self.savedSignalCard.trailingAnchor constant:-18.0],
        [self.signalActionsRow.bottomAnchor constraintEqualToAnchor:self.savedSignalCard.bottomAnchor constant:-18.0],

        [self.actionStack.topAnchor constraintEqualToAnchor:self.savedSignalCard.bottomAnchor constant:18.0],
        [self.actionStack.leadingAnchor constraintEqualToAnchor:self.savedSignalCard.leadingAnchor],
        [self.actionStack.trailingAnchor constraintEqualToAnchor:self.savedSignalCard.trailingAnchor],

        [self.hintLabel.topAnchor constraintEqualToAnchor:self.actionStack.bottomAnchor constant:16.0],
        [self.hintLabel.leadingAnchor constraintEqualToAnchor:self.actionStack.leadingAnchor],
        [self.hintLabel.trailingAnchor constraintEqualToAnchor:self.actionStack.trailingAnchor],
        [self.hintLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-28.0]
    ]];
}

- (void)closeButtonTapped {
    if (self.navigationController && self.navigationController.viewControllers.firstObject != self) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)scanButtonTapped {
    if (self.spooferManager.isScanning) {
        [self.spooferManager stopScanning];
        [self didUpdateStatusMessage:@"تم إيقاف البحث عن الإشارات"]; 
    } else {
        [self.spooferManager startScanningAndCopying];
    }
}

- (void)spoofButtonTapped {
    if (self.spooferManager.isSpoofing) {
        [self.spooferManager stopSpoofing];
    } else {
        [self.spooferManager startSpoofing];
    }
}

- (void)clearSignalButtonTapped {
    [self.spooferManager clearSavedSignal];
}

- (void)handleCopyUUIDTapped {
    NSString *uuid = self.spooferManager.savedUUIDString;
    if (uuid.length == 0) {
        return;
    }
    UIPasteboard.generalPasteboard.string = uuid;
    [self didUpdateStatusMessage:@"تم نسخ UUID إلى الحافظة"];
}

- (void)refreshInterface {
    [self didUpdateSavedUUID:self.spooferManager.savedUUIDString];
    [self didUpdateScanningState:self.spooferManager.isScanning];
    [self didUpdateSpoofingState:self.spooferManager.isSpoofing];
    if (self.spooferManager.savedUUIDString.length == 0) {
        [self didUpdateStatusMessage:@"جاهز للاستخدام - انسخ إشارة أولاً ثم فعّل البث عند الحاجة"]; 
    }
}

#pragma mark - BluetoothSpooferDelegate

- (void)didUpdateStatusMessage:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusLabel.text = message;
    });
}

- (void)didUpdateScanningState:(BOOL)isScanning {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.scanButton setTitle:(isScanning ? @"إيقاف البحث الحالي" : @"نسخ وحفظ الإشارة القريبة") forState:UIControlStateNormal];
        self.scanButton.backgroundColor = isScanning ? UIColor.systemOrangeColor : [UIColor colorWithRed:0.16 green:0.36 blue:0.92 alpha:1.0];
        if (isScanning) {
            self.statusLabel.backgroundColor = UIColor.systemOrangeColor;
        } else if (!self.spooferManager.isSpoofing) {
            self.statusLabel.backgroundColor = [UIColor colorWithWhite:0.56 alpha:1.0];
        }
    });
}

- (void)didUpdateSpoofingState:(BOOL)isSpoofing {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.spoofButton setTitle:(isSpoofing ? @"إيقاف بث الإشارة" : @"تفعيل بث الإشارة المحفوظة") forState:UIControlStateNormal];
        self.spoofButton.backgroundColor = isSpoofing ? UIColor.systemRedColor : [UIColor colorWithRed:0.17 green:0.68 blue:0.39 alpha:1.0];
        self.statusLabel.backgroundColor = isSpoofing ? UIColor.systemGreenColor : [UIColor colorWithWhite:0.56 alpha:1.0];
    });
}

- (void)didUpdateSavedUUID:(nullable NSString *)uuidString {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (uuidString.length > 0) {
            self.uuidLabel.text = [NSString stringWithFormat:@"UUID المحفوظ:\n%@", uuidString];
            self.uuidLabel.textColor = [UIColor colorWithRed:0.16 green:0.36 blue:0.92 alpha:1.0];
            self.spoofButton.alpha = 1.0;
            self.spoofButton.userInteractionEnabled = YES;
            self.clearSignalButton.hidden = NO;
            self.uuidCopyButton.hidden = NO;
        } else {
            self.uuidLabel.text = @"لا توجد إشارة محفوظة حالياً";
            self.uuidLabel.textColor = UIColor.secondaryLabelColor;
            self.spoofButton.alpha = 0.55;
            self.spoofButton.userInteractionEnabled = NO;
            self.clearSignalButton.hidden = YES;
            self.uuidCopyButton.hidden = YES;
        }
    });
}

@end
