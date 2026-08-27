#import "LSBluetoothScannerViewController.h"
#import "LSBluetoothLogManager.h"
#import <CoreBluetooth/CoreBluetooth.h>
#import "LSFloatingPanel.h"
#include <math.h>

static NSString * const kLSBluetoothSavedDevicesKey = @"LSBluetoothSavedDevicesV2";

#pragma mark - Radar View

@interface LSBluetoothRadarView : UIView
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, NSNumber *> *> *points;
@end

@implementation LSBluetoothRadarView

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
    UIColor *lineColor = [[UIColor colorWithRed:0.0 green:0.75 blue:0.95 alpha:1.0] colorWithAlphaComponent:0.16];
    UIColor *pointColor = [UIColor colorWithRed:0.0 green:0.72 blue:1.0 alpha:1.0];

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

@interface LSBluetoothScannerViewController () <CBCentralManagerDelegate, CBPeripheralManagerDelegate, UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) CBCentralManager *centralManager;
@property (nonatomic, strong) CBPeripheralManager *peripheralManager;
@property (nonatomic, strong) NSMutableArray<NSDictionary<NSString *, id> *> *discoveredDevices;
@property (nonatomic, strong) NSMutableArray<NSDictionary<NSString *, id> *> *savedDevices;
@property (nonatomic, strong) NSMutableArray<NSDictionary<NSString *, NSNumber *> *> *radarPoints;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *broadcastLabel;
@property (nonatomic, strong) UIButton *scanButton;
@property (nonatomic, strong) UISegmentedControl *modeControl;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) LSBluetoothRadarView *radarView;
@property (nonatomic, assign) BOOL isScanning;
@property (nonatomic, copy, nullable) NSString *activeBroadcastIdentifier;
@property (nonatomic, strong, nullable) NSDictionary<NSString *, id> *pendingBroadcastDevice;
@end

@implementation LSBluetoothScannerViewController

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.modalPresentationStyle = UIModalPresentationOverFullScreen;
        self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    }
    return self;
}


#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = UIColor.clearColor;
    self.view.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;

    self.discoveredDevices = [NSMutableArray array];
    self.savedDevices = [[self sanitizedDevicesFromArray:[[NSUserDefaults standardUserDefaults] arrayForKey:kLSBluetoothSavedDevicesKey]] mutableCopy] ?: [NSMutableArray array];
    self.radarPoints = [NSMutableArray array];
    self.activeBroadcastIdentifier = nil;

    [self buildInterface];
    [self refreshBroadcastStatus];

    self.centralManager = [[CBCentralManager alloc] initWithDelegate:self queue:nil options:@{ CBCentralManagerOptionShowPowerAlertKey: @NO }];
    self.peripheralManager = [[CBPeripheralManager alloc] initWithDelegate:self queue:nil options:nil];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopScanSilently:NO];
}

#pragma mark - UI

- (UIButton *)ls_buttonWithTitle:(NSString *)title tint:(UIColor *)tint action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:tint forState:UIControlStateNormal];
    button.tintColor = tint;
    button.titleLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightBlack];
    button.backgroundColor = [[UIColor colorWithRed:0.02 green:0.17 blue:0.24 alpha:1.0] colorWithAlphaComponent:0.96];
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
    button.titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightBlack];
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
    [close setTitleColor:[UIColor colorWithRed:0.0 green:0.72 blue:0.95 alpha:1.0] forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightBold];
    [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:close];

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"مسح البلوتوث 📡";
    title.font = [UIFont systemFontOfSize:24.0 weight:UIFontWeightBlack];
    title.textColor = UIColor.whiteColor;
    title.textAlignment = NSTextAlignmentCenter;
    [panel addSubview:title];

    self.radarView = [[LSBluetoothRadarView alloc] init];
    self.radarView.translatesAutoresizingMaskIntoConstraints = NO;
    [panel addSubview:self.radarView];

    self.broadcastLabel = [[UILabel alloc] init];
    self.broadcastLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.broadcastLabel.text = @"اضغط مسح لاكتشاف الأجهزة";
    self.broadcastLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightBlack];
    self.broadcastLabel.textColor = [UIColor colorWithRed:0.0 green:0.72 blue:0.95 alpha:1.0];
    self.broadcastLabel.textAlignment = NSTextAlignmentCenter;
    [panel addSubview:self.broadcastLabel];

    self.scanButton = [self ls_buttonWithTitle:@"ابدأ المسح 🔍" tint:[UIColor colorWithRed:0.0 green:0.72 blue:0.95 alpha:1.0] action:@selector(scanTapped)];
    [panel addSubview:self.scanButton];

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
    self.statusLabel.text = @"جاري تجهيز البلوتوث…";
    self.statusLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    self.statusLabel.textColor = UIColor.secondaryLabelColor;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
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

        [self.broadcastLabel.topAnchor constraintEqualToAnchor:self.radarView.bottomAnchor constant:8.0],
        [self.broadcastLabel.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:24.0],
        [self.broadcastLabel.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-24.0],

        [self.scanButton.topAnchor constraintEqualToAnchor:self.broadcastLabel.bottomAnchor constant:8.0],
        [self.scanButton.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:22.0],
        [self.scanButton.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-22.0],

        [self.modeControl.topAnchor constraintEqualToAnchor:self.scanButton.bottomAnchor constant:12.0],
        [self.modeControl.leadingAnchor constraintEqualToAnchor:self.scanButton.leadingAnchor],
        [self.modeControl.trailingAnchor constraintEqualToAnchor:self.scanButton.trailingAnchor],
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
    [self refreshBroadcastStatus];
}

