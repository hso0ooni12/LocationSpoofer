#import "LSWiFiScannerViewController.h"
#import "LSFloatingPanel.h"

#import <CoreLocation/CoreLocation.h>
#import <SystemConfiguration/CaptiveNetwork.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <math.h>

static NSString * const kLSWiFiSavedNetworksKey = @"LSWiFiSavedNetworksV1";
static NSString * const kLSWiFiActiveNetworkKey = @"LSWiFiActiveNetworkV1";
static NSString * const kLSWiFiDefaultsSuiteName = @"com.xsgps.dylib";

static NSString *LSWiFiNormalizedBSSIDString(NSString *value) {
    if (![value isKindOfClass:NSString.class]) {
        return @"";
    }

    NSString *clean = [[value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    clean = [[clean stringByReplacingOccurrencesOfString:@"-" withString:@":"] stringByReplacingOccurrencesOfString:@" " withString:@""];
    if (clean.length == 12 && ![clean containsString:@":"]) {
        NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:6];
        for (NSUInteger index = 0; index < 12; index += 2) {
            [parts addObject:[clean substringWithRange:NSMakeRange(index, 2)]];
        }
        clean = [parts componentsJoinedByString:@":"];
    }

    NSArray<NSString *> *parts = [clean componentsSeparatedByString:@":"];
    if (parts.count != 6) {
        return @"";
    }

    NSCharacterSet *hexSet = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"];
    for (NSString *part in parts) {
        if (part.length != 2) {
            return @"";
        }
        for (NSUInteger index = 0; index < part.length; index++) {
            if (![hexSet characterIsMember:[part characterAtIndex:index]]) {
                return @"";
            }
        }
    }
    return clean;
}

#pragma mark - Radar View

@interface LSWiFiRadarView : UIView
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, NSNumber *> *> *points;
@end

@implementation LSWiFiRadarView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _points = @[];
        self.backgroundColor = UIColor.clearColor;
        self.opaque = NO;
    }
    return self;
}

- (void)setPoints:(NSArray<NSDictionary<NSString *,NSNumber *> *> *)points {
    _points = [points copy] ?: @[];
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) { return; }

    CGPoint center = CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect));
    CGFloat maxRadius = MIN(rect.size.width, rect.size.height) * 0.46;
    UIColor *lineColor = [[UIColor colorWithRed:0.16 green:0.90 blue:0.70 alpha:1.0] colorWithAlphaComponent:0.16];
    UIColor *pointColor = [UIColor colorWithRed:0.16 green:0.90 blue:0.70 alpha:1.0];

    CGContextSetLineWidth(ctx, 1.4);
    CGContextSetStrokeColorWithColor(ctx, lineColor.CGColor);
    for (NSInteger i = 1; i <= 3; i++) {
        CGFloat r = maxRadius * ((CGFloat)i / 3.0);
        CGContextStrokeEllipseInRect(ctx, CGRectMake(center.x - r, center.y - r, r * 2.0, r * 2.0));
    }

    CGContextMoveToPoint(ctx, center.x - maxRadius, center.y);
    CGContextAddLineToPoint(ctx, center.x + maxRadius, center.y);
    CGContextMoveToPoint(ctx, center.x, center.y - maxRadius);
    CGContextAddLineToPoint(ctx, center.x, center.y + maxRadius);
    CGContextStrokePath(ctx);

    for (NSDictionary<NSString *, NSNumber *> *point in self.points) {
        CGFloat angle = point[@"angle"].doubleValue;
        CGFloat radiusFactor = MAX(0.12, MIN(0.96, point[@"radius"].doubleValue));
        CGFloat r = maxRadius * radiusFactor;
        CGPoint p = CGPointMake(center.x + cos(angle) * r, center.y + sin(angle) * r);
        CGRect glowRect = CGRectMake(p.x - 9.0, p.y - 9.0, 18.0, 18.0);
        CGRect dotRect = CGRectMake(p.x - 5.0, p.y - 5.0, 10.0, 10.0);
        CGContextSetFillColorWithColor(ctx, [pointColor colorWithAlphaComponent:0.22].CGColor);
        CGContextFillEllipseInRect(ctx, glowRect);
        CGContextSetFillColorWithColor(ctx, pointColor.CGColor);
        CGContextFillEllipseInRect(ctx, dotRect);
    }

    CGContextSetFillColorWithColor(ctx, pointColor.CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(center.x - 3.0, center.y - 3.0, 6.0, 6.0));
}

@end

#pragma mark - Scanner

@interface LSWiFiScannerViewController () <UITableViewDataSource, UITableViewDelegate, CLLocationManagerDelegate>
@property (nonatomic, strong) NSMutableArray<NSDictionary<NSString *, id> *> *discoveredNetworks;
@property (nonatomic, strong) NSMutableArray<NSDictionary<NSString *, id> *> *savedNetworks;
@property (nonatomic, strong) NSMutableArray<NSDictionary<NSString *, NSNumber *> *> *radarPoints;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *activeLabel;
@property (nonatomic, strong) UIButton *scanButton;
@property (nonatomic, strong) UIButton *manualAddButton;
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) UISegmentedControl *modeControl;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) LSWiFiRadarView *radarView;
@property (nonatomic, copy, nullable) NSString *activeNetworkIdentifier;
@end

@implementation LSWiFiScannerViewController

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.modalPresentationStyle = UIModalPresentationOverFullScreen;
        self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    }
    return self;
}


#pragma mark - Defaults

- (NSUserDefaults *)toolDefaults {
    return [[NSUserDefaults alloc] initWithSuiteName:kLSWiFiDefaultsSuiteName] ?: NSUserDefaults.standardUserDefaults;
}

