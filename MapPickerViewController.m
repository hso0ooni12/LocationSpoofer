#import "MapPickerViewController.h"
#import "MapPickerViewController+Private.h"
#import "LocationSpoofer.h"
#import "OverlayWindow.h"
#import "PersistenceManager.h"
#import "RouteSimulator.h"
#import "LSBluetoothManager.h" // 👈 إضافة مدير البلوتوث الجديد

#import <CoreLocation/CoreLocation.h>
#import <MapKit/MapKit.h>
#import <CommonCrypto/CommonDigest.h>

static const CGFloat kLSCornerRadius = 16.0;
static const CGFloat kLSHorizontalInset = 20.0;
static const CGFloat kLSControlPanelCornerRadius = 16.0;
static const CGFloat kLSSuggestionRowHeight = 48.0;
static const CGFloat kLSSuggestionMaxHeight = 240.0;
static const NSInteger kLSSuggestionMaxVisibleRows = 5;
static const CGFloat kLSMapHeightMultiplier = 0.30;

// تعريف قيم النوافذ (Tabs) الجديدة
typedef NS_ENUM(NSInteger, LSMapPickerPanelTab) {
    LSMapPickerPanelTabMap = 0,
    LSMapPickerPanelTabBookmarks = 1,
    LSMapPickerPanelTabBluetooth = 2 // 👈 نافذة البلوتوث المضافة
};

@interface MapPickerViewController () <MKMapViewDelegate, UISearchBarDelegate, UITextFieldDelegate, MKLocalSearchCompleterDelegate, UITableViewDataSource, UITableViewDelegate, LSBluetoothManagerDelegate>

// عناصر واجهة البلوتوث المضافة حديثاً
@property (nonatomic, strong) UIView *bluetoothControlsContainer;
@property (nonatomic, strong) UIButton *bluetoothScanButton;
@property (nonatomic, strong) UITableView *bluetoothTableView;
@property (nonatomic, strong) UILabel *bluetoothStatusLabel;
@property (nonatomic, strong) NSArray<NSDictionary *> *btDevices;

@end

@implementation MapPickerViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.selectedCoordinate = CLLocationCoordinate2DMake(37.7749, -122.4194);
    self.hasSelectedCoordinate = NO;

    PersistenceManager *store = [PersistenceManager shared];
    if ([store isSpoofingEnabled] || [store hasStoredCoordinate]) {
        self.selectedCoordinate = [store spoofCoordinate];
        self.hasSelectedCoordinate = YES;
    }
    self.panelTab = LSMapPickerPanelTabMap;
    self.coordinateMode = LSMapPickerCoordinateModeStatic;
    self.btDevices = @[];

    [self buildInterface];
    [self buildRouteControls];
    [self buildBookmarksPanel];
    [self buildBluetoothPanel]; // 👈 بناء نافذة البلوتوث
    [self installConstraints];
    [self configureKeyboardToolbar];
    [self configureSearchCompleter];
    [self restoreSimulationUIIfNeeded];
    [self refreshStatusPill];
    [self syncFieldsFromCoordinate];
    self.altitudeField.text = [NSString stringWithFormat:@"%.0f", store.altitude];
    self.headingSlider.value = (float)store.heading;
    [self updateHeadingLabel];
    [self updatePanelTabVisibility];

    [self syncFluctuationUI];
    
    [LSBluetoothManager sharedManager].delegate = self; // ربط أحداث البلوتوث

    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(ls_keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(ls_keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    LSSetHooksBypassed(YES);
    [LSOverlayManager setMapPickerVisible:YES];
    [self refreshStatusPill];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    LSSetHooksBypassed(YES);
    [self configureMapIfNeeded];
    [self checkActivation]; 
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[LSBluetoothManager sharedManager] stopScanning]; // إيقاف الفحص عند الخروج للسلامة
    [LSOverlayManager restoreMapPickerSessionState];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [LSOverlayManager restoreMapPickerSessionState];
}

#pragma mark - Interface

- (void)buildInterface {
    self.contentScrollView = [[UIScrollView alloc] init];
    self.contentScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentScrollView.alwaysBounceVertical = YES;
    self.contentScrollView.showsVerticalScrollIndicator = YES;
    self.contentScrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.contentScrollView.clipsToBounds = NO;
    [self.view addSubview:self.contentScrollView];

    self.scrollContentView = [[UIView alloc] init];
    self.scrollContentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentScrollView addSubview:self.scrollContentView];

    [self buildHeader];
    [self buildSearchBar];
    [self buildMapSection];
    [self buildControlPanel];
}

- (void)buildHeader {
    self.headerView = [[UIView alloc] init];
    self.headerView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollContentView addSubview:self.headerView];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.text = @"مزيّف الموقع والبلوتوث";
    self.titleLabel.font = [UIFont systemFontOfSize:26.0 weight:UIFontWeightBold];
    self.titleLabel.textColor = UIColor.labelColor;
    [self.headerView addSubview:self.titleLabel];

    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.subtitleLabel.text = @"اختر موقعك الجغرافي أو انسخ وقم بمحاكاة البلوتوث عن بعد";
    self.subtitleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
    self.subtitleLabel.textColor = UIColor.secondaryLabelColor;
    self.subtitleLabel.numberOfLines = 2;
    [self.headerView addSubview:self.subtitleLabel];

    self.statusPill = [[UIView alloc] init];
    self.statusPill.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusPill.backgroundColor = [UIColor.tertiarySystemFillColor colorWithAlphaComponent:0.9];
    self.statusPill.layer.cornerRadius = 14.0;
    self.statusPill.layer.cornerCurve = kCACornerCurveContinuous;
    self.statusPill.userInteractionEnabled = YES;
    [self.headerView addSubview:self.statusPill];

    self.statusDot = [[UIView alloc] init];
    self.statusDot.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusDot.layer.cornerRadius = 5.0;
    [self.statusPill addSubview:self.statusDot];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    self.statusLabel.textColor = UIColor.secondaryLabelColor;
    [self.statusPill addSubview:self.statusLabel];

    self.pillStopLabel = [[UILabel alloc] init];
    self.pillStopLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.pillStopLabel.text = @"إيقاف";
    self.pillStopLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
    self.pillStopLabel.textColor = UIColor.systemRedColor;
    self.pillStopLabel.hidden = YES;
    [self.statusPill addSubview:self.pillStopLabel];

    UITapGestureRecognizer *pillTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleStatusPillTapped)];
    [self.statusPill addGestureRecognizer:pillTap];

    self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    UIImage *closeImage = [UIImage systemImageNamed:@"xmark.circle.fill"];
    [self.closeButton setImage:closeImage forState:UIControlStateNormal];
    self.closeButton.tintColor = UIColor.tertiaryLabelColor;
    [self.closeButton addTarget:self action:@selector(handleCancel) forControlEvents:UIControlEventTouchUpInside];
    [self.headerView addSubview:self.closeButton];
}

- (void)buildSearchBar {
    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchBar.placeholder = @"ابحث عن مدينة أو عنوان أو معلم";
    self.searchBar.delegate = self;
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    [self.scrollContentView addSubview:self.searchBar];

    self.searchSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.searchSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchSpinner.hidesWhenStopped = YES;
    [self.scrollContentView addSubview:self.searchSpinner];

    [self buildSearchSuggestions];
}

