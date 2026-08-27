#import "UUIDManagerViewController.h"
#import "LSAppIdentifierProvider.h"
#import "LSUUIDResetManager.h"
#import <stdlib.h>

static NSString * const kLSOldAppUUIDKey = @"LSOldAppUUIDForTransfer";
static NSString * const kLSSavedCurrentAppUUIDKey = @"LSSavedCurrentAppUUID";
static NSString * const kLSLegacyOldDeviceUUIDKey = @"LSOldDeviceUUIDForTransfer";
static NSString * const kLSLegacySavedCurrentDeviceUUIDKey = @"LSSavedCurrentDeviceUUID";
static NSString * const kLSTestApplicationUUIDEnabledKey = @"LSTestApplicationUUIDEnabled";

@interface UUIDManagerViewController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UILabel *activeUUIDLabel;
@property (nonatomic, strong) UILabel *realUUIDLabel;
@property (nonatomic, strong) UILabel *savedUUIDLabel;
@property (nonatomic, strong) UITextField *replacementUUIDTextField;
@property (nonatomic, strong) UILabel *hintLabel;
@end

@implementation UUIDManagerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.view.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    self.title = @"معرّف التطبيق";
    [self migrateLegacyKeysIfNeeded];
    [self buildInterface];
}

- (void)migrateLegacyKeysIfNeeded {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (![defaults stringForKey:kLSOldAppUUIDKey]) {
        NSString *legacyOld = [defaults stringForKey:kLSLegacyOldDeviceUUIDKey];
        if (legacyOld.length > 0) {
            [defaults setObject:legacyOld forKey:kLSOldAppUUIDKey];
            [defaults setBool:YES forKey:kLSTestApplicationUUIDEnabledKey];
        }
    }
    if (![defaults stringForKey:kLSSavedCurrentAppUUIDKey]) {
        NSString *legacyCurrent = [defaults stringForKey:kLSLegacySavedCurrentDeviceUUIDKey];
        if (legacyCurrent.length > 0) {
            [defaults setObject:legacyCurrent forKey:kLSSavedCurrentAppUUIDKey];
        }
    }
    [defaults synchronize];
}

- (NSString *)savedCurrentIdentifierString {
    NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:kLSSavedCurrentAppUUIDKey];
    return saved.length > 0 ? saved : @"لم يتم الحفظ بعد";
}

- (UIView *)cardView {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    card.layer.cornerRadius = 22.0;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    card.layer.borderColor = UIColor.separatorColor.CGColor;
    return card;
}

- (UILabel *)labelWithText:(NSString *)text font:(UIFont *)font color:(UIColor *)color {
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = text;
    label.font = font;
    label.textColor = color;
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentRight;
    return label;
}

- (UIButton *)buttonWithTitle:(NSString *)title systemImage:(NSString *)systemImage color:(UIColor *)color action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    UIImage *image = [UIImage systemImageNamed:systemImage];
    [button setImage:image forState:UIControlStateNormal];
    button.tintColor = UIColor.whiteColor;
    button.backgroundColor = color;
    button.titleLabel.font = [UIFont systemFontOfSize:16.5 weight:UIFontWeightBold];
    button.layer.cornerRadius = 17.0;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    button.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    button.imageEdgeInsets = UIEdgeInsetsMake(0, 8, 0, -8);
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [button.heightAnchor constraintEqualToConstant:52.0].active = YES;
    return button;
}

- (UILabel *)uuidBoxWithText:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = text;
    label.font = [UIFont monospacedSystemFontOfSize:14.0 weight:UIFontWeightSemibold];
    label.textColor = UIColor.labelColor;
    label.numberOfLines = 3;
    label.textAlignment = NSTextAlignmentCenter;
    label.backgroundColor = UIColor.tertiarySystemGroupedBackgroundColor;
    label.layer.cornerRadius = 14.0;
    label.layer.cornerCurve = kCACornerCurveContinuous;
    label.clipsToBounds = YES;
    return label;
}