- (NSArray<NSDictionary<NSString *, id> *> *)storedSavedNetworks {
    NSArray *suiteNetworks = [[self toolDefaults] arrayForKey:kLSWiFiSavedNetworksKey];
    if ([suiteNetworks isKindOfClass:NSArray.class]) { return suiteNetworks; }
    NSArray *standardNetworks = [NSUserDefaults.standardUserDefaults arrayForKey:kLSWiFiSavedNetworksKey];
    return [standardNetworks isKindOfClass:NSArray.class] ? standardNetworks : @[];
}

- (nullable NSDictionary<NSString *, id> *)storedActiveNetwork {
    NSDictionary *suiteNetwork = [[self toolDefaults] dictionaryForKey:kLSWiFiActiveNetworkKey];
    if ([suiteNetwork isKindOfClass:NSDictionary.class]) { return suiteNetwork; }
    NSDictionary *standardNetwork = [NSUserDefaults.standardUserDefaults dictionaryForKey:kLSWiFiActiveNetworkKey];
    return [standardNetwork isKindOfClass:NSDictionary.class] ? standardNetwork : nil;
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = UIColor.clearColor;
    self.view.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;

    self.discoveredNetworks = [NSMutableArray array];
    self.savedNetworks = [[self sanitizedNetworksFromArray:[self storedSavedNetworks]] mutableCopy] ?: [NSMutableArray array];
    self.radarPoints = [NSMutableArray array];
    NSDictionary *active = [self normalizedNetwork:[self storedActiveNetwork]];
    self.activeNetworkIdentifier = [self identifierForNetwork:active];

    [self buildInterface];
    [self ensureWiFiLocationReadiness];
    [self refreshActiveStatus];
    [self scanTapped];
}

#pragma mark - UI

- (UIButton *)ls_buttonWithTitle:(NSString *)title tint:(UIColor *)tint action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:tint forState:UIControlStateNormal];
    button.tintColor = tint;
    button.titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightBlack];
    button.titleLabel.adjustsFontSizeToFitWidth = YES;
    button.titleLabel.minimumScaleFactor = 0.72;
    button.backgroundColor = [[UIColor colorWithRed:0.02 green:0.20 blue:0.15 alpha:1.0] colorWithAlphaComponent:0.96];
    button.layer.cornerRadius = 13.0;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    button.layer.borderWidth = 1.4;
    button.layer.borderColor = tint.CGColor;
    button.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [button.heightAnchor constraintEqualToConstant:52.0].active = YES;
    return button;
}

- (UIButton *)ls_cellButtonWithTitle:(NSString *)title color:(UIColor *)color {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightBlack];
    button.backgroundColor = color;
    button.layer.cornerRadius = 12.0;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    button.frame = CGRectMake(0.0, 0.0, 96.0, 44.0);
    return button;
}

- (void)buildInterface {
    UIView *panel = [self ls_xsgps_installFloatingPanelWithBackgroundColor:[UIColor colorWithRed:0.055 green:0.055 blue:0.070 alpha:1.0]];
    [self ls_xsgps_addGrabberToFloatingPanel:panel color:[UIColor colorWithWhite:0.70 alpha:0.45]];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [close setTitle:@"إغلاق" forState:UIControlStateNormal];
    [close setTitleColor:[UIColor colorWithRed:0.16 green:0.90 blue:0.70 alpha:1.0] forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightBold];
    [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:close];

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"بحث الوايفاي 📶";
    title.font = [UIFont systemFontOfSize:24.0 weight:UIFontWeightBlack];
    title.textColor = UIColor.whiteColor;
    title.textAlignment = NSTextAlignmentCenter;
    [panel addSubview:title];

    self.radarView = [[LSWiFiRadarView alloc] init];
    self.radarView.translatesAutoresizingMaskIntoConstraints = NO;
    [panel addSubview:self.radarView];

    self.activeLabel = [[UILabel alloc] init];
    self.activeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.activeLabel.text = @"اضغط بحث لاكتشاف شبكات الوايفاي القريبة";
    self.activeLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightBlack];
    self.activeLabel.textColor = [UIColor colorWithRed:0.16 green:0.90 blue:0.70 alpha:1.0];
    self.activeLabel.textAlignment = NSTextAlignmentCenter;
    self.activeLabel.numberOfLines = 2;
    [panel addSubview:self.activeLabel];

    self.scanButton = [self ls_buttonWithTitle:@"بحث 🔍" tint:[UIColor colorWithRed:0.16 green:0.90 blue:0.70 alpha:1.0] action:@selector(scanTapped)];
    self.manualAddButton = [self ls_buttonWithTitle:@"إضافة يدويًا +" tint:UIColor.systemBlueColor action:@selector(manualAddTapped)];

    UIStackView *scanRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.scanButton, self.manualAddButton]];
    scanRow.translatesAutoresizingMaskIntoConstraints = NO;
    scanRow.axis = UILayoutConstraintAxisHorizontal;
    scanRow.spacing = 8.0;
    scanRow.alignment = UIStackViewAlignmentFill;
    scanRow.distribution = UIStackViewDistributionFillEqually;
    scanRow.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    [panel addSubview:scanRow];

    self.modeControl = [[UISegmentedControl alloc] initWithItems:@[@"المكتشفة", @"المحفوظة"]];
    self.modeControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.modeControl.selectedSegmentIndex = 0;
    self.modeControl.backgroundColor = [UIColor colorWithRed:0.17 green:0.17 blue:0.21 alpha:1.0];
    self.modeControl.selectedSegmentTintColor = [UIColor colorWithWhite:0.47 alpha:1.0];
    NSDictionary *normalAttrs = @{ NSForegroundColorAttributeName: [UIColor colorWithWhite:0.75 alpha:1.0], NSFontAttributeName: [UIFont systemFontOfSize:16.0 weight:UIFontWeightBlack] };
    NSDictionary *selectedAttrs = @{ NSForegroundColorAttributeName: UIColor.whiteColor, NSFontAttributeName: [UIFont systemFontOfSize:16.0 weight:UIFontWeightBlack] };
    [self.modeControl setTitleTextAttributes:normalAttrs forState:UIControlStateNormal];
    [self.modeControl setTitleTextAttributes:selectedAttrs forState:UIControlStateSelected];
    [self.modeControl addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
    [panel addSubview:self.modeControl];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.text = @"جاري تجهيز الوايفاي…";
    self.statusLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    self.statusLabel.textColor = UIColor.secondaryLabelColor;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 2;
    [panel addSubview:self.statusLabel];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.separatorColor = [[UIColor whiteColor] colorWithAlphaComponent:0.06];
    self.tableView.rowHeight = 90.0;
    [panel addSubview:self.tableView];

    UILayoutGuide *safe = panel.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [close.topAnchor constraintEqualToAnchor:safe.topAnchor constant:20.0],
        [close.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:22.0],
        [close.widthAnchor constraintGreaterThanOrEqualToConstant:70.0],

        [title.topAnchor constraintEqualToAnchor:safe.topAnchor constant:22.0],
        [title.centerXAnchor constraintEqualToAnchor:panel.centerXAnchor],
        [title.leadingAnchor constraintGreaterThanOrEqualToAnchor:close.trailingAnchor constant:8.0],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:panel.trailingAnchor constant:-22.0],

        [self.radarView.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:16.0],
        [self.radarView.centerXAnchor constraintEqualToAnchor:panel.centerXAnchor],
        [self.radarView.widthAnchor constraintEqualToAnchor:panel.widthAnchor multiplier:0.48],
        [self.radarView.heightAnchor constraintEqualToAnchor:self.radarView.widthAnchor],

        [self.activeLabel.topAnchor constraintEqualToAnchor:self.radarView.bottomAnchor constant:8.0],
        [self.activeLabel.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:24.0],
        [self.activeLabel.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-24.0],

        [scanRow.topAnchor constraintEqualToAnchor:self.activeLabel.bottomAnchor constant:8.0],
        [scanRow.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:22.0],
        [scanRow.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-22.0],
        [scanRow.heightAnchor constraintEqualToConstant:52.0],

        [self.modeControl.topAnchor constraintEqualToAnchor:scanRow.bottomAnchor constant:12.0],
        [self.modeControl.leadingAnchor constraintEqualToAnchor:scanRow.leadingAnchor],
        [self.modeControl.trailingAnchor constraintEqualToAnchor:scanRow.trailingAnchor],
        [self.modeControl.heightAnchor constraintEqualToConstant:48.0],

        [self.statusLabel.topAnchor constraintEqualToAnchor:self.modeControl.bottomAnchor constant:6.0],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:22.0],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-22.0],

        [self.tableView.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:4.0],
        [self.tableView.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor]
    ]];
}