- (void)buildSearchSuggestions {
    self.suggestionsPanel = [[UIView alloc] init];
    self.suggestionsPanel.translatesAutoresizingMaskIntoConstraints = NO;
    self.suggestionsPanel.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.suggestionsPanel.layer.cornerRadius = kLSCornerRadius;
    self.suggestionsPanel.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.suggestionsPanel.layer.borderColor = UIColor.separatorColor.CGColor;
    self.suggestionsPanel.hidden = YES;
    self.suggestionsPanel.alpha = 0.0;
    [self.scrollContentView addSubview:self.suggestionsPanel];

    self.suggestionsTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.suggestionsTableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.suggestionsTableView.dataSource = self;
    self.suggestionsTableView.delegate = self;
    self.suggestionsTableView.rowHeight = kLSSuggestionRowHeight;
    [self.suggestionsTableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"LSSearchSuggestionCell"];
    [self.suggestionsPanel addSubview:self.suggestionsTableView];
}

- (void)configureSearchCompleter {
    self.searchCompletions = @[];
    self.searchCompleter = [[MKLocalSearchCompleter alloc] init];
    self.searchCompleter.delegate = self;
}

- (void)buildMapSection {
    self.mapContainer = [[UIView alloc] init];
    self.mapContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.mapContainer.layer.cornerRadius = kLSCornerRadius;
    self.mapContainer.clipsToBounds = YES;
    self.mapContainer.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.mapContainer.layer.borderColor = UIColor.separatorColor.CGColor;
    [self.scrollContentView addSubview:self.mapContainer];

    self.mapView = [[MKMapView alloc] initWithFrame:CGRectZero];
    self.mapView.translatesAutoresizingMaskIntoConstraints = NO;
    self.mapView.delegate = self;
    [self.mapContainer addSubview:self.mapView];

    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleMapTap:)];
    [self.mapView addGestureRecognizer:tapGesture];

    self.mapHintLabel = [[UILabel alloc] init];
    self.mapHintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.mapHintLabel.text = @"  اضغط على الخريطة لتحديد الموقع الجغرافي  ";
    self.mapHintLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    self.mapHintLabel.textColor = UIColor.labelColor;
    self.mapHintLabel.backgroundColor = [UIColor.secondarySystemBackgroundColor colorWithAlphaComponent:0.92];
    self.mapHintLabel.layer.cornerRadius = 12.0;
    self.mapHintLabel.clipsToBounds = YES;
    [self.mapContainer addSubview:self.mapHintLabel];

    self.mapSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.mapSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.mapSpinner.hidesWhenStopped = YES;
    [self.mapContainer addSubview:self.mapSpinner];
}

- (void)buildControlPanel {
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial];
    self.controlPanel = [[UIVisualEffectView alloc] initWithEffect:blur];
    self.controlPanel.translatesAutoresizingMaskIntoConstraints = NO;
    self.controlPanel.layer.cornerRadius = kLSControlPanelCornerRadius;
    self.controlPanel.clipsToBounds = YES;
    [self.scrollContentView addSubview:self.controlPanel];

    UIView *content = self.controlPanel.contentView;

    // 👈 تحديث القائمة لتشمل ثلاثة خيارات (الخريطة، المحفوظات، البلوتوث)
    self.panelTabSegment = [[UISegmentedControl alloc] initWithItems:@[@"الخريطة", @"المحفوظات", @"البلوتوث"]];
    self.panelTabSegment.translatesAutoresizingMaskIntoConstraints = NO;
    self.panelTabSegment.selectedSegmentIndex = LSMapPickerPanelTabMap;
    [self.panelTabSegment addTarget:self action:@selector(handlePanelTabChanged:) forControlEvents:UIControlEventValueChanged];
    [content addSubview:self.panelTabSegment];

    self.mapControlsContainer = [[UIView alloc] init];
    self.mapControlsContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:self.mapControlsContainer];

    self.staticControlsContainer = [[UIView alloc] init];
    self.staticControlsContainer.translatesAutoresizingMaskIntoConstraints = NO;

    self.routeControlsContainer = [[UIView alloc] init];
    self.routeControlsContainer.translatesAutoresizingMaskIntoConstraints = NO;

    self.mapControlsStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.staticControlsContainer, self.routeControlsContainer]];
    self.mapControlsStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.mapControlsStack.axis = UILayoutConstraintAxisVertical;
    self.mapControlsStack.spacing = 12.0;

    self.coordinateModeSegment = [[UISegmentedControl alloc] initWithItems:@[@"ثابت", @"مسار"]];
    self.coordinateModeSegment.translatesAutoresizingMaskIntoConstraints = NO;
    self.coordinateModeSegment.selectedSegmentIndex = LSMapPickerCoordinateModeStatic;
    [self.coordinateModeSegment addTarget:self action:@selector(handleCoordinateModeChanged:) forControlEvents:UIControlEventValueChanged];
    [self.mapControlsContainer addSubview:self.coordinateModeSegment];
    [self.mapControlsContainer addSubview:self.mapControlsStack];

    UIView *staticPanel = self.staticControlsContainer;

    self.coordinateTitleLabel = [[UILabel alloc] init];
    self.coordinateTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.coordinateTitleLabel.text = @"الإحداثيات المحددة";
    self.coordinateTitleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    self.coordinateTitleLabel.textColor = UIColor.secondaryLabelColor;
    [staticPanel addSubview:self.coordinateTitleLabel];

    self.coordinateValueLabel = [[UILabel alloc] init];
    self.coordinateValueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.coordinateValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:14.0 weight:UIFontWeightMedium];
    self.coordinateValueLabel.textColor = UIColor.labelColor;
    self.coordinateValueLabel.numberOfLines = 2;
    [staticPanel addSubview:self.coordinateValueLabel];

    self.bookmarkSaveButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.bookmarkSaveButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.bookmarkSaveButton setImage:[UIImage systemImageNamed:@"bookmark"] forState:UIControlStateNormal];
    [self.bookmarkSaveButton addTarget:self action:@selector(handleBookmarkSaveTapped) forControlEvents:UIControlEventTouchUpInside];
    [staticPanel addSubview:self.bookmarkSaveButton];

    self.separatorCoordFields = [self ls_separatorView];
    [staticPanel addSubview:self.separatorCoordFields];

    UITextField *latitudeInput = nil;
    UITextField *longitudeInput = nil;
    UIView *latitudeContainer = [self coordinateFieldWithTitle:@"خط العرض" placeholder:@"37.774900" textField:&latitudeInput];
    UIView *longitudeContainer = [self coordinateFieldWithTitle:@"خط الطول" placeholder:@"-122.419400" textField:&longitudeInput];
    self.latitudeField = latitudeInput;
    self.longitudeField = longitudeInput;

    UITextField *altitudeInput = nil;
    UIView *altitudeContainer = [self coordinateFieldWithTitle:@"الارتفاع (م)" placeholder:@"0" textField:&altitudeInput];
    self.altitudeField = altitudeInput;

    self.fieldStack = [[UIStackView alloc] initWithArrangedSubviews:@[latitudeContainer, longitudeContainer, altitudeContainer]];
    self.fieldStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.fieldStack.axis = UILayoutConstraintAxisHorizontal;
    self.fieldStack.spacing = 8.0;
    self.fieldStack.distribution = UIStackViewDistributionFillEqually;
    [staticPanel addSubview:self.fieldStack];

    self.separatorFieldsHeading = [self ls_separatorView];
    [staticPanel addSubview:self.separatorFieldsHeading];

    self.headingValueLabel = [[UILabel alloc] init];
    self.headingValueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.headingValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:14.0 weight:UIFontWeightMedium];
    self.headingValueLabel.textColor = UIColor.secondaryLabelColor;
    [staticPanel addSubview:self.headingValueLabel];

    self.headingSlider = [[UISlider alloc] init];
    self.headingSlider.translatesAutoresizingMaskIntoConstraints = NO;
    self.headingSlider.minimumValue = 0.0f;
    self.headingSlider.maximumValue = 359.0f;
    [self.headingSlider addTarget:self action:@selector(handleHeadingSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [staticPanel addSubview:self.headingSlider];

    self.headingDirectionLabel = [[UILabel alloc] init];
    self.headingDirectionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.headingDirectionLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightRegular];
    self.headingDirectionLabel.textColor = UIColor.tertiaryLabelColor;
    [staticPanel addSubview:self.headingDirectionLabel];

    self.separatorHeadingActions = [self ls_separatorView];
    [staticPanel addSubview:self.separatorHeadingActions];

    self.separatorFluctuation = [self ls_separatorView];
    [staticPanel addSubview:self.separatorFluctuation];

    self.fluctuationRow = [[UIView alloc] init];
    self.fluctuationRow.translatesAutoresizingMaskIntoConstraints = NO;
    [staticPanel addSubview:self.fluctuationRow];

    self.fluctuationLabel = [[UILabel alloc] init];
    self.fluctuationLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.fluctuationLabel.text = @"التذبذب الذكي للموقع";
    self.fluctuationLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
    [self.fluctuationRow addSubview:self.fluctuationLabel];

    self.fluctuationSwitch = [[UISwitch alloc] init];
    self.fluctuationSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [self.fluctuationSwitch addTarget:self action:@selector(handleFluctuationToggle) forControlEvents:UIControlEventValueChanged];
    [self.fluctuationRow addSubview:self.fluctuationSwitch];

    self.fluctuationRadiusField = [[UITextField alloc] init];
    self.fluctuationRadiusField.translatesAutoresizingMaskIntoConstraints = NO;
    self.fluctuationRadiusField.placeholder = @"نصف قطر التذبذب (متر)";
    self.fluctuationRadiusField.keyboardType = UIKeyboardTypeNumberPad;
    self.fluctuationRadiusField.backgroundColor = UIColor.clearColor;
    self.fluctuationRadiusField.delegate = self;
    [self.fluctuationRadiusField addTarget:self action:@selector(handleFluctuationRadiusChanged) forControlEvents:UIControlEventEditingDidEnd];
    [staticPanel addSubview:self.fluctuationRadiusField];

    self.applyButton = [self primaryButtonWithTitle:@"تطبيق الموقع الجغرافي" action:@selector(handleApply)];
    self.cancelButton = [self secondaryButtonWithTitle:@"إلغاء" action:@selector(handleCancel)];
    self.stopButton = [self destructiveOutlineButtonWithTitle:@"إيقاف التزييف بالكامل" action:@selector(handleStopSpoofing)];

    UIStackView *actionRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.cancelButton, self.applyButton]];
    actionRow.translatesAutoresizingMaskIntoConstraints = NO;
    actionRow.axis = UILayoutConstraintAxisHorizontal;
    actionRow.spacing = 12.0;
    actionRow.distribution = UIStackViewDistributionFillEqually;
    [staticPanel addSubview:actionRow];

    self.actionRow = actionRow;
    [staticPanel addSubview:self.stopButton];
}

