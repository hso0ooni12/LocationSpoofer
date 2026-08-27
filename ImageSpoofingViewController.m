#import "ImageSpoofingViewController.h"
#import "ImageSpoofingManager.h"
#import "LSFloatingPanel.h"

@interface ImageSpoofingViewController ()
@property (nonatomic, strong) ImageSpoofingManager *manager;
@property (nonatomic, strong) UIImageView *previewImageView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UISwitch *enabledSwitch;
@end

@implementation ImageSpoofingViewController

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
    self.manager = [ImageSpoofingManager sharedManager];
    [self buildInterface];
    [self refresh];
}

- (UIButton *)button:(NSString *)title color:(UIColor *)color action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightBold];
    button.backgroundColor = color;
    button.layer.cornerRadius = 17.0;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [button.heightAnchor constraintEqualToConstant:50.0].active = YES;
    return button;
}

- (void)buildInterface {
    UIView *panel = [self ls_xsgps_installFloatingPanelWithBackgroundColor:UIColor.systemGroupedBackgroundColor];
    [self ls_xsgps_addGrabberToFloatingPanel:panel color:[UIColor colorWithWhite:0.45 alpha:0.35]];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [close setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    close.tintColor = UIColor.tertiaryLabelColor;
    [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:close];

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"الصورة المرجعية";
    title.font = [UIFont systemFontOfSize:25.0 weight:UIFontWeightBlack];
    [panel addSubview:title];

    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.text = @"تُحفظ وتُعرض داخل XsGpS فقط.";
    subtitle.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
    subtitle.textColor = UIColor.secondaryLabelColor;
    [panel addSubview:subtitle];

    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    card.layer.cornerRadius = 22.0;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    card.layer.borderColor = UIColor.separatorColor.CGColor;
    [panel addSubview:card];

    UILabel *enabled = [[UILabel alloc] init];
    enabled.translatesAutoresizingMaskIntoConstraints = NO;
    enabled.text = @"تفعيل الصورة المرجعية";
    enabled.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightBold];
    [card addSubview:enabled];
    self.enabledSwitch = [[UISwitch alloc] init];
    self.enabledSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    self.enabledSwitch.onTintColor = UIColor.systemOrangeColor;
    [self.enabledSwitch addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
    [card addSubview:self.enabledSwitch];
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
    self.statusLabel.textColor = UIColor.secondaryLabelColor;
    [card addSubview:self.statusLabel];

    self.previewImageView = [[UIImageView alloc] init];
    self.previewImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.previewImageView.contentMode = UIViewContentModeScaleAspectFill;
    self.previewImageView.backgroundColor = UIColor.tertiarySystemGroupedBackgroundColor;
    self.previewImageView.layer.cornerRadius = 22.0;
    self.previewImageView.layer.cornerCurve = kCACornerCurveContinuous;
    self.previewImageView.clipsToBounds = YES;
    [panel addSubview:self.previewImageView];

    UIButton *choose = [self button:@"اختيار صورة من الاستديو" color:UIColor.systemBlueColor action:@selector(chooseTapped)];
    UIButton *clear = [self button:@"حذف الصورة" color:UIColor.systemRedColor action:@selector(clearTapped)];
    [panel addSubview:choose]; [panel addSubview:clear];

    UILayoutGuide *safe = panel.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [close.topAnchor constraintEqualToAnchor:safe.topAnchor constant:10.0], [close.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:20.0], [close.widthAnchor constraintEqualToConstant:34.0], [close.heightAnchor constraintEqualToConstant:34.0],
        [title.topAnchor constraintEqualToAnchor:safe.topAnchor constant:14.0], [title.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-22.0], [title.leadingAnchor constraintGreaterThanOrEqualToAnchor:close.trailingAnchor constant:12.0],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4.0], [subtitle.trailingAnchor constraintEqualToAnchor:title.trailingAnchor], [subtitle.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:22.0],
        [card.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:18.0], [card.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:20.0], [card.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-20.0],
        [enabled.topAnchor constraintEqualToAnchor:card.topAnchor constant:16.0], [enabled.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],
        [self.enabledSwitch.centerYAnchor constraintEqualToAnchor:enabled.centerYAnchor], [self.enabledSwitch.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [self.statusLabel.topAnchor constraintEqualToAnchor:enabled.bottomAnchor constant:8.0], [self.statusLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0], [self.statusLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0], [self.statusLabel.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16.0],
        [self.previewImageView.topAnchor constraintEqualToAnchor:card.bottomAnchor constant:16.0], [self.previewImageView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor], [self.previewImageView.trailingAnchor constraintEqualToAnchor:card.trailingAnchor], [self.previewImageView.heightAnchor constraintEqualToConstant:230.0],
        [choose.topAnchor constraintEqualToAnchor:self.previewImageView.bottomAnchor constant:16.0], [choose.leadingAnchor constraintEqualToAnchor:card.leadingAnchor], [choose.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [clear.topAnchor constraintEqualToAnchor:choose.bottomAnchor constant:10.0], [clear.leadingAnchor constraintEqualToAnchor:card.leadingAnchor], [clear.trailingAnchor constraintEqualToAnchor:card.trailingAnchor], [clear.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-18.0]
    ]];
}

- (void)refresh {
    self.previewImageView.image = [self.manager getSelectedImage];
    self.enabledSwitch.on = self.manager.referenceEnabled;
    self.statusLabel.text = self.previewImageView.image ? @"صورة محفوظة وجاهزة للعرض." : @"لا توجد صورة محفوظة.";
}
- (void)toggleChanged:(UISwitch *)sender { self.manager.referenceEnabled = sender.isOn; [self refresh]; }
- (void)chooseTapped { [self.manager openPhotoLibraryFromViewController:self]; }
- (void)clearTapped { [self.manager clearSelectedImage]; [self refresh]; }
- (void)closeTapped { [self dismissViewControllerAnimated:YES completion:nil]; }

@end