#pragma mark - Actions

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)modeChanged:(UISegmentedControl *)sender {
    (void)sender;
    [self.tableView reloadData];
    [self refreshActiveStatus];
}

- (void)scanTapped {
    [self.discoveredNetworks removeAllObjects];
    [self.radarPoints removeAllObjects];
    self.radarView.points = @[];
    self.statusLabel.text = @"جاري البحث عن شبكات الوايفاي القريبة…";
    self.activeLabel.text = @"البحث يعمل الآن 📶";
    [self.scanButton setTitle:@"تحديث 🔄" forState:UIControlStateNormal];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<NSDictionary<NSString *, id> *> *networks = [self collectWiFiNetworks];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.discoveredNetworks addObjectsFromArray:networks];
            [self rebuildRadarPoints];
            self.modeControl.selectedSegmentIndex = 0;
            if (networks.count == 0) {
                self.statusLabel.text = @"لم يتم العثور على شبكات. فعّل إذن الموقع، وتأكد من توفر MobileWiFi/NEHotspotNetwork، أو استخدم إضافة يدويًا.";
                self.activeLabel.text = self.savedNetworks.count ? @"اختر شبكة محفوظة أو أعد البحث" : @"لا توجد شبكات مكتشفة حالياً";
            } else {
                self.statusLabel.text = [NSString stringWithFormat:@"تم التقاط %lu شبكة وايفاي. احفظ الشبكة ثم بثها من المحفوظة.", (unsigned long)networks.count];
                [self refreshActiveStatus];
            }
            [self.tableView reloadData];
        });
    });
}

- (void)saveButtonTapped:(UIButton *)sender {
    NSInteger index = sender.tag;
    if (index < 0 || index >= (NSInteger)self.discoveredNetworks.count) { return; }
    NSDictionary<NSString *, id> *network = [self normalizedNetwork:self.discoveredNetworks[index]];
    if (!network) { self.statusLabel.text = @"تعذر حفظ الشبكة: البيانات غير مكتملة."; return; }
    [self saveNetwork:network];
    self.modeControl.selectedSegmentIndex = 1;
    [self.tableView reloadData];
    NSString *name = [self displayNameForNetwork:network];
    self.statusLabel.text = [NSString stringWithFormat:@"تم حفظ %@ مع نفس SSID/BSSID.", name];
    [self refreshActiveStatus];
}

- (void)manualAddTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"إضافة شبكة وايفاي" message:@"اكتب الاسم و ID/BSSID حتى تحفظها وتبثها داخل الأداة." preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"SSID / اسم الشبكة";
        textField.textAlignment = NSTextAlignmentRight;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"BSSID / ID مثال 00:11:22:33:44:55";
        textField.textAlignment = NSTextAlignmentRight;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"حفظ" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) { return; }
        NSString *ssid = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
        NSString *bssid = [alert.textFields.lastObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
        if (ssid.length == 0 && bssid.length == 0) {
            strongSelf.statusLabel.text = @"اكتب اسم الشبكة أو ID/BSSID أولًا.";
            return;
        }
        NSDictionary<NSString *, id> *network = @{
            @"ssid": ssid,
            @"bssid": bssid.lowercaseString,
            @"rssi": @0,
            @"secure": @YES,
            @"source": @"Manual",
            @"lastSeen": @([[NSDate date] timeIntervalSince1970])
        };
        [strongSelf saveNetwork:network];
        strongSelf.modeControl.selectedSegmentIndex = 1;
        [strongSelf.tableView reloadData];
        strongSelf.statusLabel.text = @"تمت إضافة الشبكة يدويًا ويمكن بثها الآن.";
        [strongSelf refreshActiveStatus];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)broadcastButtonTapped:(UIButton *)sender {
    NSInteger index = sender.tag;
    if (index < 0 || index >= (NSInteger)self.savedNetworks.count) { return; }
    NSDictionary<NSString *, id> *network = self.savedNetworks[index];
    NSString *identifier = [self identifierForNetwork:network];
    if (identifier.length > 0 && [self.activeNetworkIdentifier isEqualToString:identifier]) {
        [self stopBroadcastingNetwork];
    } else {
        [self startBroadcastingNetwork:network];
    }
}