// 👈 بناء عناصر واجهة نافذة البلوتوث المضافة حديثاً
- (void)buildBluetoothPanel {
    UIView *content = self.controlPanel.contentView;

    self.bluetoothControlsContainer = [[UIView alloc] init];
    self.bluetoothControlsContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.bluetoothControlsContainer.hidden = YES;
    [content addSubview:self.bluetoothControlsContainer];

    self.bluetoothStatusLabel = [[UILabel alloc] init];
    self.bluetoothStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.bluetoothStatusLabel.text = @"اضغط لبدء فحص وحصاد الإشارات القريبة بدون برامج خارجية:";
    self.bluetoothStatusLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    self.bluetoothStatusLabel.textColor = UIColor.secondaryLabelColor;
    self.bluetoothStatusLabel.numberOfLines = 2;
    [self.bluetoothControlsContainer addSubview:self.bluetoothStatusLabel];

    self.bluetoothScanButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.bluetoothScanButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.bluetoothScanButton setTitle:@"بدء مسح وحصد البلوتوث" forState:UIControlStateNormal];
    [self.bluetoothScanButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.bluetoothScanButton.backgroundColor = UIColor.systemGreenColor;
    self.bluetoothScanButton.layer.cornerRadius = 10.0;
    self.bluetoothScanButton.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightBold];
    [self.bluetoothScanButton addTarget:self action:@selector(handleBluetoothScanToggle) forControlEvents:UIControlEventTouchUpInside];
    [self.bluetoothControlsContainer addSubview:self.bluetoothScanButton];

    self.bluetoothTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.bluetoothTableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.bluetoothTableView.dataSource = self;
    self.bluetoothTableView.delegate = self;
    self.bluetoothTableView.backgroundColor = UIColor.clearColor;
    self.bluetoothTableView.layer.cornerRadius = 8.0;
    self.bluetoothTableView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.bluetoothTableView.layer.borderColor = UIColor.separatorColor.CGColor;
    [self.bluetoothControlsContainer addSubview:self.bluetoothTableView];
}

#pragma mark - Constraints Installation