- (void)buildInterface {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:self.scrollView];

    self.contentView = [[UIView alloc] init];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.contentView];

    UILabel *titleLabel = [self labelWithText:@"إدارة معرّف التطبيق" font:[UIFont systemFontOfSize:26.0 weight:UIFontWeightBlack] color:UIColor.labelColor];
    [self.contentView addSubview:titleLabel];

    UILabel *subtitleLabel = [self labelWithText:@"استخرج المعرّف الحالي، أو الصق معرّف جديد ليتم حفظه كمعرّف التطبيق المستخدم داخل الأداة وتطبيقه بعد إعادة التشغيل." font:[UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium] color:UIColor.secondaryLabelColor];
    [self.contentView addSubview:subtitleLabel];

    UIView *activeCard = [self cardView];
    [self.contentView addSubview:activeCard];

    UILabel *activeTitle = [self labelWithText:@"المعرّف الحالي المستخدم داخل الأداة" font:[UIFont systemFontOfSize:17.0 weight:UIFontWeightBold] color:UIColor.labelColor];
    [activeCard addSubview:activeTitle];

    self.activeUUIDLabel = [self uuidBoxWithText:[LSAppIdentifierProvider applicationIdentifierForTestMode]];
    [activeCard addSubview:self.activeUUIDLabel];

    UIButton *copyActiveButton = [self buttonWithTitle:@"نسخ المعرّف المستخدم حالياً" systemImage:@"doc.on.doc.fill" color:UIColor.systemBlueColor action:@selector(copyActiveUUID)];
    [activeCard addSubview:copyActiveButton];

    UIView *realCard = [self cardView];
    [self.contentView addSubview:realCard];

    UILabel *realTitle = [self labelWithText:@"UUID التطبيق الأصلي" font:[UIFont systemFontOfSize:17.0 weight:UIFontWeightBold] color:UIColor.labelColor];
    [realCard addSubview:realTitle];

    self.realUUIDLabel = [self uuidBoxWithText:[LSAppIdentifierProvider currentApplicationIdentifier]];
    [realCard addSubview:self.realUUIDLabel];

    UIButton *copyRealButton = [self buttonWithTitle:@"نسخ المعرّف الأصلي" systemImage:@"doc.on.doc" color:UIColor.systemIndigoColor action:@selector(copyRealUUID)];
    [realCard addSubview:copyRealButton];

    UIButton *saveCurrentButton = [self buttonWithTitle:@"حفظ المعرّف الأصلي داخل الأداة" systemImage:@"tray.and.arrow.down.fill" color:UIColor.systemTealColor action:@selector(saveCurrentUUID)];
    [realCard addSubview:saveCurrentButton];

    UIView *savedCard = [self cardView];
    [self.contentView addSubview:savedCard];

    UILabel *savedTitle = [self labelWithText:@"المعرّف الأصلي المحفوظ" font:[UIFont systemFontOfSize:17.0 weight:UIFontWeightBold] color:UIColor.labelColor];
    [savedCard addSubview:savedTitle];

    self.savedUUIDLabel = [self uuidBoxWithText:[self savedCurrentIdentifierString]];
    [savedCard addSubview:self.savedUUIDLabel];

    UIView *replaceCard = [self cardView];
    [self.contentView addSubview:replaceCard];

    UILabel *replaceTitle = [self labelWithText:@"استبدال معرّف التطبيق داخل الأداة" font:[UIFont systemFontOfSize:17.0 weight:UIFontWeightBold] color:UIColor.labelColor];
    [replaceCard addSubview:replaceTitle];

    UILabel *replaceSubtitle = [self labelWithText:@"الصق المعرّف الجديد هنا، ثم اضغط استبدال. سيتم حفظه وإعادة تشغيل التطبيق لتطبيق التغيير." font:[UIFont systemFontOfSize:13.5 weight:UIFontWeightMedium] color:UIColor.secondaryLabelColor];
    [replaceCard addSubview:replaceSubtitle];

    self.replacementUUIDTextField = [[UITextField alloc] init];
    self.replacementUUIDTextField.translatesAutoresizingMaskIntoConstraints = NO;
    self.replacementUUIDTextField.placeholder = @"6bb0cdeeb3574c5aa7fd6fb6179c8df0";
    self.replacementUUIDTextField.text = [LSAppIdentifierProvider replacementApplicationIdentifier] ?: @"";
    self.replacementUUIDTextField.font = [UIFont monospacedSystemFontOfSize:14.0 weight:UIFontWeightRegular];
    self.replacementUUIDTextField.textAlignment = NSTextAlignmentCenter;
    self.replacementUUIDTextField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    self.replacementUUIDTextField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.replacementUUIDTextField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.replacementUUIDTextField.borderStyle = UITextBorderStyleRoundedRect;
    self.replacementUUIDTextField.delegate = self;
    [replaceCard addSubview:self.replacementUUIDTextField];

    UIButton *replaceButton = [self buttonWithTitle:@"استبدال المعرّف وإعادة التشغيل" systemImage:@"arrow.triangle.2.circlepath.circle.fill" color:UIColor.systemBlueColor action:@selector(replaceUUIDAndRestart)];
    [replaceCard addSubview:replaceButton];

    UIButton *clearButton = [self buttonWithTitle:@"مسح المعرّف البديل" systemImage:@"trash.fill" color:UIColor.systemRedColor action:@selector(clearReplacementUUID)];
    [replaceCard addSubview:clearButton];

    self.hintLabel = [self labelWithText:@"ملاحظة: الاستبدال هنا يُحفظ داخل الأداة/تطبيقك التجريبي عبر LSAppIdentifierProvider، وبعد إعادة التشغيل تقرأ الأداة المعرّف الجديد كمعرّف مستخدم داخلها." font:[UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium] color:UIColor.secondaryLabelColor];
    [self.contentView addSubview:self.hintLabel];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [self.contentView.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor],
        [self.contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor],
        [self.contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor],
        [self.contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor],
        [self.contentView.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor],

        [titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:24.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:22.0],
        [titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-22.0],

        [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:8.0],
        [subtitleLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [subtitleLabel.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],

        [activeCard.topAnchor constraintEqualToAnchor:subtitleLabel.bottomAnchor constant:18.0],
        [activeCard.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
        [activeCard.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],

        [activeTitle.topAnchor constraintEqualToAnchor:activeCard.topAnchor constant:18.0],
        [activeTitle.leadingAnchor constraintEqualToAnchor:activeCard.leadingAnchor constant:18.0],
        [activeTitle.trailingAnchor constraintEqualToAnchor:activeCard.trailingAnchor constant:-18.0],

        [self.activeUUIDLabel.topAnchor constraintEqualToAnchor:activeTitle.bottomAnchor constant:12.0],
        [self.activeUUIDLabel.leadingAnchor constraintEqualToAnchor:activeCard.leadingAnchor constant:18.0],
        [self.activeUUIDLabel.trailingAnchor constraintEqualToAnchor:activeCard.trailingAnchor constant:-18.0],
        [self.activeUUIDLabel.heightAnchor constraintGreaterThanOrEqualToConstant:58.0],

        [copyActiveButton.topAnchor constraintEqualToAnchor:self.activeUUIDLabel.bottomAnchor constant:14.0],
        [copyActiveButton.leadingAnchor constraintEqualToAnchor:self.activeUUIDLabel.leadingAnchor],
        [copyActiveButton.trailingAnchor constraintEqualToAnchor:self.activeUUIDLabel.trailingAnchor],
        [copyActiveButton.bottomAnchor constraintEqualToAnchor:activeCard.bottomAnchor constant:-18.0],

        [realCard.topAnchor constraintEqualToAnchor:activeCard.bottomAnchor constant:14.0],
        [realCard.leadingAnchor constraintEqualToAnchor:activeCard.leadingAnchor],
        [realCard.trailingAnchor constraintEqualToAnchor:activeCard.trailingAnchor],

        [realTitle.topAnchor constraintEqualToAnchor:realCard.topAnchor constant:18.0],
        [realTitle.leadingAnchor constraintEqualToAnchor:realCard.leadingAnchor constant:18.0],
        [realTitle.trailingAnchor constraintEqualToAnchor:realCard.trailingAnchor constant:-18.0],

        [self.realUUIDLabel.topAnchor constraintEqualToAnchor:realTitle.bottomAnchor constant:12.0],
        [self.realUUIDLabel.leadingAnchor constraintEqualToAnchor:realCard.leadingAnchor constant:18.0],
        [self.realUUIDLabel.trailingAnchor constraintEqualToAnchor:realCard.trailingAnchor constant:-18.0],
        [self.realUUIDLabel.heightAnchor constraintGreaterThanOrEqualToConstant:58.0],

        [copyRealButton.topAnchor constraintEqualToAnchor:self.realUUIDLabel.bottomAnchor constant:14.0],
        [copyRealButton.leadingAnchor constraintEqualToAnchor:self.realUUIDLabel.leadingAnchor],
        [copyRealButton.trailingAnchor constraintEqualToAnchor:self.realUUIDLabel.trailingAnchor],

        [saveCurrentButton.topAnchor constraintEqualToAnchor:copyRealButton.bottomAnchor constant:10.0],
        [saveCurrentButton.leadingAnchor constraintEqualToAnchor:copyRealButton.leadingAnchor],
        [saveCurrentButton.trailingAnchor constraintEqualToAnchor:copyRealButton.trailingAnchor],
        [saveCurrentButton.bottomAnchor constraintEqualToAnchor:realCard.bottomAnchor constant:-18.0],

        [savedCard.topAnchor constraintEqualToAnchor:realCard.bottomAnchor constant:14.0],
        [savedCard.leadingAnchor constraintEqualToAnchor:activeCard.leadingAnchor],
        [savedCard.trailingAnchor constraintEqualToAnchor:activeCard.trailingAnchor],

        [savedTitle.topAnchor constraintEqualToAnchor:savedCard.topAnchor constant:18.0],
        [savedTitle.leadingAnchor constraintEqualToAnchor:savedCard.leadingAnchor constant:18.0],
        [savedTitle.trailingAnchor constraintEqualToAnchor:savedCard.trailingAnchor constant:-18.0],

        [self.savedUUIDLabel.topAnchor constraintEqualToAnchor:savedTitle.bottomAnchor constant:12.0],
        [self.savedUUIDLabel.leadingAnchor constraintEqualToAnchor:savedCard.leadingAnchor constant:18.0],
        [self.savedUUIDLabel.trailingAnchor constraintEqualToAnchor:savedCard.trailingAnchor constant:-18.0],
        [self.savedUUIDLabel.heightAnchor constraintGreaterThanOrEqualToConstant:54.0],
        [self.savedUUIDLabel.bottomAnchor constraintEqualToAnchor:savedCard.bottomAnchor constant:-18.0],

        [replaceCard.topAnchor constraintEqualToAnchor:savedCard.bottomAnchor constant:14.0],
        [replaceCard.leadingAnchor constraintEqualToAnchor:activeCard.leadingAnchor],
        [replaceCard.trailingAnchor constraintEqualToAnchor:activeCard.trailingAnchor],

        [replaceTitle.topAnchor constraintEqualToAnchor:replaceCard.topAnchor constant:18.0],
        [replaceTitle.leadingAnchor constraintEqualToAnchor:replaceCard.leadingAnchor constant:18.0],
        [replaceTitle.trailingAnchor constraintEqualToAnchor:replaceCard.trailingAnchor constant:-18.0],

        [replaceSubtitle.topAnchor constraintEqualToAnchor:replaceTitle.bottomAnchor constant:6.0],
        [replaceSubtitle.leadingAnchor constraintEqualToAnchor:replaceTitle.leadingAnchor],
        [replaceSubtitle.trailingAnchor constraintEqualToAnchor:replaceTitle.trailingAnchor],

        [self.replacementUUIDTextField.topAnchor constraintEqualToAnchor:replaceSubtitle.bottomAnchor constant:12.0],
        [self.replacementUUIDTextField.leadingAnchor constraintEqualToAnchor:replaceCard.leadingAnchor constant:18.0],
        [self.replacementUUIDTextField.trailingAnchor constraintEqualToAnchor:replaceCard.trailingAnchor constant:-18.0],
        [self.replacementUUIDTextField.heightAnchor constraintEqualToConstant:48.0],

        [replaceButton.topAnchor constraintEqualToAnchor:self.replacementUUIDTextField.bottomAnchor constant:12.0],
        [replaceButton.leadingAnchor constraintEqualToAnchor:self.replacementUUIDTextField.leadingAnchor],
        [replaceButton.trailingAnchor constraintEqualToAnchor:self.replacementUUIDTextField.trailingAnchor],

        [clearButton.topAnchor constraintEqualToAnchor:replaceButton.bottomAnchor constant:10.0],
        [clearButton.leadingAnchor constraintEqualToAnchor:replaceButton.leadingAnchor],
        [clearButton.trailingAnchor constraintEqualToAnchor:replaceButton.trailingAnchor],
        [clearButton.bottomAnchor constraintEqualToAnchor:replaceCard.bottomAnchor constant:-18.0],

        [self.hintLabel.topAnchor constraintEqualToAnchor:replaceCard.bottomAnchor constant:14.0],
        [self.hintLabel.leadingAnchor constraintEqualToAnchor:replaceCard.leadingAnchor constant:4.0],
        [self.hintLabel.trailingAnchor constraintEqualToAnchor:replaceCard.trailingAnchor constant:-4.0],
        [self.hintLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-24.0]
    ]];
}