#pragma mark - Location Permission Helper

- (void)ensureWiFiLocationReadiness {
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    BOOL hasWhenInUseUsage = [info[@"NSLocationWhenInUseUsageDescription"] isKindOfClass:NSString.class];
    BOOL hasAlwaysUsage = [info[@"NSLocationAlwaysAndWhenInUseUsageDescription"] isKindOfClass:NSString.class] || [info[@"NSLocationAlwaysUsageDescription"] isKindOfClass:NSString.class];
    CLAuthorizationStatus status = [CLLocationManager authorizationStatus];
    if (status == kCLAuthorizationStatusNotDetermined && (hasWhenInUseUsage || hasAlwaysUsage)) {
        self.locationManager = [[CLLocationManager alloc] init];
        self.locationManager.delegate = self;
        [self.locationManager requestWhenInUseAuthorization];
        self.statusLabel.text = @"قد تحتاج الموافقة على إذن الموقع لإظهار SSID/BSSID الحالي.";
    } else if (status == kCLAuthorizationStatusDenied || status == kCLAuthorizationStatusRestricted) {
        self.statusLabel.text = @"إذن الموقع غير مفعل؛ قد لا يظهر SSID/BSSID إلا عبر MobileWiFi أو الإضافة اليدوية.";
    }
}

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
    (void)manager;
    CLAuthorizationStatus status = [CLLocationManager authorizationStatus];
    if (status != kCLAuthorizationStatusNotDetermined) {
        [self scanTapped];
    }
}

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
    (void)manager;
    if (status != kCLAuthorizationStatusNotDetermined) {
        [self scanTapped];
    }
}

#pragma mark - Persistence

- (nullable NSDictionary<NSString *, id> *)normalizedNetwork:(NSDictionary<NSString *, id> *)network {
    if (![network isKindOfClass:NSDictionary.class]) { return nil; }

    NSString *(^cleanString)(id) = ^NSString *(id value) {
        if (![value isKindOfClass:NSString.class]) { return @""; }
        return [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    };

    NSString *ssid = cleanString(network[@"ssid"]);
    NSString *bssid = LSWiFiNormalizedBSSIDString(cleanString(network[@"bssid"]));
    if (ssid.length == 0 && bssid.length == 0) { return nil; }

    NSNumber *rssi = [network[@"rssi"] isKindOfClass:NSNumber.class] ? network[@"rssi"] : @0;
    NSNumber *secure = [network[@"secure"] isKindOfClass:NSNumber.class] ? network[@"secure"] : @YES;
    NSString *source = cleanString(network[@"source"]);

    return @{
        @"ssid": ssid ?: @"",
        @"bssid": bssid ?: @"",
        @"rssi": rssi ?: @0,
        @"secure": secure ?: @YES,
        @"source": source.length ? source : @"Saved",
        @"lastSeen": [network[@"lastSeen"] isKindOfClass:NSNumber.class] ? network[@"lastSeen"] : @([[NSDate date] timeIntervalSince1970])
    };
}

- (NSArray<NSDictionary<NSString *, id> *> *)sanitizedNetworksFromArray:(NSArray *)networks {
    NSMutableArray<NSDictionary<NSString *, id> *> *cleanNetworks = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (id item in networks) {
        NSDictionary<NSString *, id> *network = [self normalizedNetwork:item];
        if (!network) { continue; }
        NSString *identifier = [self identifierForNetwork:network];
        if (identifier.length == 0 || [seen containsObject:identifier]) { continue; }
        [cleanNetworks addObject:network];
        [seen addObject:identifier];
    }
    return cleanNetworks;
}

- (void)saveNetwork:(NSDictionary<NSString *, id> *)network {
    NSDictionary<NSString *, id> *cleanNetwork = [self normalizedNetwork:network];
    NSString *identifier = [self identifierForNetwork:cleanNetwork];
    if (identifier.length == 0) { return; }

    NSUInteger existingIndex = [self.savedNetworks indexOfObjectPassingTest:^BOOL(NSDictionary<NSString *,id> *obj, NSUInteger idx, BOOL *stop) {
        (void)idx;
        BOOL match = [[self identifierForNetwork:obj] isEqualToString:identifier];
        if (match) { *stop = YES; }
        return match;
    }];
    if (existingIndex == NSNotFound) {
        [self.savedNetworks insertObject:cleanNetwork atIndex:0];
    } else {
        [self.savedNetworks replaceObjectAtIndex:existingIndex withObject:cleanNetwork];
    }
    [self persistSavedNetworks];
}

- (void)persistSavedNetworks {
    NSArray<NSDictionary<NSString *, id> *> *payload = [self sanitizedNetworksFromArray:self.savedNetworks];
    self.savedNetworks = [payload mutableCopy] ?: [NSMutableArray array];
    NSUserDefaults *toolDefaults = [self toolDefaults];
    [toolDefaults setObject:payload forKey:kLSWiFiSavedNetworksKey];
    [toolDefaults synchronize];
    [NSUserDefaults.standardUserDefaults setObject:payload forKey:kLSWiFiSavedNetworksKey];
    [NSUserDefaults.standardUserDefaults synchronize];
}

- (void)startBroadcastingNetwork:(NSDictionary<NSString *, id> *)network {
    NSDictionary<NSString *, id> *cleanNetwork = [self normalizedNetwork:network];
    NSString *identifier = [self identifierForNetwork:cleanNetwork];
    if (identifier.length == 0) { self.statusLabel.text = @"تعذر البث: بيانات الشبكة غير صالحة."; return; }
    self.activeNetworkIdentifier = identifier;
    NSUserDefaults *toolDefaults = [self toolDefaults];
    [toolDefaults setObject:cleanNetwork forKey:kLSWiFiActiveNetworkKey];
    [toolDefaults synchronize];
    [NSUserDefaults.standardUserDefaults setObject:cleanNetwork forKey:kLSWiFiActiveNetworkKey];
    [NSUserDefaults.standardUserDefaults synchronize];
    NSString *name = [self displayNameForNetwork:cleanNetwork];
    NSString *bssid = [cleanNetwork[@"bssid"] isKindOfClass:NSString.class] ? cleanNetwork[@"bssid"] : @"";
    self.statusLabel.text = bssid.length ? [NSString stringWithFormat:@"تم تفعيل بث معلومات %@ بنفس ID: %@", name, bssid] : [NSString stringWithFormat:@"تم تفعيل بث معلومات %@ بنفس الاسم.", name];
    [self refreshActiveStatus];
    [self.tableView reloadData];
}

- (void)stopBroadcastingNetwork {
    self.activeNetworkIdentifier = nil;
    NSUserDefaults *toolDefaults = [self toolDefaults];
    [toolDefaults removeObjectForKey:kLSWiFiActiveNetworkKey];
    [toolDefaults synchronize];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:kLSWiFiActiveNetworkKey];
    [NSUserDefaults.standardUserDefaults synchronize];
    self.statusLabel.text = @"تم إيقاف بث شبكة الوايفاي.";
    [self refreshActiveStatus];
    [self.tableView reloadData];
}