- (void)installConstraints {
    UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;
    UIView *panelContent = self.controlPanel.contentView;

    [NSLayoutConstraint activateConstraints:@[
        [self.contentScrollView.topAnchor constraintEqualToAnchor:safeArea.topAnchor],
        [self.contentScrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.contentScrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.contentScrollView.bottomAnchor constraintEqualToAnchor:safeArea.bottomAnchor],

        [self.scrollContentView.topAnchor constraintEqualToAnchor:self.contentScrollView.contentLayoutGuide.topAnchor],
        [self.scrollContentView.leadingAnchor constraintEqualToAnchor:self.contentScrollView.contentLayoutGuide.leadingAnchor],
        [self.scrollContentView.trailingAnchor constraintEqualToAnchor:self.contentScrollView.contentLayoutGuide.trailingAnchor],
        [self.scrollContentView.bottomAnchor constraintEqualToAnchor:self.contentScrollView.contentLayoutGuide.bottomAnchor],
        [self.scrollContentView.widthAnchor constraintEqualToAnchor:self.contentScrollView.frameLayoutGuide.widthAnchor],

        [self.headerView.topAnchor constraintEqualToAnchor:self.scrollContentView.topAnchor constant:8.0],
        [self.headerView.leadingAnchor constraintEqualToAnchor:self.scrollContentView.leadingAnchor constant:kLSHorizontalInset],
        [self.headerView.trailingAnchor constraintEqualToAnchor:self.scrollContentView.trailingAnchor constant:-kLSHorizontalInset],

        [self.titleLabel.topAnchor constraintEqualToAnchor:self.headerView.topAnchor],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.headerView.leadingAnchor],

        [self.closeButton.centerYAnchor constraintEqualToAnchor:self.titleLabel.centerYAnchor],
        [self.closeButton.trailingAnchor constraintEqualToAnchor:self.headerView.trailingAnchor],
        [self.closeButton.widthAnchor constraintEqualToConstant:32.0],
        [self.closeButton.heightAnchor constraintEqualToConstant:32.0],

        [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:4.0],
        [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.headerView.leadingAnchor],
        [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.headerView.trailingAnchor],

        [self.statusPill.topAnchor constraintEqualToAnchor:self.subtitleLabel.bottomAnchor constant:12.0],
        [self.statusPill.leadingAnchor constraintEqualToAnchor:self.headerView.leadingAnchor],
        [self.statusPill.bottomAnchor constraintEqualToAnchor:self.headerView.bottomAnchor],

        [self.statusDot.leadingAnchor constraintEqualToAnchor:self.statusPill.leadingAnchor constant:10.0],
        [self.statusDot.centerYAnchor constraintEqualToAnchor:self.statusPill.centerYAnchor],
        [self.statusDot.widthAnchor constraintEqualToConstant:10.0],
        [self.statusDot.heightAnchor constraintEqualToConstant:10.0],

        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.statusDot.trailingAnchor constant:8.0],
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.statusPill.topAnchor constant:6.0],
        [self.statusLabel.bottomAnchor constraintEqualToAnchor:self.statusPill.bottomAnchor constant:-6.0],

        [self.pillStopLabel.leadingAnchor constraintEqualToAnchor:self.statusLabel.trailingAnchor constant:6.0],
        [self.pillStopLabel.centerYAnchor constraintEqualToAnchor:self.statusPill.centerYAnchor],
        [self.pillStopLabel.trailingAnchor constraintEqualToAnchor:self.statusPill.trailingAnchor constant:-12.0],

        [self.searchBar.topAnchor constraintEqualToAnchor:self.headerView.bottomAnchor constant:16.0],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:self.scrollContentView.leadingAnchor constant:kLSHorizontalInset],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:self.searchSpinner.leadingAnchor constant:-4.0],
        [self.searchBar.heightAnchor constraintEqualToConstant:52.0],

        [self.searchSpinner.centerYAnchor constraintEqualToAnchor:self.searchBar.centerYAnchor],
        [self.searchSpinner.trailingAnchor constraintEqualToAnchor:self.scrollContentView.trailingAnchor constant:-kLSHorizontalInset],

        [self.suggestionsPanel.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor constant:2.0],
        [self.suggestionsPanel.leadingAnchor constraintEqualToAnchor:self.searchBar.leadingAnchor],
        [self.suggestionsPanel.trailingAnchor constraintEqualToAnchor:self.searchBar.trailingAnchor],

        [self.suggestionsTableView.topAnchor constraintEqualToAnchor:self.suggestionsPanel.topAnchor],
        [self.suggestionsTableView.leadingAnchor constraintEqualToAnchor:self.suggestionsPanel.leadingAnchor],
        [self.suggestionsTableView.trailingAnchor constraintEqualToAnchor:self.suggestionsPanel.trailingAnchor],
        [self.suggestionsTableView.bottomAnchor constraintEqualToAnchor:self.suggestionsPanel.bottomAnchor],

        [self.mapContainer.topAnchor constraintEqualToAnchor:self.suggestionsPanel.bottomAnchor constant:10.0],
        [self.mapContainer.leadingAnchor constraintEqualToAnchor:self.scrollContentView.leadingAnchor constant:kLSHorizontalInset],
        [self.mapContainer.trailingAnchor constraintEqualToAnchor:self.scrollContentView.trailingAnchor constant:-kLSHorizontalInset],

        [self.mapView.topAnchor constraintEqualToAnchor:self.mapContainer.topAnchor],
        [self.mapView.leadingAnchor constraintEqualToAnchor:self.mapContainer.leadingAnchor],
        [self.mapView.trailingAnchor constraintEqualToAnchor:self.mapContainer.trailingAnchor],
        [self.mapView.bottomAnchor constraintEqualToAnchor:self.mapContainer.bottomAnchor],

        [self.mapHintLabel.bottomAnchor constraintEqualToAnchor:self.mapContainer.bottomAnchor constant:-12.0],
        [self.mapHintLabel.centerXAnchor constraintEqualToAnchor:self.mapContainer.centerXAnchor],

        [self.mapSpinner.centerXAnchor constraintEqualToAnchor:self.mapContainer.centerXAnchor],
        [self.mapSpinner.centerYAnchor constraintEqualToAnchor:self.mapContainer.centerYAnchor],

        [self.controlPanel.topAnchor constraintEqualToAnchor:self.mapContainer.bottomAnchor constant:16.0],
        [self.controlPanel.leadingAnchor constraintEqualToAnchor:self.scrollContentView.leadingAnchor constant:kLSHorizontalInset],
        [self.controlPanel.trailingAnchor constraintEqualToAnchor:self.scrollContentView.trailingAnchor constant:-kLSHorizontalInset],
        [self.controlPanel.bottomAnchor constraintEqualToAnchor:self.scrollContentView.bottomAnchor constant:-8.0],

        [self.panelTabSegment.topAnchor constraintEqualToAnchor:panelContent.topAnchor constant:14.0],
        [self.panelTabSegment.leadingAnchor constraintEqualToAnchor:panelContent.leadingAnchor constant:12.0],
        [self.panelTabSegment.trailingAnchor constraintEqualToAnchor:panelContent.trailingAnchor constant:-12.0],

        [self.mapControlsContainer.topAnchor constraintEqualToAnchor:self.panelTabSegment.bottomAnchor constant:10.0],
        [self.mapControlsContainer.leadingAnchor constraintEqualToAnchor:panelContent.leadingAnchor constant:12.0],
        [self.mapControlsContainer.trailingAnchor constraintEqualToAnchor:panelContent.trailingAnchor constant:-12.0],
        [self.mapControlsContainer.bottomAnchor constraintEqualToAnchor:panelContent.bottomAnchor constant:-12.0],

        [self.bookmarksContainer.topAnchor constraintEqualToAnchor:self.panelTabSegment.bottomAnchor constant:6.0],
        [self.bookmarksContainer.leadingAnchor constraintEqualToAnchor:panelContent.leadingAnchor],
        [self.bookmarksContainer.trailingAnchor constraintEqualToAnchor:panelContent.trailingAnchor],
        [self.bookmarksContainer.bottomAnchor constraintEqualToAnchor:panelContent.bottomAnchor constant:-8.0],

        // محاذاة نافذة البلوتوث الجديدة
        [self.bluetoothControlsContainer.topAnchor constraintEqualToAnchor:self.panelTabSegment.bottomAnchor constant:12.0],
        [self.bluetoothControlsContainer.leadingAnchor constraintEqualToAnchor:panelContent.leadingAnchor constant:12.0],
        [self.bluetoothControlsContainer.trailingAnchor constraintEqualToAnchor:panelContent.trailingAnchor constant:-12.0],
        [self.bluetoothControlsContainer.bottomAnchor constraintEqualToAnchor:panelContent.bottomAnchor constant:-12.0],

        [self.bluetoothStatusLabel.topAnchor constraintEqualToAnchor:self.bluetoothControlsContainer.topAnchor],
        [self.bluetoothStatusLabel.leadingAnchor constraintEqualToAnchor:self.bluetoothControlsContainer.leadingAnchor],
        [self.bluetoothStatusLabel.trailingAnchor constraintEqualToAnchor:self.bluetoothControlsContainer.trailingAnchor],

        [self.bluetoothScanButton.topAnchor constraintEqualToAnchor:self.bluetoothStatusLabel.bottomAnchor constant:8.0],
        [self.bluetoothScanButton.leadingAnchor constraintEqualToAnchor:self.bluetoothControlsContainer.leadingAnchor],
        [self.bluetoothScanButton.trailingAnchor constraintEqualToAnchor:self.bluetoothControlsContainer.trailingAnchor],
        [self.bluetoothScanButton.heightAnchor constraintEqualToConstant:40.0],

        [self.bluetoothTableView.topAnchor constraintEqualToAnchor:self.bluetoothScanButton.bottomAnchor constant:10.0],
        [self.bluetoothTableView.leadingAnchor constraintEqualToAnchor:self.bluetoothControlsContainer.leadingAnchor],
        [self.bluetoothTableView.trailingAnchor constraintEqualToAnchor:self.bluetoothControlsContainer.trailingAnchor],
        [self.bluetoothTableView.bottomAnchor constraintEqualToAnchor:self.bluetoothControlsContainer.bottomAnchor],
        [self.bluetoothTableView.heightAnchor constraintEqualToConstant:220.0],

        [self.coordinateModeSegment.topAnchor constraintEqualToAnchor:self.mapControlsContainer.topAnchor],
        [self.coordinateModeSegment.leadingAnchor constraintEqualToAnchor:self.mapControlsContainer.leadingAnchor constant:12.0],
        [self.coordinateModeSegment.trailingAnchor constraintEqualToAnchor:self.mapControlsContainer.trailingAnchor constant:-12.0],

        [self.mapControlsStack.topAnchor constraintEqualToAnchor:self.coordinateModeSegment.bottomAnchor constant:12.0],
        [self.mapControlsStack.leadingAnchor constraintEqualToAnchor:self.mapControlsContainer.leadingAnchor constant:12.0],
        [self.mapControlsStack.trailingAnchor constraintEqualToAnchor:self.mapControlsContainer.trailingAnchor constant:-12.0],
        [self.mapControlsStack.bottomAnchor constraintEqualToAnchor:self.mapControlsContainer.bottomAnchor constant:-12.0],

        [self.coordinateTitleLabel.topAnchor constraintEqualToAnchor:self.staticControlsContainer.topAnchor],
        [self.coordinateTitleLabel.leadingAnchor constraintEqualToAnchor:self.staticControlsContainer.leadingAnchor],

        [self.bookmarkSaveButton.centerYAnchor constraintEqualToAnchor:self.coordinateTitleLabel.centerYAnchor],
        [self.bookmarkSaveButton.trailingAnchor constraintEqualToAnchor:self.staticControlsContainer.trailingAnchor],

        [self.coordinateValueLabel.topAnchor constraintEqualToAnchor:self.coordinateTitleLabel.bottomAnchor constant:4.0],
        [self.coordinateValueLabel.leadingAnchor constraintEqualToAnchor:self.staticControlsContainer.leadingAnchor],
        [self.coordinateValueLabel.trailingAnchor constraintEqualToAnchor:self.staticControlsContainer.trailingAnchor],

        [self.separatorCoordFields.topAnchor constraintEqualToAnchor:self.coordinateValueLabel.bottomAnchor constant:8.0],
        [self.separatorCoordFields.leadingAnchor constraintEqualToAnchor:self.staticControlsContainer.leadingAnchor],
        [self.separatorCoordFields.trailingAnchor constraintEqualToAnchor:self.staticControlsContainer.trailingAnchor],

        [self.fieldStack.topAnchor constraintEqualToAnchor:self.separatorCoordFields.bottomAnchor constant:6.0],
        [self.fieldStack.leadingAnchor constraintEqualToAnchor:self.staticControlsContainer.leadingAnchor],
        [self.fieldStack.trailingAnchor constraintEqualToAnchor:self.staticControlsContainer.trailingAnchor],

        [self.separatorFieldsHeading.topAnchor constraintEqualToAnchor:self.fieldStack.bottomAnchor constant:8.0],
        [self.separatorFieldsHeading.leadingAnchor constraintEqualToAnchor:self.staticControlsContainer.leadingAnchor],
        [self.separatorFieldsHeading.trailingAnchor constraintEqualToAnchor:self.staticControlsContainer.trailingAnchor],

        [self.headingValueLabel.topAnchor constraintEqualToAnchor:self.separatorFieldsHeading.bottomAnchor constant:6.0],
        [self.headingValueLabel.leadingAnchor constraintEqualToAnchor:self.staticControlsContainer.leadingAnchor],

        [self.headingSlider.centerYAnchor constraintEqualToAnchor:self.headingValueLabel.centerYAnchor],
        [self.headingSlider.leadingAnchor constraintEqualToAnchor:self.headingValueLabel.trailingAnchor constant:12.0],
        [self.headingSlider.trailingAnchor constraintEqualToAnchor:self.staticControlsContainer.trailingAnchor],

        [self.headingDirectionLabel.topAnchor constraintEqualToAnchor:self.headingSlider.bottomAnchor constant:2.0],
        [self.headingDirectionLabel.centerXAnchor constraintEqualToAnchor:self.headingSlider.centerXAnchor],

        [self.separatorHeadingActions.topAnchor constraintEqualToAnchor:self.headingDirectionLabel.bottomAnchor constant:8.0],
        [self.separatorHeadingActions.leadingAnchor constraintEqualToAnchor:self.staticControlsContainer.leadingAnchor],
        [self.separatorHeadingActions.trailingAnchor constraintEqualToAnchor:self.staticControlsContainer.trailingAnchor],

        [self.separatorFluctuation.topAnchor constraintEqualToAnchor:self.separatorHeadingActions.bottomAnchor constant:8.0],
        [self.separatorFluctuation.leadingAnchor constraintEqualToAnchor:self.staticControlsContainer.leadingAnchor],
        [self.separatorFluctuation.trailingAnchor constraintEqualToAnchor:self.staticControlsContainer.trailingAnchor],

        [self.fluctuationRow.topAnchor constraintEqualToAnchor:self.separatorFluctuation.bottomAnchor constant:8.0],
        [self.fluctuationRow.leadingAnchor constraintEqualToAnchor:self.staticControlsContainer.leadingAnchor],
        [self.fluctuationRow.trailingAnchor constraintEqualToAnchor:self.staticControlsContainer.trailingAnchor],

        [self.fluctuationLabel.leadingAnchor constraintEqualToAnchor:self.fluctuationRow.leadingAnchor],
        [self.fluctuationLabel.centerYAnchor constraintEqualToAnchor:self.fluctuationRow.centerYAnchor],

        [self.fluctuationSwitch.trailingAnchor constraintEqualToAnchor:self.fluctuationRow.trailingAnchor],
        [self.fluctuationSwitch.centerYAnchor constraintEqualToAnchor:self.fluctuationRow.centerYAnchor],

        [self.fluctuationRow.heightAnchor constraintEqualToConstant:40.0],

        (self.fluctuationRadiusTopConstraint = [self.fluctuationRadiusField.topAnchor constraintEqualToAnchor:self.fluctuationRow.bottomAnchor constant:6.0]),
        [self.fluctuationRadiusField.leadingAnchor constraintEqualToAnchor:self.staticControlsContainer.leadingAnchor],
        [self.fluctuationRadiusField.trailingAnchor constraintEqualToAnchor:self.staticControlsContainer.trailingAnchor],
        (self.fluctuationRadiusHeightConstraint = [self.fluctuationRadiusField.heightAnchor constraintEqualToConstant:40.0]),

        [self.cancelButton.heightAnchor constraintEqualToConstant:50.0],
        [self.applyButton.heightAnchor constraintEqualToConstant:50.0],

        [self.actionRow.topAnchor constraintEqualToAnchor:self.fluctuationRadiusField.bottomAnchor constant:12.0],
        [self.actionRow.leadingAnchor constraintEqualToAnchor:self.staticControlsContainer.leadingAnchor],
        [self.actionRow.trailingAnchor constraintEqualToAnchor:self.staticControlsContainer.trailingAnchor],

        [self.stopButton.topAnchor constraintEqualToAnchor:self.actionRow.bottomAnchor constant:10.0],
        [self.stopButton.leadingAnchor constraintEqualToAnchor:self.staticControlsContainer.leadingAnchor],
        [self.stopButton.trailingAnchor constraintEqualToAnchor:self.staticControlsContainer.trailingAnchor]
    ]];

    [self ls_installRouteConstraintsInRoutePanel];

    self.mapControlsBottomStaticConstraint = [self.stopButton.bottomAnchor constraintEqualToAnchor:self.staticControlsContainer.bottomAnchor constant:-12.0];
    self.mapControlsBottomStaticNoStopConstraint = [self.actionRow.bottomAnchor constraintEqualToAnchor:self.staticControlsContainer.bottomAnchor constant:-12.0];
    self.mapControlsBottomRouteConstraint = [self.routeActionRow.bottomAnchor constraintEqualToAnchor:self.routeControlsContainer.bottomAnchor constant:-12.0];
    self.mapControlsBottomRouteEarlyConstraint = [self.getRouteButton.bottomAnchor constraintEqualToAnchor:self.routeControlsContainer.bottomAnchor constant:-12.0];
    self.mapControlsBottomStaticConstraint.active = YES;

    self.stopButtonHeightConstraint = [self.stopButton.heightAnchor constraintEqualToConstant:50.0];
    self.stopButtonHeightConstraint.active = YES;

    self.suggestionsHeightConstraint = [self.suggestionsPanel.heightAnchor constraintEqualToConstant:0.0];
    self.suggestionsHeightConstraint.active = YES;

    self.mapHeightConstraint = [self.mapContainer.heightAnchor constraintEqualToAnchor:self.view.heightAnchor multiplier:kLSMapHeightMultiplier];
    self.mapHeightConstraint.active = YES;
}