- (void)scanTapped {
    self.isScanning ? [self stopScanSilently:NO] : [self startScanIfPossible];
}

- (void)saveButtonTapped:(UIButton *)sender {
    NSInteger index = sender.tag;
    if (index < 0 || index >= (NSInteger)self.discoveredDevices.count) { return; }
    NSDictionary<NSString *, id> *device = [self normalizedDevice:self.discoveredDevices[index]];
    if (!device) { self.statusLabel.text = @"تعذر حفظ الجهاز: بيانات البلوتوث غير مكتملة."; return; }
    [self saveDevice:device];
    self.modeControl.selectedSegmentIndex = 1;
    [self.tableView reloadData];
    NSString *name = [self displayNameForDevice:device];
    self.statusLabel.text = [NSString stringWithFormat:@"تم حفظ %@", name];
    [self refreshBroadcastStatus];
}

- (void)broadcastButtonTapped:(UIButton *)sender {
    NSInteger index = sender.tag;
    if (index < 0 || index >= (NSInteger)self.savedDevices.count) { return; }
    NSDictionary<NSString *, id> *device = self.savedDevices[index];
    NSString *identifier = [device[@"identifier"] isKindOfClass:NSString.class] ? device[@"identifier"] : @"";
    if (identifier.length > 0 && [self.activeBroadcastIdentifier isEqualToString:identifier]) {
        [self stopBroadcasting];
    } else {
        [self startBroadcastingDevice:device];
    }
}

#pragma mark - Persistence