#pragma mark - Wi-Fi Collection

typedef CFTypeRef (*LSWiFiManagerCreateFunc)(CFAllocatorRef allocator, int flags);
typedef CFArrayRef (*LSWiFiManagerCopyDevicesFunc)(CFTypeRef manager);
typedef int (*LSWiFiDeviceScanFunc)(CFTypeRef device, CFDictionaryRef parameters);
typedef CFArrayRef (*LSWiFiDeviceCopyNetworksFunc)(CFTypeRef device);
typedef CFStringRef (*LSWiFiNetworkCopyStringFunc)(CFTypeRef network);
typedef CFNumberRef (*LSWiFiNetworkCopyNumberFunc)(CFTypeRef network);
typedef Boolean (*LSWiFiNetworkBoolFunc)(CFTypeRef network);

- (NSArray<NSDictionary<NSString *, id> *> *)collectWiFiNetworks {
    NSMutableArray<NSDictionary<NSString *, id> *> *networks = [NSMutableArray array];
    [self appendMobileWiFiNetworksToArray:networks];
    [self appendCurrentWiFiNetworkToArray:networks];
    [self appendNEHotspotCurrentNetworkToArray:networks];
    [self appendStoredActiveNetworkToArray:networks];
    return [self deduplicatedNetworksFromArray:networks];
}

- (void)appendMobileWiFiNetworksToArray:(NSMutableArray<NSDictionary<NSString *, id> *> *)networks {
    void *handle = dlopen("/System/Library/PrivateFrameworks/MobileWiFi.framework/MobileWiFi", RTLD_LAZY);
    if (!handle) { return; }

    LSWiFiManagerCreateFunc managerCreate = (LSWiFiManagerCreateFunc)dlsym(handle, "WiFiManagerClientCreate");
    LSWiFiManagerCopyDevicesFunc copyDevices = (LSWiFiManagerCopyDevicesFunc)dlsym(handle, "WiFiManagerClientCopyDevices");
    LSWiFiDeviceScanFunc scanDevice = (LSWiFiDeviceScanFunc)dlsym(handle, "WiFiDeviceClientScan");
    LSWiFiDeviceCopyNetworksFunc copyNetworks = (LSWiFiDeviceCopyNetworksFunc)dlsym(handle, "WiFiDeviceClientCopyNetworks");
    LSWiFiNetworkCopyStringFunc getSSID = (LSWiFiNetworkCopyStringFunc)dlsym(handle, "WiFiNetworkGetSSID");
    LSWiFiNetworkCopyStringFunc getBSSID = (LSWiFiNetworkCopyStringFunc)dlsym(handle, "WiFiNetworkGetBSSID");
    LSWiFiNetworkCopyNumberFunc getRSSI = (LSWiFiNetworkCopyNumberFunc)dlsym(handle, "WiFiNetworkGetRSSI");
    LSWiFiNetworkBoolFunc isSecure = (LSWiFiNetworkBoolFunc)dlsym(handle, "WiFiNetworkIsSecure");

    if (!managerCreate || !copyDevices || !copyNetworks) {
        dlclose(handle);
        return;
    }

    CFTypeRef manager = managerCreate(kCFAllocatorDefault, 0);
    if (!manager) {
        dlclose(handle);
        return;
    }

    CFArrayRef devices = copyDevices(manager);
    if (devices) {
        CFIndex count = CFArrayGetCount(devices);
        for (CFIndex i = 0; i < count; i++) {
            CFTypeRef device = CFArrayGetValueAtIndex(devices, i);
            if (!device) { continue; }
            if (scanDevice) {
                scanDevice(device, NULL);
                [NSThread sleepForTimeInterval:0.45];
            }
            CFArrayRef rawNetworks = copyNetworks(device);
            if (!rawNetworks) { continue; }
            CFIndex networkCount = CFArrayGetCount(rawNetworks);
            for (CFIndex n = 0; n < networkCount; n++) {
                CFTypeRef rawNetwork = CFArrayGetValueAtIndex(rawNetworks, n);
                NSDictionary<NSString *, id> *network = [self dictionaryFromMobileWiFiNetwork:rawNetwork getSSID:getSSID getBSSID:getBSSID getRSSI:getRSSI isSecure:isSecure];
                if (network) { [networks addObject:network]; }
            }
            CFRelease(rawNetworks);
        }
        CFRelease(devices);
    }
    CFRelease(manager);
    dlclose(handle);
}