#pragma mark - Controls & Helpers

- (UIView *)ls_separatorView {
    UIView *line = [[UIView alloc] init];
    line.translatesAutoresizingMaskIntoConstraints = NO;
    line.backgroundColor = UIColor.separatorColor;
    [NSLayoutConstraint activateConstraints:@[[line.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale]]];
    return line;
}

- (UIView *)coordinateFieldWithTitle:(NSString *)title placeholder:(NSString *)placeholder textField:(UITextField * __strong *)textFieldOut {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    container.layer.cornerRadius = 10.0;
    container.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    container.layer.borderColor = UIColor.separatorColor.CGColor;

    UILabel *caption = [[UILabel alloc] init];
    caption.translatesAutoresizingMaskIntoConstraints = NO;
    caption.text = title;
    caption.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold];
    caption.textColor = UIColor.secondaryLabelColor;
    [container addSubview:caption];

    UITextField *field = [[UITextField alloc] init];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.placeholder = placeholder;
    field.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    field.font = [UIFont monospacedDigitSystemFontOfSize:14.0 weight:UIFontWeightMedium];
    [field addTarget:self action:@selector(textFieldDidChange:) forControlEvents:UIControlEventEditingChanged];
    [container addSubview:field];

    if (textFieldOut) { *textFieldOut = field; }

    [NSLayoutConstraint activateConstraints:@[
        [caption.topAnchor constraintEqualToAnchor:container.topAnchor constant:4.0],
        [caption.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:10.0],
        [field.topAnchor constraintEqualToAnchor:caption.bottomAnchor constant:1.0],
        [field.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:10.0],
        [field.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-10.0],
        [field.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-6.0],
        [container.heightAnchor constraintEqualToConstant:46.0]
    ]];
    return container;
}