- (nullable NSDictionary<NSString *, id> *)normalizedDevice:(NSDictionary<NSString *, id> *)device {
    if (![device isKindOfClass:NSDictionary.class]) { return nil; }

    NSString *(^cleanString)(id) = ^NSString *(id value) {
        if (![value isKindOfClass:NSString.class]) { return @""; }
        return [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    };

    NSString *identifier = cleanString(device[@"identifier"]);
    if (identifier.length == 0) { return nil; }

    NSMutableArray<NSString *> *serviceUUIDs = [NSMutableArray array];
    NSArray *rawUUIDs = [device[@"serviceUUIDs"] isKindOfClass:NSArray.class] ? device[@"serviceUUIDs"] : @[];
    for (id item in rawUUIDs) {
        NSString *uuid = cleanString(item);
        if (uuid.length > 0 && ![serviceUUIDs containsObject:uuid]) {
            [serviceUUIDs addObject:uuid];
        }
        if (serviceUUIDs.count >= 8) { break; }
    }

    NSNumber *rssi = [device[@"rssi"] isKindOfClass:NSNumber.class] ? device[@"rssi"] : @0;
    NSString *manufacturerHex = cleanString(device[@"manufacturerHex"]);
    if (manufacturerHex.length > 512) {
        manufacturerHex = [manufacturerHex substringToIndex:512];
    }

    return @{
        @"identifier": identifier,
        @"name": cleanString(device[@"name"]),
        @"localName": cleanString(device[@"localName"]),
        @"rssi": rssi ?: @0,
        @"serviceUUIDs": serviceUUIDs,
        @"manufacturerHex": manufacturerHex ?: @"",
        @"lastSeen": [device[@"lastSeen"] isKindOfClass:NSNumber.class] ? device[@"lastSeen"] : @([[NSDate date] timeIntervalSince1970])
    };
}

- (NSArray<NSDictionary<NSString *, id> *> *)sanitizedDevicesFromArray:(NSArray *)devices {
    NSMutableArray<NSDictionary<NSString *, id> *> *cleanDevices = [NSMutableArray array];
    NSMutableSet<NSString *> *seenIdentifiers = [NSMutableSet set];
    for (id item in devices) {
        NSDictionary<NSString *, id> *device = [self normalizedDevice:item];
        if (!device) { continue; }
        NSString *identifier = [device[@"identifier"] isKindOfClass:NSString.class] ? device[@"identifier"] : @"";
        if (identifier.length == 0 || [seenIdentifiers containsObject:identifier]) { continue; }
        [cleanDevices addObject:device];
        [seenIdentifiers addObject:identifier];
    }
    return cleanDevices;
}

- (void)saveDevice:(NSDictionary<NSString *, id> *)device {
    NSDictionary<NSString *, id> *cleanDevice = [self normalizedDevice:device];
    if (!cleanDevice) { return; }
    NSString *identifier = [cleanDevice[@"identifier"] isKindOfClass:NSString.class] ? cleanDevice[@"identifier"] : @"";
    if (identifier.length == 0) { return; }

    NSUInteger existingIndex = [self.savedDevices indexOfObjectPassingTest:^BOOL(NSDictionary<NSString *,id> *obj, NSUInteger idx, BOOL *stop) {
        (void)idx;
        NSString *candidate = [obj[@"identifier"] isKindOfClass:NSString.class] ? obj[@"identifier"] : @"";
        BOOL match = [candidate isEqualToString:identifier];
        if (match) { *stop = YES; }
        return match;
    }];
    if (existingIndex == NSNotFound) {
        [self.savedDevices insertObject:cleanDevice atIndex:0];
    } else {
        [self.savedDevices replaceObjectAtIndex:existingIndex withObject:cleanDevice];
    }
    [self persistSavedDevices];
}

- (void)persistSavedDevices {
    NSArray<NSDictionary<NSString *, id> *> *payload = [self sanitizedDevicesFromArray:self.savedDevices];
    self.savedDevices = [payload mutableCopy] ?: [NSMutableArray array];
    [[NSUserDefaults standardUserDefaults] setObject:payload forKey:kLSBluetoothSavedDevicesKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark - Helpers

- (NSString *)displayNameForDevice:(NSDictionary<NSString *, id> *)device {
    NSString *name = [device[@"name"] isKindOfClass:NSString.class] ? device[@"name"] : @"";
    if (name.length == 0) {
        name = [device[@"localName"] isKindOfClass:NSString.class] ? device[@"localName"] : @"";
    }
    return name.length ? name : @"Unknown";
}

- (NSString *)hexStringFromData:(NSData *)data {
    if (![data isKindOfClass:NSData.class] || data.length == 0) { return @""; }
    const unsigned char *bytes = data.bytes;
    NSMutableString *hex = [NSMutableString stringWithCapacity:data.length * 3];
    for (NSUInteger i = 0; i < data.length; i++) {
        [hex appendFormat:@"%02X", bytes[i]];
        if (i + 1 < data.length) { [hex appendString:@" "]; }
    }
    return hex;
}

- (NSArray<NSString *> *)uuidStringsFromAdvertisement:(NSDictionary<NSString *, id> *)advertisementData {
    NSArray<CBUUID *> *serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey];
    if (![serviceUUIDs isKindOfClass:NSArray.class]) { return @[]; }
    NSMutableArray<NSString *> *strings = [NSMutableArray array];
    for (CBUUID *uuid in serviceUUIDs) {
        if (![uuid isKindOfClass:CBUUID.class]) { continue; }
        NSString *value = uuid.UUIDString;
        if (value.length > 0 && ![strings containsObject:value]) {
            [strings addObject:value];
        }
    }
    return strings;
}

- (CGFloat)radiusFactorForRSSI:(NSNumber *)RSSI {
    double value = RSSI.doubleValue;
    if (value >= -35.0) { return 0.20; }
    if (value <= -100.0) { return 0.95; }
    return 0.20 + ((fabs(value) - 35.0) / 65.0) * 0.75;
}

- (void)addRadarPointForIdentifier:(NSString *)identifier RSSI:(NSNumber *)RSSI {
    if (identifier.length == 0) { return; }
    NSUInteger hash = identifier.hash;
    CGFloat angle = ((CGFloat)(hash % 628)) / 100.0;
    CGFloat radius = [self radiusFactorForRSSI:RSSI];
    NSDictionary *point = @{ @"angle": @(angle), @"radius": @(radius) };

    NSUInteger existingIndex = [self.radarPoints indexOfObjectPassingTest:^BOOL(NSDictionary<NSString *,NSNumber *> *obj, NSUInteger idx, BOOL *stop) {
        (void)obj;
        if (idx < self.discoveredDevices.count) {
            NSString *candidate = [self.discoveredDevices[idx][@"identifier"] description];
            if ([candidate isEqualToString:identifier]) { *stop = YES; return YES; }
        }
        return NO;
    }];
    if (existingIndex == NSNotFound || existingIndex >= self.radarPoints.count) {
        if (self.radarPoints.count >= 24) { [self.radarPoints removeLastObject]; }
        [self.radarPoints addObject:point];
    } else {
        [self.radarPoints replaceObjectAtIndex:existingIndex withObject:point];
    }
    self.radarView.points = self.radarPoints;
}

#pragma mark - Scanning

- (void)startScanIfPossible {
    CBManagerState state = self.centralManager.state;
    if (state == CBManagerStatePoweredOn) {
        [self.discoveredDevices removeAllObjects];
        [self.radarPoints removeAllObjects];
        self.radarView.points = @[];
        self.isScanning = YES;
        self.statusLabel.text = @"جاري البحث عن أجهزة BLE القريبة…";
        self.broadcastLabel.text = @"المسح يعمل الآن ⬜";
        [self.scanButton setTitle:@"إيقاف المسح ⬜" forState:UIControlStateNormal];
        [self.centralManager scanForPeripheralsWithServices:nil options:@{ CBCentralManagerScanOptionAllowDuplicatesKey: @YES }];
        [self.tableView reloadData];
        return;
    }

    if (state == CBManagerStateUnauthorized) {
        self.statusLabel.text = @"لا توجد صلاحية للبلوتوث.";
    } else if (state == CBManagerStatePoweredOff) {
        self.statusLabel.text = @"البلوتوث مغلق. فعّله ثم حاول مرة أخرى.";
    } else if (state == CBManagerStateUnsupported) {
        self.statusLabel.text = @"هذا الجهاز لا يدعم Bluetooth LE.";
    } else {
        self.statusLabel.text = @"جاري تجهيز البلوتوث… انتظر لحظة.";
    }
}

- (void)stopScanSilently:(BOOL)silent {
    if (!self.isScanning) { return; }
    [self.centralManager stopScan];
    self.isScanning = NO;
    [self.scanButton setTitle:@"ابدأ المسح 🔍" forState:UIControlStateNormal];
    if (!silent) {
        self.statusLabel.text = @"تم إيقاف المسح.";
    }
    [self refreshBroadcastStatus];
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    (void)central;
    switch (self.centralManager.state) {
        case CBManagerStatePoweredOn:
            self.statusLabel.text = @"البلوتوث جاهز للمسح والحفظ.";
            self.scanButton.enabled = YES;
            break;
        case CBManagerStatePoweredOff:
            self.statusLabel.text = @"البلوتوث مغلق.";
            self.scanButton.enabled = NO;
            [self stopScanSilently:YES];
            break;
        case CBManagerStateUnauthorized:
            self.statusLabel.text = @"اسمح للتطبيق باستخدام البلوتوث من الإعدادات.";
            self.scanButton.enabled = NO;
            break;
        case CBManagerStateUnsupported:
            self.statusLabel.text = @"هذا الجهاز لا يدعم Bluetooth LE.";
            self.scanButton.enabled = NO;
            break;
        default:
            self.statusLabel.text = @"البلوتوث غير جاهز حاليًا.";
            self.scanButton.enabled = NO;
            break;
    }
}

- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary<NSString *,id> *)advertisementData RSSI:(NSNumber *)RSSI {
    (void)central;
    NSString *identifier = peripheral.identifier.UUIDString ?: @"";
    if (identifier.length == 0) { return; }

    NSString *localName = [advertisementData[CBAdvertisementDataLocalNameKey] isKindOfClass:NSString.class] ? advertisementData[CBAdvertisementDataLocalNameKey] : @"";
    NSString *name = peripheral.name.length ? peripheral.name : localName;
    NSData *manufacturerData = [advertisementData[CBAdvertisementDataManufacturerDataKey] isKindOfClass:NSData.class] ? advertisementData[CBAdvertisementDataManufacturerDataKey] : nil;
    NSArray<NSString *> *serviceUUIDs = [self uuidStringsFromAdvertisement:advertisementData];

    NSDictionary<NSString *, id> *device = @{
        @"identifier": identifier,
        @"name": name ?: @"",
        @"localName": localName ?: @"",
        @"rssi": RSSI ?: @(0),
        @"serviceUUIDs": serviceUUIDs ?: @[],
        @"manufacturerHex": manufacturerData ? [self hexStringFromData:manufacturerData] : @"",
        @"lastSeen": @([[NSDate date] timeIntervalSince1970])
    };

    NSUInteger existingIndex = [self.discoveredDevices indexOfObjectPassingTest:^BOOL(NSDictionary<NSString *,id> *obj, NSUInteger idx, BOOL *stop) {
        (void)idx;
        BOOL match = [[obj[@"identifier"] description] isEqualToString:identifier];
        if (match) { *stop = YES; }
        return match;
    }];
    if (existingIndex == NSNotFound) {
        [self.discoveredDevices addObject:device];
    } else {
        [self.discoveredDevices replaceObjectAtIndex:existingIndex withObject:device];
    }

    [self addRadarPointForIdentifier:identifier RSSI:RSSI ?: @(0)];
    [LSBluetoothLogManager recordName:name identifier:identifier rssi:RSSI ?: @(0)];
    self.statusLabel.text = [NSString stringWithFormat:@"تم التقاط %lu جهاز.", (unsigned long)self.discoveredDevices.count];
    if (self.modeControl.selectedSegmentIndex == 0) { [self.tableView reloadData]; }
}

#pragma mark - Broadcasting

- (NSString *)shortenedLocalName:(NSString *)name {
    NSString *clean = name.length ? name : @"XsGpS-BLE";
    if (clean.length > 18) {
        return [[clean substringToIndex:18] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }
    return clean;
}

- (nullable CBUUID *)safeCBUUIDFromString:(NSString *)string {
    if (![string isKindOfClass:NSString.class] || string.length == 0) { return nil; }
    CBUUID *uuid = nil;
    @try {
        uuid = [CBUUID UUIDWithString:string];
    } @catch (__unused NSException *exception) {
        uuid = nil;
    }
    return uuid;
}

- (NSArray<CBUUID *> *)advertisableServiceUUIDsForDevice:(NSDictionary<NSString *, id> *)device {
    NSMutableArray<CBUUID *> *uuids = [NSMutableArray array];
    NSArray *strings = [device[@"serviceUUIDs"] isKindOfClass:NSArray.class] ? device[@"serviceUUIDs"] : @[];
    for (id item in strings) {
        if (![item isKindOfClass:NSString.class]) { continue; }
        CBUUID *uuid = [self safeCBUUIDFromString:item];
        if (uuid) { [uuids addObject:uuid]; }
        if (uuids.count >= 1) { break; }
    }

    if (uuids.count == 0) {
        NSString *identifier = [device[@"identifier"] isKindOfClass:NSString.class] ? device[@"identifier"] : @"";
        CBUUID *fallback = [self safeCBUUIDFromString:identifier];
        if (fallback) { [uuids addObject:fallback]; }
    }
    return uuids;
}

- (void)startBroadcastingDevice:(NSDictionary<NSString *, id> *)device {
    NSDictionary<NSString *, id> *cleanDevice = [self normalizedDevice:device];
    if (!cleanDevice) {
        self.statusLabel.text = @"تعذر بث الجهاز: البيانات المحفوظة غير صالحة.";
        return;
    }
    NSString *identifier = [cleanDevice[@"identifier"] isKindOfClass:NSString.class] ? cleanDevice[@"identifier"] : @"";
    if (identifier.length == 0) {
        self.statusLabel.text = @"تعذر بث الجهاز: لا يوجد معرف صالح.";
        return;
    }

    CBManagerState state = self.peripheralManager.state;
    if (state == CBManagerStateUnknown || state == CBManagerStateResetting) {
        self.pendingBroadcastDevice = cleanDevice;
        self.statusLabel.text = @"جاري تجهيز بث البلوتوث…";
        return;
    }
    if (state != CBManagerStatePoweredOn) {
        if (state == CBManagerStateUnauthorized) {
            self.statusLabel.text = @"لا توجد صلاحية لبث البلوتوث.";
        } else if (state == CBManagerStatePoweredOff) {
            self.statusLabel.text = @"البلوتوث مغلق. فعّله لتشغيل البث.";
        } else if (state == CBManagerStateUnsupported) {
            self.statusLabel.text = @"هذا الجهاز لا يدعم بث Bluetooth LE.";
        } else {
            self.statusLabel.text = @"بث البلوتوث غير جاهز حاليًا.";
        }
        return;
    }

    [self.peripheralManager stopAdvertising];
    NSArray<CBUUID *> *serviceUUIDs = [self advertisableServiceUUIDsForDevice:cleanDevice];
    NSString *localName = [self shortenedLocalName:[self displayNameForDevice:cleanDevice]];
    NSMutableDictionary<NSString *, id> *advertisementData = [NSMutableDictionary dictionary];
    if (localName.length > 0) { advertisementData[CBAdvertisementDataLocalNameKey] = localName; }
    if (serviceUUIDs.count > 0) { advertisementData[CBAdvertisementDataServiceUUIDsKey] = serviceUUIDs; }
    if (advertisementData.count == 0) {
        self.statusLabel.text = @"تعذر البث: لا يوجد اسم أو Service UUID صالح لهذا الجهاز.";
        return;
    }

    self.activeBroadcastIdentifier = identifier;
    [self.peripheralManager startAdvertising:advertisementData];
    [self refreshBroadcastStatus];
    [self.tableView reloadData];
}

- (void)stopBroadcasting {
    [self.peripheralManager stopAdvertising];
    self.pendingBroadcastDevice = nil;
    self.activeBroadcastIdentifier = nil;
    self.statusLabel.text = @"تم إيقاف بث الإشارة.";
    [self refreshBroadcastStatus];
    [self.tableView reloadData];
}

- (void)refreshBroadcastStatus {
    if (self.activeBroadcastIdentifier.length == 0) {
        if (!self.isScanning) {
            self.broadcastLabel.text = self.savedDevices.count ? @"اختر جهاز محفوظ ثم اضغط بث 📡" : @"اضغط مسح لاكتشاف الأجهزة";
        }
        return;
    }

    NSDictionary<NSString *, id> *activeDevice = nil;
    for (NSDictionary<NSString *, id> *device in self.savedDevices) {
        NSString *identifier = [device[@"identifier"] isKindOfClass:NSString.class] ? device[@"identifier"] : @"";
        if ([identifier isEqualToString:self.activeBroadcastIdentifier]) {
            activeDevice = device;
            break;
        }
    }
    NSString *name = activeDevice ? [self displayNameForDevice:activeDevice] : self.activeBroadcastIdentifier;
    self.broadcastLabel.text = [NSString stringWithFormat:@"يبث: %@ 📡", name];
}

- (void)peripheralManagerDidUpdateState:(CBPeripheralManager *)peripheral {
    (void)peripheral;
    if (self.peripheralManager.state == CBManagerStatePoweredOn) {
        if (self.pendingBroadcastDevice) {
            NSDictionary<NSString *, id> *device = self.pendingBroadcastDevice;
            self.pendingBroadcastDevice = nil;
            [self startBroadcastingDevice:device];
        } else {
            [self refreshBroadcastStatus];
        }
        return;
    }

    if (self.peripheralManager.state == CBManagerStatePoweredOff || self.peripheralManager.state == CBManagerStateUnauthorized || self.peripheralManager.state == CBManagerStateUnsupported) {
        if (self.activeBroadcastIdentifier.length > 0) {
            self.activeBroadcastIdentifier = nil;
            [self.tableView reloadData];
        }
    }
}

- (void)peripheralManagerDidStartAdvertising:(CBPeripheralManager *)peripheral error:(NSError *)error {
    (void)peripheral;
    if (error) {
        self.statusLabel.text = [NSString stringWithFormat:@"تعذر تشغيل البث: %@", error.localizedDescription ?: @"خطأ غير معروف"];
        self.activeBroadcastIdentifier = nil;
        [self refreshBroadcastStatus];
        [self.tableView reloadData];
        return;
    }
    self.statusLabel.text = @"تم تفعيل بث الإشارة المحفوظة.";
    [self refreshBroadcastStatus];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return self.modeControl.selectedSegmentIndex == 0 ? self.discoveredDevices.count : self.savedDevices.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"BluetoothDeviceCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"BluetoothDeviceCell"];
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
    UIImage *deviceImage = [UIImage systemImageNamed:@"dot.radiowaves.left.and.right"];
    if (!deviceImage) { deviceImage = [UIImage systemImageNamed:@"antenna.radiowaves.left.and.right"]; }
    cell.imageView.image = deviceImage;
    cell.imageView.tintColor = [UIColor colorWithRed:0.0 green:0.72 blue:1.0 alpha:1.0];

    BOOL savedMode = self.modeControl.selectedSegmentIndex == 1;
    NSDictionary<NSString *, id> *device = savedMode ? self.savedDevices[indexPath.row] : self.discoveredDevices[indexPath.row];
    NSString *name = [self displayNameForDevice:device];
    NSString *identifier = [device[@"identifier"] isKindOfClass:NSString.class] ? device[@"identifier"] : @"";
    NSNumber *rssi = [device[@"rssi"] isKindOfClass:NSNumber.class] ? device[@"rssi"] : @0;
    NSString *manufacturer = [device[@"manufacturerHex"] isKindOfClass:NSString.class] ? device[@"manufacturerHex"] : @"";
    NSArray *serviceUUIDs = [device[@"serviceUUIDs"] isKindOfClass:NSArray.class] ? device[@"serviceUUIDs"] : @[];

    cell.textLabel.text = name;
    NSString *firstLine = manufacturer.length ? manufacturer : (serviceUUIDs.count ? [[serviceUUIDs valueForKey:@"description"] componentsJoinedByString:@", "] : identifier);
    if (firstLine.length > 28) { firstLine = [[firstLine substringToIndex:28] stringByAppendingString:@"…"]; }
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@\n%@ dBm", firstLine, rssi];

    if (savedMode) {
        BOOL active = identifier.length > 0 && [identifier isEqualToString:self.activeBroadcastIdentifier];
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
    if (self.modeControl.selectedSegmentIndex == 0 && self.discoveredDevices.count == 0) {
        return @"ابدأ المسح، وبعد ظهور الجهاز اضغط حفظ.";
    }
    if (self.modeControl.selectedSegmentIndex == 1 && self.savedDevices.count == 0) {
        return @"لا توجد أجهزة محفوظة حتى الآن.";
    }
    return nil;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary<NSString *, id> *device = self.modeControl.selectedSegmentIndex == 0 ? self.discoveredDevices[indexPath.row] : self.savedDevices[indexPath.row];
    NSString *identifier = [device[@"identifier"] isKindOfClass:NSString.class] ? device[@"identifier"] : @"";
    if (identifier.length == 0) { return; }
    UIPasteboard.generalPasteboard.string = identifier;
    self.statusLabel.text = @"تم نسخ معرّف الجهاز إلى الحافظة.";
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.modeControl.selectedSegmentIndex != 1 || editingStyle != UITableViewCellEditingStyleDelete) { return; }
    NSDictionary<NSString *, id> *device = self.savedDevices[indexPath.row];
    NSString *identifier = [device[@"identifier"] isKindOfClass:NSString.class] ? device[@"identifier"] : @"";
    if (identifier.length > 0 && [identifier isEqualToString:self.activeBroadcastIdentifier]) {
        [self stopBroadcasting];
    }
    [self.savedDevices removeObjectAtIndex:indexPath.row];
    [self persistSavedDevices];
    [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    [self refreshBroadcastStatus];
}

@end