- (nullable NSDictionary<NSString *, id> *)dictionaryFromMobileWiFiNetwork:(CFTypeRef)rawNetwork
                                                                    getSSID:(LSWiFiNetworkCopyStringFunc)getSSID
                                                                   getBSSID:(LSWiFiNetworkCopyStringFunc)getBSSID
                                                                    getRSSI:(LSWiFiNetworkCopyNumberFunc)getRSSI
                                                                   isSecure:(LSWiFiNetworkBoolFunc)isSecure {
    if (!rawNetwork) { return nil; }

    NSString *ssid = @"";
    NSString *bssid = @"";
    NSNumber *rssi = @0;
    NSNumber *secure = @NO;
    NSString *source = @"MobileWiFi";

    if (CFGetTypeID(rawNetwork) == CFDictionaryGetTypeID()) {
        NSDictionary *dict = (__bridge NSDictionary *)rawNetwork;
        id ssidValue = dict[@"SSID_STR"] ?: dict[@"SSID"] ?: dict[@"ssid"];
        if ([ssidValue isKindOfClass:NSString.class]) { ssid = ssidValue; }
        id bssidValue = dict[@"BSSID"] ?: dict[@"bssid"];
        if ([bssidValue isKindOfClass:NSString.class]) { bssid = bssidValue; }
        id rssiValue = dict[@"RSSI"] ?: dict[@"rssi"];
        if ([rssiValue isKindOfClass:NSNumber.class]) { rssi = rssiValue; }
        id securityValue = dict[@"CAPABILITIES"] ?: dict[@"security"];
        if ([securityValue isKindOfClass:NSString.class]) { secure = @([(NSString *)securityValue length] > 0); }
    } else {
        if (getSSID) {
            CFStringRef ssidRef = getSSID(rawNetwork);
            if (ssidRef) { ssid = [(__bridge NSString *)ssidRef copy]; }
        }
        if (getBSSID) {
            CFStringRef bssidRef = getBSSID(rawNetwork);
            if (bssidRef) { bssid = [(__bridge NSString *)bssidRef copy]; }
        }
        if (getRSSI) {
            CFNumberRef rssiRef = getRSSI(rawNetwork);
            if (rssiRef) { rssi = (__bridge NSNumber *)rssiRef; }
        }
        if (isSecure) { secure = @(isSecure(rawNetwork)); }
    }

    ssid = [ssid isKindOfClass:NSString.class] ? [ssid stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
    bssid = [bssid isKindOfClass:NSString.class] ? LSWiFiNormalizedBSSIDString(bssid) : @"";
    if (ssid.length == 0 && bssid.length == 0) { return nil; }

    return @{
        @"ssid": ssid ?: @"",
        @"bssid": bssid ?: @"",
        @"rssi": rssi ?: @0,
        @"secure": secure ?: @NO,
        @"source": source,
        @"lastSeen": @([[NSDate date] timeIntervalSince1970])
    };
}

- (void)appendCurrentWiFiNetworkToArray:(NSMutableArray<NSDictionary<NSString *, id> *> *)networks {
    CFArrayRef interfaces = CNCopySupportedInterfaces();
    if (!interfaces) { return; }

    CFIndex count = CFArrayGetCount(interfaces);
    for (CFIndex i = 0; i < count; i++) {
        CFStringRef interfaceName = CFArrayGetValueAtIndex(interfaces, i);
        if (!interfaceName) { continue; }
        CFDictionaryRef info = CNCopyCurrentNetworkInfo(interfaceName);
        if (!info) { continue; }
        NSDictionary *networkInfo = (__bridge NSDictionary *)info;
        NSString *ssid = [networkInfo[(__bridge NSString *)kCNNetworkInfoKeySSID] isKindOfClass:NSString.class] ? networkInfo[(__bridge NSString *)kCNNetworkInfoKeySSID] : @"";
        NSString *bssid = [networkInfo[(__bridge NSString *)kCNNetworkInfoKeyBSSID] isKindOfClass:NSString.class] ? LSWiFiNormalizedBSSIDString(networkInfo[(__bridge NSString *)kCNNetworkInfoKeyBSSID]) : @"";
        if (ssid.length > 0 || bssid.length > 0) {
            [networks addObject:@{
                @"ssid": ssid ?: @"",
                @"bssid": bssid ?: @"",
                @"rssi": @0,
                @"secure": @YES,
                @"source": @"CurrentWiFi",
                @"lastSeen": @([[NSDate date] timeIntervalSince1970])
            }];
        }
        CFRelease(info);
    }
    CFRelease(interfaces);
}

- (nullable NSString *)stringValueFromObject:(id)object selector:(SEL)selector {
    if (!object || !selector || ![object respondsToSelector:selector]) { return nil; }
    NSString *value = nil;
    @try {
        value = ((id (*)(id, SEL))objc_msgSend)(object, selector);
    } @catch (__unused NSException *exception) {
        value = nil;
    }
    return [value isKindOfClass:NSString.class] ? value : nil;
}

- (nullable NSDictionary<NSString *, id> *)dictionaryFromNEHotspotNetwork:(id)hotspot {
    if (!hotspot) { return nil; }
    NSString *ssid = [self stringValueFromObject:hotspot selector:@selector(SSID)] ?: @"";
    NSString *bssid = [self stringValueFromObject:hotspot selector:@selector(BSSID)] ?: @"";

    BOOL secure = YES;
    if ([hotspot respondsToSelector:@selector(isSecure)]) {
        @try { secure = ((BOOL (*)(id, SEL))objc_msgSend)(hotspot, @selector(isSecure)); } @catch (__unused NSException *exception) { secure = YES; }
    }

    double signalStrength = 0.0;
    if ([hotspot respondsToSelector:@selector(signalStrength)]) {
        @try { signalStrength = ((double (*)(id, SEL))objc_msgSend)(hotspot, @selector(signalStrength)); } @catch (__unused NSException *exception) { signalStrength = 0.0; }
    }
    NSNumber *rssi = signalStrength > 0.0 ? @((NSInteger)lrint(-100.0 + MAX(0.0, MIN(1.0, signalStrength)) * 65.0)) : @0;

    return [self normalizedNetwork:@{
        @"ssid": ssid ?: @"",
        @"bssid": bssid ?: @"",
        @"rssi": rssi,
        @"secure": @(secure),
        @"source": @"NEHotspotNetwork",
        @"lastSeen": @([[NSDate date] timeIntervalSince1970])
    }];
}

- (void)appendNEHotspotCurrentNetworkToArray:(NSMutableArray<NSDictionary<NSString *, id> *> *)networks {
    dlopen("/System/Library/Frameworks/NetworkExtension.framework/NetworkExtension", RTLD_LAZY);
    Class hotspotClass = NSClassFromString(@"NEHotspotNetwork");
    SEL selector = NSSelectorFromString(@"fetchCurrentWithCompletionHandler:");
    if (!hotspotClass || ![hotspotClass respondsToSelector:selector]) { return; }

    __block NSDictionary<NSString *, id> *capturedNetwork = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    void (^completion)(id) = ^(id hotspot) {
        capturedNetwork = [self dictionaryFromNEHotspotNetwork:hotspot];
        dispatch_semaphore_signal(semaphore);
    };

    @try {
        ((void (*)(id, SEL, id))objc_msgSend)(hotspotClass, selector, completion);
        dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)));
    } @catch (__unused NSException *exception) {
        capturedNetwork = nil;
    }

    if (capturedNetwork) {
        [networks addObject:capturedNetwork];
    }
}