- (UIButton *)primaryButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    button.backgroundColor = UIColor.systemBlueColor;
    button.layer.cornerRadius = 12.0;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (UIButton *)secondaryButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.labelColor forState:UIControlStateNormal];
    button.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    button.layer.cornerRadius = 12.0;
    button.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    button.layer.borderColor = UIColor.separatorColor.CGColor;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (UIButton *)destructiveOutlineButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    [button setTitleColor:UIColor.systemRedColor forState:UIControlStateNormal];
    button.backgroundColor = [UIColor.systemRedColor colorWithAlphaComponent:0.12];
    button.layer.cornerRadius = 12.0;
    button.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    button.layer.borderColor = UIColor.systemRedColor.CGColor;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)configureKeyboardToolbar {
    UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 0, 44)];
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismissKeyboard)];
    toolbar.items = @[flex, done];
    self.latitudeField.inputAccessoryView = toolbar;
    self.longitudeField.inputAccessoryView = toolbar;
    self.altitudeField.inputAccessoryView = toolbar;
    self.customSpeedField.inputAccessoryView = toolbar;
}

- (void)refreshStatusPill {
    LSRouteSimulator *simulator = [LSRouteSimulator shared];
    LSBluetoothManager *btManager = [LSBluetoothManager sharedManager];
    
    if (btManager.isAdvertising) {
        self.statusLabel.text = @"تزييف البلوتوث نشط بثبات 📡";
        self.statusDot.backgroundColor = UIColor.systemPurpleColor;
    } else if (simulator.isSimulating) {
        double kmh = [LSRouteSimulator speedMetersPerSecondForMode:simulator.transportMode customSpeedKmh:simulator.customSpeedKmh] * 3.6;
        self.statusLabel.text = [NSString stringWithFormat:@"محاكاة المسار · %.1f كم/س", kmh];
        self.statusDot.backgroundColor = UIColor.systemGreenColor;
    } else {
        BOOL active = [[PersistenceManager shared] isSpoofingEnabled];
        self.statusLabel.text = active ? @"تزييف الموقع مفعل 📍" : @"التزييف متوقف";
        self.statusDot.backgroundColor = active ? UIColor.systemGreenColor : UIColor.systemOrangeColor;
    }

    BOOL active = [[PersistenceManager shared] isSpoofingEnabled] || simulator.isSimulating || btManager.isAdvertising;
    self.pillStopLabel.hidden = !active;
    self.statusPill.backgroundColor = active ? [UIColor.systemRedColor colorWithAlphaComponent:0.12] : [UIColor.tertiarySystemFillColor colorWithAlphaComponent:0.9];
    
    BOOL showStop = active && self.coordinateMode == LSMapPickerCoordinateModeStatic && self.panelTab == LSMapPickerPanelTabMap;
    self.stopButton.hidden = !showStop;
    self.stopButtonHeightConstraint.constant = showStop ? 50.0 : 0.0;
    [self ls_updateMapControlsBottomConstraint];
}

#pragma mark - Keyboard Handlers

- (void)ls_keyboardWillShow:(NSNotification *)note {
    CGRect kbFrame = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    UIEdgeInsets insets = self.contentScrollView.contentInset;
    insets.bottom = kbFrame.size.height;
    self.contentScrollView.contentInset = insets;
    self.contentScrollView.scrollIndicatorInsets = insets;
}

- (void)ls_keyboardWillHide:(NSNotification *)note {
    UIEdgeInsets insets = self.contentScrollView.contentInset;
    insets.bottom = 0.0;
    self.contentScrollView.contentInset = insets;
    self.contentScrollView.scrollIndicatorInsets = insets;
}

#pragma mark - Map Methods

- (void)configureMapIfNeeded {
    if (self.mapConfigured) return;
    self.mapConfigured = YES;
    [self.mapSpinner startAnimating];

    self.pinAnnotation = [[MKPointAnnotation alloc] init];
    self.pinAnnotation.title = @"الموقع المزيّف";
    self.pinAnnotation.coordinate = self.selectedCoordinate;
    [self.mapView addAnnotation:self.pinAnnotation];

    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(self.selectedCoordinate, 1500.0, 1500.0);
    [self.mapView setRegion:region animated:NO];
    [self updateSearchCompleterRegion];
}

- (void)syncFieldsFromCoordinate {
    self.suppressFieldSync = YES;
    self.latitudeField.text = [NSString stringWithFormat:@"%.6f", self.selectedCoordinate.latitude];
    self.longitudeField.text = [NSString stringWithFormat:@"%.6f", self.selectedCoordinate.longitude];
    self.suppressFieldSync = NO;
    [self updateCoordinateLabel];
    [self updatePinOnMapAnimated:NO];
}

- (void)updateCoordinateLabel {
    self.coordinateValueLabel.text = [NSString stringWithFormat:@"%@%.6f\n%@%.6f",
                                      self.selectedCoordinate.latitude >= 0.0 ? @"N " : @"S ",
                                      fabs(self.selectedCoordinate.latitude),
                                      self.selectedCoordinate.longitude >= 0.0 ? @"E " : @"W ",
                                      fabs(self.selectedCoordinate.longitude)];
}