- (void)showMessageWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"موافق" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)copyText:(NSString *)text title:(NSString *)title message:(NSString *)message {
    NSString *normalized = [LSAppIdentifierProvider normalizedApplicationIdentifier:text] ?: text;
    UIPasteboard.generalPasteboard.string = normalized;
    [self showMessageWithTitle:title message:message];
}

- (void)copyActiveUUID {
    [self copyText:self.activeUUIDLabel.text title:@"تم النسخ" message:@"تم نسخ المعرّف المستخدم حالياً داخل الأداة."];
}

- (void)copyRealUUID {
    [self copyText:self.realUUIDLabel.text title:@"تم النسخ" message:@"تم نسخ UUID التطبيق الأصلي."];
}

- (void)saveCurrentUUID {
    NSString *current = [LSAppIdentifierProvider currentApplicationIdentifier];
    [NSUserDefaults.standardUserDefaults setObject:current forKey:kLSSavedCurrentAppUUIDKey];
    [NSUserDefaults.standardUserDefaults synchronize];
    self.savedUUIDLabel.text = current;
    [self showMessageWithTitle:@"تم الحفظ" message:@"تم حفظ معرّف التطبيق الأصلي داخل الأداة."];
}

- (void)replaceUUIDAndRestart {
    [self.replacementUUIDTextField resignFirstResponder];
    NSString *errorMessage = nil;
    BOOL saved = [LSAppIdentifierProvider saveReplacementApplicationIdentifier:self.replacementUUIDTextField.text errorMessage:&errorMessage];
    if (!saved) {
        [self showMessageWithTitle:@"تعذر الاستبدال" message:errorMessage ?: @"تأكد من المعرّف وحاول مرة ثانية."];
        return;
    }

    NSString *replacement = [LSAppIdentifierProvider replacementApplicationIdentifier] ?: @"";
    self.replacementUUIDTextField.text = replacement;
    self.activeUUIDLabel.text = [LSAppIdentifierProvider applicationIdentifierForTestMode];

    BOOL appliedNow = [LSAppIdentifierProvider isReplacementIdentifierAppliedInCurrentProcess];
    NSString *message = appliedNow ? @"تم حفظ المعرّف الجديد والتحقق من قراءته داخل العملية الحالية. سيتم الآن تنظيف بيانات التطبيق وإعادة التشغيل." : @"تم حفظ المعرّف الجديد. سيتم الآن تنظيف بيانات التطبيق والـ Keychain ثم إعادة التشغيل حتى يقرأ التطبيق UUID الجديد من البداية.";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"تم الاستبدال"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"إعادة التشغيل الآن" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [weakSelf restartApplicationProcess];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)clearReplacementUUID {
    self.replacementUUIDTextField.text = @"";
    [LSAppIdentifierProvider clearReplacementApplicationIdentifier];
    self.activeUUIDLabel.text = [LSAppIdentifierProvider applicationIdentifierForTestMode];
    [self showMessageWithTitle:@"تم المسح" message:@"تم حذف المعرّف البديل ورجوع الأداة للمعرّف الأصلي."];
}

- (void)restartApplicationProcess {
    [LSUUIDResetManager restartAfterApplyingUUID];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

@end