- (void)appendStoredActiveNetworkToArray:(NSMutableArray<NSDictionary<NSString *, id> *> *)networks {
    NSDictionary<NSString *, id> *active = [self normalizedNetwork:[self storedActiveNetwork]];
    if (!active) { return; }
    NSMutableDictionary<NSString *, id> *network = [active mutableCopy];
    network[@"source"] = @"ActiveBroadcast";
    [networks addObject:network];
}

- (NSArray<NSDictionary<NSString *, id> *> *)deduplicatedNetworksFromArray:(NSArray<NSDictionary<NSString *, id> *> *)networks {
    NSMutableArray<NSDictionary<NSString *, id> *> *unique = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSDictionary<NSString *, id> *network in networks) {
        NSString *identifier = [self identifierForNetwork:network];
        if (identifier.length == 0 || [seen containsObject:identifier]) { continue; }
        [seen addObject:identifier];
        [unique addObject:network];
    }
    [unique sortUsingComparator:^NSComparisonResult(NSDictionary<NSString *,id> *a, NSDictionary<NSString *,id> *b) {
        NSNumber *rssiA = [a[@"rssi"] isKindOfClass:NSNumber.class] ? a[@"rssi"] : @(-999);
        NSNumber *rssiB = [b[@"rssi"] isKindOfClass:NSNumber.class] ? b[@"rssi"] : @(-999);
        return [rssiB compare:rssiA];
    }];
    return unique;
}

#pragma mark - Helpers

- (NSString *)displayNameForNetwork:(NSDictionary<NSString *, id> *)network {
    NSString *ssid = [network[@"ssid"] isKindOfClass:NSString.class] ? network[@"ssid"] : @"";
    return ssid.length ? ssid : @"Hidden Wi-Fi";
}

- (NSString *)identifierForNetwork:(nullable NSDictionary<NSString *, id> *)network {
    if (![network isKindOfClass:NSDictionary.class]) { return @""; }
    NSString *bssid = [network[@"bssid"] isKindOfClass:NSString.class] ? network[@"bssid"] : @"";
    NSString *ssid = [network[@"ssid"] isKindOfClass:NSString.class] ? network[@"ssid"] : @"";
    if (bssid.length > 0) { return bssid.lowercaseString; }
    return ssid.lowercaseString;
}

- (CGFloat)radiusFactorForRSSI:(NSNumber *)RSSI {
    double value = RSSI.doubleValue;
    if (value == 0.0) { return 0.45; }
    if (value >= -35.0) { return 0.20; }
    if (value <= -100.0) { return 0.95; }
    return 0.20 + ((fabs(value) - 35.0) / 65.0) * 0.75;
}

- (void)rebuildRadarPoints {
    [self.radarPoints removeAllObjects];
    for (NSDictionary<NSString *, id> *network in self.discoveredNetworks) {
        NSString *identifier = [self identifierForNetwork:network];
        if (identifier.length == 0) { continue; }
        NSNumber *rssi = [network[@"rssi"] isKindOfClass:NSNumber.class] ? network[@"rssi"] : @0;
        NSUInteger hash = identifier.hash;
        CGFloat angle = ((CGFloat)(hash % 628)) / 100.0;
        CGFloat radius = [self radiusFactorForRSSI:rssi];
        [self.radarPoints addObject:@{ @"angle": @(angle), @"radius": @(radius) }];
        if (self.radarPoints.count >= 24) { break; }
    }
    self.radarView.points = self.radarPoints;
}