- (void)movePinToCoordinate:(CLLocationCoordinate2D)coordinate animated:(BOOL)animated {
    self.selectedCoordinate = coordinate;
    self.hasSelectedCoordinate = YES;
    self.suppressFieldSync = YES;
    self.latitudeField.text = [NSString stringWithFormat:@"%.6f", coordinate.latitude];
    self.longitudeField.text = [NSString stringWithFormat:@"%.6f", coordinate.longitude];
    self.suppressFieldSync = NO;
    [self updateCoordinateLabel];
    [self updatePinOnMapAnimated:animated];
}

- (void)updatePinOnMapAnimated:(BOOL)animated {
    if (!self.pinAnnotation) return;
    self.pinAnnotation.coordinate = self.selectedCoordinate;
}

#pragma mark - Validation & Input Parsing

- (nullable NSNumber *)ls_parsedCoordinateComponentFromText:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) return nil;
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    return [formatter numberFromString:[trimmed stringByReplacingOccurrencesOfString:@"," withString:@"."]];
}

- (BOOL)applyFieldsToCoordinate {
    if (self.suppressFieldSync) return YES;
    NSNumber *lat = [self ls_parsedCoordinateComponentFromText:self.latitudeField.text];
    NSNumber *lng = [self ls_parsedCoordinateComponentFromText:self.longitudeField.text];
    if (!lat || !lng) return NO;
    [self movePinToCoordinate:CLLocationCoordinate2DMake(lat.doubleValue, lng.doubleValue) animated:YES];
    return YES;
}

- (void)showInvalidCoordinateFeedback {
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [feedback impactOccurred];
}

- (BOOL)applyAltitudeField {
    NSNumber *alt = [self ls_parsedCoordinateComponentFromText:self.altitudeField.text];
    if (!alt) return NO;
    [PersistenceManager shared].altitude = alt.doubleValue;
    return YES;
}

- (void)handleHeadingSliderChanged:(UISlider *)sender {
    NSInteger heading = (NSInteger)lroundf(self.headingSlider.value);
    [PersistenceManager shared].heading = (CLLocationDirection)heading;
    [self updateHeadingLabel];
}

- (void)syncFluctuationUI {
    PersistenceManager *store = [PersistenceManager shared];
    self.fluctuationSwitch.on = store.fluctuationEnabled;
    self.fluctuationRadiusField.text = [NSString stringWithFormat:@"%.0f", store.fluctuationRadius];
    self.fluctuationRadiusField.hidden = !store.fluctuationEnabled;
}

- (void)handleFluctuationToggle {
    PersistenceManager *store = [PersistenceManager shared];
    store.fluctuationEnabled = self.fluctuationSwitch.isOn;
    self.fluctuationRadiusField.hidden = !self.fluctuationSwitch.isOn;
    if (self.fluctuationSwitch.isOn) { [self.fluctuationRadiusField becomeFirstResponder]; }
}

- (void)handleFluctuationRadiusChanged {
    NSNumber *val = [self ls_parsedCoordinateComponentFromText:self.fluctuationRadiusField.text];
    double r = val ? val.doubleValue : 50.0;
    [PersistenceManager shared].fluctuationRadius = MAX(1.0, MIN(r, 1000.0));
    self.fluctuationRadiusField.text = [NSString stringWithFormat:@"%.0f", [PersistenceManager shared].fluctuationRadius];
}

- (void)updateHeadingLabel {
    NSInteger heading = (NSInteger)lroundf(self.headingSlider.value);
    self.headingValueLabel.text = [NSString stringWithFormat:@"الاتجاه: %03ld°", (long)heading];
}

#pragma mark - Tabs Switching

- (void)handlePanelTabChanged:(UISegmentedControl *)sender {
    self.panelTab = sender.selectedSegmentIndex;
    [self updatePanelTabVisibility];
    
    // إيقاف مسح البلوتوث إذا غادر المستخدم النافذة لتوفير الطاقة
    if (self.panelTab != LSMapPickerPanelTabBluetooth) {
        [[LSBluetoothManager sharedManager] stopScanning];
        [self.bluetoothScanButton setTitle:@"بدء مسح وحصد البلوتوث" forState:UIControlStateNormal];
        self.bluetoothScanButton.backgroundColor = UIColor.systemGreenColor;
    }
}

- (void)updatePanelTabVisibility {
    self.mapControlsContainer.hidden = (self.panelTab != LSMapPickerPanelTabMap);
    self.bookmarksContainer.hidden = (self.panelTab != LSMapPickerPanelTabBookmarks);
    self.bluetoothControlsContainer.hidden = (self.panelTab != LSMapPickerPanelTabBluetooth); // 👈 إخفاء وإظهار نافذة البلوتوث
    [self refreshStatusPill];
}

#pragma mark - Bluetooth Actions (إجراءات البلوتوث وحصاد البيانات)

- (void)handleBluetoothScanToggle {
    LSBluetoothManager *bt = [LSBluetoothManager sharedManager];
    if (bt.isScanning) {
        [bt stopScanning];
        [self.bluetoothScanButton setTitle:@"بدء مسح وحصد البلوتوث" forState:UIControlStateNormal];
        self.bluetoothScanButton.backgroundColor = UIColor.systemGreenColor;
        self.bluetoothStatusLabel.text = @"توقف المسح. اضغط مجدداً للاستئناف:";
    } else {
        [bt startScanning];
        [self.bluetoothScanButton setTitle:@"جاري الحصاد... اضغط للإيقاف" forState:UIControlStateNormal];
        self.bluetoothScanButton.backgroundColor = UIColor.systemRedColor;
        self.bluetoothStatusLabel.text = @"جاري الاستماع للإشارات المحيطة وفك تشفير حزم الحضور الذكي...";
    }
}

// مفوض استقبال إشارات البلوتوث وتحديث الجدول لحظياً
- (void)blueToothManagerDidUpdateDiscoveredDevices:(NSArray<NSDictionary *> *)devices {
    self.btDevices = devices;
    [self.bluetoothTableView reloadData];
}

#pragma mark - Search Suggestions Mechanics

- (void)updateSearchCompleterRegion {
    if (self.mapConfigured) self.searchCompleter.region = self.mapView.region;
}

- (void)updateSearchSuggestionsVisibility {
    NSInteger count = self.searchCompletions.count;
    if (count > 0 && self.searchBar.isFirstResponder) {
        self.suggestionsHeightConstraint.constant = MIN(count * kLSSuggestionRowHeight, kLSSuggestionMaxHeight);
        self.suggestionsPanel.hidden = NO;
        self.suggestionsPanel.alpha = 1.0;
    } else {
        [self hideSearchSuggestions];
    }
}

- (void)hideSearchSuggestions {
    self.suggestionsHeightConstraint.constant = 0.0;
    self.suggestionsPanel.hidden = YES;
}

- (void)updateSearchQueryFragment:(NSString *)query {
    if (query.length == 0) {
        self.searchCompletions = @[];
        [self.suggestionsTableView reloadData];
        [self hideSearchSuggestions];
        return;
    }
    [self updateSearchCompleterRegion];
    self.searchCompleter.queryFragment = query;
}

- (void)resolveSearchCompletion:(MKLocalSearchCompletion *)completion {
    [self hideSearchSuggestions];
    [self.searchBar resignFirstResponder];
    self.searchBar.text = completion.title;

    MKLocalSearchRequest *request = [[MKLocalSearchRequest alloc] initWithCompletion:completion];
    MKLocalSearch *search = [[MKLocalSearch alloc] initWithRequest:request];
    [search startWithCompletionHandler:^(MKLocalSearchResponse * _Nullable response, NSError * _Nullable error) {
        if (!error && response.mapItems.count > 0) {
            [self movePinToCoordinate:response.mapItems.firstObject.placemark.coordinate animated:YES];
        }
    }];
}

#pragma mark - MKLocalSearchCompleterDelegate

- (void)completerDidUpdateResults:(MKLocalSearchCompleter *)completer {
    self.searchCompletions = completer.results ?: @[];
    [self.suggestionsTableView reloadData];
    [self updateSearchSuggestionsVisibility];
}

- (void)completer:(MKLocalSearchCompleter *)completer didFailWithError:(NSError *)error {
    [self hideSearchSuggestions];
}

#pragma mark - UITableView Combined DataSource & Delegate

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (tableView == self.bluetoothTableView) {
        return self.btDevices.count; // 👈 عدد أجهزة البلوتوث المرصودة
    }
    if ([self ls_isBookmarksTableView:tableView]) {
        return [self ls_bookmarksNumberOfRowsInSection:section];
    }
    return self.searchCompletions.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    // 1. جدول البلوتوث وحصاد الإشارات بدون برامج خارجية
    if (tableView == self.bluetoothTableView) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"LSBluetoothCell"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"LSBluetoothCell"];
        }
        NSDictionary *device = self.btDevices[indexPath.row];
        
        cell.textLabel.text = [NSString stringWithFormat:@"%@  [%@ dBm]", device[@"name"], device[@"rssi"]];
        cell.textLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightBold];
        
        if ([device[@"major"] integerValue] > 0 || [device[@"minor"] integerValue] > 0) {
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@\nUUID: %@\nMajor: %@ | Minor: %@", 
                                         device[@"type"], device[@"uuid"], device[@"major"], device[@"minor"]];
        } else {
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@\nID/Service: %@", device[@"type"], device[@"uuid"]];
        }
        
        cell.detailTextLabel.numberOfLines = 3;
        cell.detailTextLabel.font = [UIFont systemFontOfSize:11.0];
        cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
        cell.imageView.image = [UIImage systemImageNamed:@"antenna.radiowaves.left.and.right"];
        cell.imageView.tintColor = UIColor.systemPurpleColor;
        cell.backgroundColor = UIColor.clearColor;
        return cell;
    }
    
    // 2. جدول المحفوظات
    if ([self ls_isBookmarksTableView:tableView]) {
        return [self ls_bookmarksCellForRowAtIndexPath:indexPath];
    }

    // 3. جدول مقترحات البحث عن المدن
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"LSSearchSuggestionCell" forIndexPath:indexPath];
    MKLocalSearchCompletion *completion = self.searchCompletions[indexPath.row];
    cell.textLabel.text = completion.title;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    // 👈 عند الضغط على إشارة بلوتوث مرصودة: يتم نسخها ومحاكاتها فوراً من داخل الأداة
    if (tableView == self.bluetoothTableView) {
        NSDictionary *device = self.btDevices[indexPath.row];
        
        NSString *uuid = device[@"uuid"];
        uint16_t major = [device[@"major"] unsignedShortValue];
        uint16_t minor = [device[@"minor"] unsignedShortValue];
        
        [[LSBluetoothManager sharedManager] stopScanning];
        [self Richmond_StopScanUI];
        
        if (major > 0 || minor > 0) {
            [[LSBluetoothManager sharedManager] startSpoofingBeaconWithUUID:uuid major:major minor:minor];
        } else {
            [[LSBluetoothManager sharedManager] startSpoofingGenericBLEWithServiceUUID:uuid localName:device[@"name"]];
        }
        
        [self refreshStatusPill];
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"تم نسخ وتزييف البلوتوث ✅" 
                                                                       message:[NSString stringWithFormat:@"جاري بث إشارة ومحاكاة جهاز [%@] بنجاح الآن عن بعد.", device[@"name"]] 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"ممتاز" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    if ([self ls_isBookmarksTableView:tableView]) {
        [self ls_bookmarksDidSelectRowAtIndexPath:indexPath];
        return;
    }

    [self resolveSearchCompletion:self.searchCompletions[indexPath.row]];
}

- (void)Richmond_StopScanUI {
    [self.bluetoothScanButton setTitle:@"بدء مسح وحصد البلوتوث" forState:UIControlStateNormal];
    self.bluetoothScanButton.backgroundColor = UIColor.systemGreenColor;
}

#pragma mark - UISearchBarDelegate

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar { [self updateSearchSuggestionsVisibility]; }
- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar { [self hideSearchSuggestions]; [searchBar resignFirstResponder]; }
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText { [self updateSearchQueryFragment:searchText]; }
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }

#pragma mark - Final Execution & Handoff

- (void)handleApply {
    [self dismissKeyboard];
    if (![self applyFieldsToCoordinate] || ![self applyAltitudeField]) return;

    PersistenceManager *store = [PersistenceManager shared];
    if (![store setSpoofCoordinate:self.selectedCoordinate enabled:YES]) return;

    [store recordRecentCoordinate:self.selectedCoordinate name:nil];
    LSSetHooksBypassed(NO);
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)handleCancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)handleStatusPillTapped {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"هل تريد إيقاف تزييف (الموقع / البلوتوث)؟" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"إيقاف الكل والعودة للوضع الطبيعي" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [self handleStopSpoofing];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"تراجع" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)handleStopSpoofing {
    [[LSRouteSimulator shared] stop];
    [[PersistenceManager shared] clearSpoof];
    [[LSBluetoothManager sharedManager] stopSpoofing]; // 👈 إيقاف بث وتزييف البلوتوث
    [[LSBluetoothManager sharedManager] stopScanning];
    [PersistenceManager shared].simulationWasActive = NO;
    LSSetHooksBypassed(NO);
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - 🔐 Activation System (نظام كود التفعيل)

- (void)checkActivation {
    BOOL isActivated = [[NSUserDefaults standardUserDefaults] boolForKey:@"LS_IsActivated"];
    if (isActivated) return;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"تفعيل الأداة المدمجة" message:@"الرجاء إدخال كود التفعيل المكون من 14 رمزاً للاستمرار:" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"LS-XXXXXXX-XXXX";
    }];
    
    UIAlertAction *activateAction = [UIAlertAction actionWithTitle:@"تفعيل" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        UITextField *textField = alert.textFields.firstObject;
        NSString *enteredCode = [textField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        if ([self validateCode:enteredCode]) {
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"LS_IsActivated"];
            [[NSUserDefaults standardUserDefaults] synchronize];
        } else {
            [self checkActivation];
        }
    }];
    [alert addAction:activateAction];
    [self presentViewController:alert animated:YES completion:nil];
}

- (BOOL)validateCode:(NSString *)code {
    if (!code || code.length < 14) return NO;
    NSArray *parts = [code componentsSeparatedByString:@"-"];
    if (parts.count != 3) return NO;
    if (![parts[0] isEqualToString:@"LS"]) return NO;
    
    NSInteger num = [parts[1] integerValue];
    if (num < 1000000 || num > 1999999) return NO;
    
    NSString *secretSalt = @"LS_Protection_2026";
    NSString *inputStr = [NSString stringWithFormat:@"%ld%@", (long)num, secretSalt];
    const char *cStr = [inputStr UTF8String];
    unsigned char digest[16];
    CC_MD5(cStr, (CC_LONG)strlen(cStr), digest);
    
    NSMutableString *computedHash = [NSMutableString stringWithCapacity:4];
    for(int i = 0; i < 2; i++) { [computedHash appendFormat:@"%02X", digest[i]]; }
    return [computedHash isEqualToString:parts[2]];
}

@end