- (void)refreshActiveStatus {
    if (self.activeNetworkIdentifier.length == 0) {
        self.activeLabel.text = self.savedNetworks.count ? @"اختر شبكة محفوظة ثم اضغط بث 📡" : @"اضغط بحث لاكتشاف شبكات الوايفاي القريبة";
        return;
    }

    NSDictionary<NSString *, id> *activeNetwork = nil;
    for (NSDictionary<NSString *, id> *network in self.savedNetworks) {
        if ([[self identifierForNetwork:network] isEqualToString:self.activeNetworkIdentifier]) {
            activeNetwork = network;
            break;
        }
    }
    NSString *name = activeNetwork ? [self displayNameForNetwork:activeNetwork] : self.activeNetworkIdentifier;
    NSString *bssid = [activeNetwork[@"bssid"] isKindOfClass:NSString.class] ? activeNetwork[@"bssid"] : @"";
    self.activeLabel.text = bssid.length ? [NSString stringWithFormat:@"يبث: %@ • ID: %@ 📡", name, bssid] : [NSString stringWithFormat:@"يبث: %@ 📡", name];
}

- (NSString *)clipboardTextForNetwork:(NSDictionary<NSString *, id> *)network {
    NSString *ssid = [network[@"ssid"] isKindOfClass:NSString.class] ? network[@"ssid"] : @"";
    NSString *bssid = [network[@"bssid"] isKindOfClass:NSString.class] ? network[@"bssid"] : @"";
    NSNumber *rssi = [network[@"rssi"] isKindOfClass:NSNumber.class] ? network[@"rssi"] : @0;
    return [NSString stringWithFormat:@"SSID: %@\nBSSID: %@\nRSSI: %@", ssid.length ? ssid : @"Hidden", bssid.length ? bssid : @"N/A", rssi];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return self.modeControl.selectedSegmentIndex == 0 ? self.discoveredNetworks.count : self.savedNetworks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"WiFiNetworkCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"WiFiNetworkCell"];
    }
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.textLabel.textColor = UIColor.whiteColor;
    cell.textLabel.font = [UIFont systemFontOfSize:19.0 weight:UIFontWeightBlack];
    cell.textLabel.textAlignment = NSTextAlignmentRight;
    cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.70 alpha:1.0];
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:13.0 weight:UIFontWeightSemibold];
    cell.detailTextLabel.textAlignment = NSTextAlignmentRight;
    cell.detailTextLabel.numberOfLines = 2;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    UIImage *wifiImage = [UIImage systemImageNamed:@"wifi"];
    if (!wifiImage) { wifiImage = [UIImage systemImageNamed:@"dot.radiowaves.left.and.right"]; }
    cell.imageView.image = wifiImage;
    cell.imageView.tintColor = [UIColor colorWithRed:0.16 green:0.90 blue:0.70 alpha:1.0];

    BOOL savedMode = self.modeControl.selectedSegmentIndex == 1;
    NSDictionary<NSString *, id> *network = savedMode ? self.savedNetworks[indexPath.row] : self.discoveredNetworks[indexPath.row];
    NSString *name = [self displayNameForNetwork:network];
    NSString *bssid = [network[@"bssid"] isKindOfClass:NSString.class] ? network[@"bssid"] : @"";
    NSNumber *rssi = [network[@"rssi"] isKindOfClass:NSNumber.class] ? network[@"rssi"] : @0;
    NSNumber *secure = [network[@"secure"] isKindOfClass:NSNumber.class] ? network[@"secure"] : @NO;
    NSString *source = [network[@"source"] isKindOfClass:NSString.class] ? network[@"source"] : @"";

    cell.textLabel.text = name;
    NSString *firstLine = bssid.length ? [NSString stringWithFormat:@"ID: %@", bssid] : source;
    if (firstLine.length > 28) { firstLine = [[firstLine substringToIndex:28] stringByAppendingString:@"…"]; }
    NSString *securityText = secure.boolValue ? @"مؤمنة" : @"مفتوحة";
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@\n%@ • %@ dBm", firstLine, securityText, rssi];

    if (savedMode) {
        NSString *identifier = [self identifierForNetwork:network];
        BOOL active = identifier.length > 0 && [identifier isEqualToString:self.activeNetworkIdentifier];
        UIButton *button = [self ls_cellButtonWithTitle:(active ? @"وقف ⬜" : @"بث 📡") color:(active ? UIColor.systemRedColor : UIColor.systemPurpleColor)];
        button.tag = indexPath.row;
        [button addTarget:self action:@selector(broadcastButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        cell.accessoryView = button;
    } else {
        UIButton *button = [self ls_cellButtonWithTitle:@"حفظ 💾" color:UIColor.systemGreenColor];
        button.tag = indexPath.row;
        [button addTarget:self action:@selector(saveButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        cell.accessoryView = button;
    }
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    if (self.modeControl.selectedSegmentIndex == 0 && self.discoveredNetworks.count == 0) {
        return @"اضغط بحث، وبعد ظهور الشبكة اضغط حفظ. قد تحتاج صلاحية الموقع لقراءة SSID/BSSID.";
    }
    if (self.modeControl.selectedSegmentIndex == 1 && self.savedNetworks.count == 0) {
        return @"لا توجد شبكات محفوظة حتى الآن.";
    }
    return nil;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary<NSString *, id> *network = self.modeControl.selectedSegmentIndex == 0 ? self.discoveredNetworks[indexPath.row] : self.savedNetworks[indexPath.row];
    UIPasteboard.generalPasteboard.string = [self clipboardTextForNetwork:network];
    self.statusLabel.text = @"تم نسخ بيانات شبكة الوايفاي إلى الحافظة.";
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.modeControl.selectedSegmentIndex != 1 || editingStyle != UITableViewCellEditingStyleDelete) { return; }
    NSDictionary<NSString *, id> *network = self.savedNetworks[indexPath.row];
    NSString *identifier = [self identifierForNetwork:network];
    if (identifier.length > 0 && [identifier isEqualToString:self.activeNetworkIdentifier]) {
        [self stopBroadcastingNetwork];
    }
    [self.savedNetworks removeObjectAtIndex:indexPath.row];
    [self persistSavedNetworks];
    [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    [self refreshActiveStatus];
}

@end
