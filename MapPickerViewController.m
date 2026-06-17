#import "MapPickerViewController.h"
#import "MapPickerViewController+Private.h"
#import "LocationSpoofer.h"
#import "OverlayWindow.h"
#import "PersistenceManager.h"
#import "RouteSimulator.h"

#import <CoreLocation/CoreLocation.h>
#import <MapKit/MapKit.h>
#import "BluetoothSpooferViewController.h"

static const CGFloat kLSCornerRadius = 16.0;
static const CGFloat kLSHorizontalInset = 20.0;
static const CGFloat kLSControlPanelCornerRadius = 16.0;
static const CGFloat kLSSuggestionRowHeight = 48.0;
static const CGFloat kLSSuggestionMaxHeight = 240.0;
static const NSInteger kLSSuggestionMaxVisibleRows = 5;
static const CGFloat kLSMapHeightMultiplier = 0.30;

@interface MapPickerViewController () <MKMapViewDelegate, UISearchBarDelegate, UITextFieldDelegate, MKLocalSearchCompleterDelegate, UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UIButton *bluetoothMenuButton;
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

    [self buildInterface];
    [self buildRouteControls];
    [self buildBookmarksPanel];
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
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
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
    self.titleLabel.text = @"مزيّف الموقع";
    self.titleLabel.font = [UIFont systemFontOfSize:28.0 weight:UIFontWeightBold];
    self.titleLabel.textColor = UIColor.labelColor;
    self.titleLabel.accessibilityTraits = UIAccessibilityTraitHeader;
    [self.headerView addSubview:self.titleLabel];

    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.subtitleLabel.text = @"اختر الموقع الذي ستعتقد التطبيقات أنك فيه";
    self.subtitleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightRegular];
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
    self.closeButton.accessibilityLabel = @"إغلاق";
    [self.closeButton addTarget:self action:@selector(handleCancel) forControlEvents:UIControlEventTouchUpInside];
    [self.headerView addSubview:self.closeButton];
}

- (void)buildSearchBar {
    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchBar.placeholder = @"ابحث عن مدينة أو عنوان أو معلم";
    self.searchBar.delegate = self;
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.backgroundImage = [[UIImage alloc] init];
    self.searchBar.backgroundColor = UIColor.clearColor;
    self.searchBar.tintColor = UIColor.systemBlueColor;
    if (@available(iOS 13.0, *)) {
        UITextField *tf = self.searchBar.searchTextField;
        tf.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightMedium];
        tf.backgroundColor = [UIColor.systemGray6Color colorWithAlphaComponent:0.6];
        tf.layer.cornerRadius = 12.0;
        tf.clipsToBounds = YES;
    }
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
    self.suggestionsPanel.layer.cornerCurve = kCACornerCurveContinuous;
    self.suggestionsPanel.clipsToBounds = YES;
    self.suggestionsPanel.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.suggestionsPanel.layer.borderColor = UIColor.separatorColor.CGColor;
    self.suggestionsPanel.layer.shadowColor = UIColor.blackColor.CGColor;
    self.suggestionsPanel.layer.shadowOpacity = 0.12;
    self.suggestionsPanel.layer.shadowRadius = 12.0;
    self.suggestionsPanel.layer.shadowOffset = CGSizeMake(0.0, 6.0);
    self.suggestionsPanel.layer.masksToBounds = NO;
    self.suggestionsPanel.hidden = YES;
    self.suggestionsPanel.alpha = 0.0;
    [self.scrollContentView addSubview:self.suggestionsPanel];

    self.suggestionsTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.suggestionsTableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.suggestionsTableView.dataSource = self;
    self.suggestionsTableView.delegate = self;
    self.suggestionsTableView.separatorInset = UIEdgeInsetsMake(0.0, 16.0, 0.0, 16.0);
    self.suggestionsTableView.rowHeight = kLSSuggestionRowHeight;
    self.suggestionsTableView.backgroundColor = UIColor.clearColor;
    self.suggestionsTableView.sectionHeaderHeight = 0.0;
    self.suggestionsTableView.sectionFooterHeight = 0.0;
    [self.suggestionsTableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"LSSearchSuggestionCell"];
    [self.suggestionsPanel addSubview:self.suggestionsTableView];
}

- (void)configureSearchCompleter {
    self.searchCompletions = @[];
    self.searchCompleter = [[MKLocalSearchCompleter alloc] init];
    self.searchCompleter.delegate = self;
    if (@available(iOS 13.0, *)) {
        self.searchCompleter.resultTypes = MKLocalSearchCompleterResultTypeAddress | MKLocalSearchCompleterResultTypeQuery;
    }
}

- (void)buildMapSection {
    self.mapContainer = [[UIView alloc] init];
    self.mapContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.mapContainer.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.mapContainer.layer.cornerRadius = kLSCornerRadius;
    self.mapContainer.layer.cornerCurve = kCACornerCurveContinuous;
    self.mapContainer.clipsToBounds = YES;
    self.mapContainer.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.mapContainer.layer.borderColor = UIColor.separatorColor.CGColor;
    [self.scrollContentView addSubview:self.mapContainer];

    self.mapView = [[MKMapView alloc] initWithFrame:CGRectZero];
    self.mapView.translatesAutoresizingMaskIntoConstraints = NO;
    self.mapView.delegate = self;
    self.mapView.showsUserLocation = ![[PersistenceManager shared] isSpoofingEnabled];
    self.mapView.showsCompass = YES;
    self.mapView.showsScale = YES;
    self.mapView.layoutMargins = UIEdgeInsetsMake(12.0, 12.0, 12.0, 12.0);
    [self.mapContainer addSubview:self.mapView];

    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleMapTap:)];
    UILongPressGestureRecognizer *longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleMapLongPress:)];
    longPressGesture.minimumPressDuration = 0.25;
    [tapGesture requireGestureRecognizerToFail:longPressGesture];
    [self.mapView addGestureRecognizer:tapGesture];
    [self.mapView addGestureRecognizer:longPressGesture];

    self.mapHintLabel = [[UILabel alloc] init];
    self.mapHintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.mapHintLabel.text = @"   اضغط على الخريطة أو اسحب الدبوس   ";
    self.mapHintLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    self.mapHintLabel.textColor = UIColor.labelColor;
    self.mapHintLabel.backgroundColor = [UIColor.secondarySystemBackgroundColor colorWithAlphaComponent:0.92];
    self.mapHintLabel.layer.cornerRadius = 12.0;
    self.mapHintLabel.layer.cornerCurve = kCACornerCurveContinuous;
    self.mapHintLabel.clipsToBounds = YES;
    self.mapHintLabel.textAlignment = NSTextAlignmentCenter;
    [self.mapContainer addSubview:self.mapHintLabel];

    self.mapSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.mapSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.mapSpinner.hidesWhenStopped = YES;
    self.mapSpinner.color = UIColor.systemGrayColor;
    [self.mapContainer addSubview:self.mapSpinner];
}

- (void)buildControlPanel {
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial];
    self.controlPanel = [[UIVisualEffectView alloc] initWithEffect:blur];
    self.controlPanel.translatesAutoresizingMaskIntoConstraints = NO;
    self.controlPanel.layer.cornerRadius = kLSControlPanelCornerRadius;
    self.controlPanel.layer.cornerCurve = kCACornerCurveContinuous;
    self.controlPanel.clipsToBounds = YES;
    self.controlPanel.layer.shadowColor = UIColor.blackColor.CGColor;
    self.controlPanel.layer.shadowOpacity = 0.12;
    self.controlPanel.layer.shadowRadius = 16.0;
    self.controlPanel.layer.shadowOffset = CGSizeMake(0.0, -2.0);
    self.controlPanel.layer.masksToBounds = NO;
    [self.scrollContentView addSubview:self.controlPanel];

    UIView *content = self.controlPanel.contentView;

    self.panelTabSegment = [[UISegmentedControl alloc] initWithItems:@[@"الخريطة", @"المحفوظات"]];
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
    self.coordinateValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:15.0 weight:UIFontWeightMedium];
    self.coordinateValueLabel.textColor = UIColor.labelColor;
    self.coordinateValueLabel.numberOfLines = 2;
    self.coordinateValueLabel.adjustsFontSizeToFitWidth = YES;
    self.coordinateValueLabel.minimumScaleFactor = 0.85;
    [staticPanel addSubview:self.coordinateValueLabel];

    self.bookmarkSaveButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.bookmarkSaveButton.translatesAutoresizingMaskIntoConstraints = NO;
    UIImage *bookmarkImage = [UIImage systemImageNamed:@"bookmark"];
    if (!bookmarkImage) {
        [self.bookmarkSaveButton setTitle:@"★" forState:UIControlStateNormal];
    } else {
        [self.bookmarkSaveButton setImage:bookmarkImage forState:UIControlStateNormal];
    }
    self.bookmarkSaveButton.accessibilityLabel = @"حفظ الموقع";
    [self.bookmarkSaveButton addTarget:self action:@selector(handleBookmarkSaveTapped) forControlEvents:UIControlEventTouchUpInside];
    [staticPanel addSubview:self.bookmarkSaveButton];

    // إضافة زر أداة البلوتوث الجديد بجانب زر المفضلة
    self.bluetoothMenuButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.bluetoothMenuButton.translatesAutoresizingMaskIntoConstraints = NO;
    UIImage *btImage = [UIImage systemImageNamed:@"antenna.radiowaves.left.and.right"];
    if (!btImage) {
        [self.bluetoothMenuButton setTitle:@"BT" forState:UIControlStateNormal];
    } else {
        [self.bluetoothMenuButton setImage:btImage forState:UIControlStateNormal];
    }
    [self.bluetoothMenuButton addTarget:self action:@selector(handleBluetoothMenuTapped) forControlEvents:UIControlEventTouchUpInside];
    [staticPanel addSubview:self.bluetoothMenuButton];

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
    self.headingSlider.tintColor = UIColor.systemBlueColor;
    [self.headingSlider addTarget:self action:@selector(handleHeadingSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [staticPanel addSubview:self.headingSlider];

    self.headingDirectionLabel = [[UILabel alloc] init];
    self.headingDirectionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.headingDirectionLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightRegular];
    self.headingDirectionLabel.textColor = UIColor.tertiaryLabelColor;
    self.headingDirectionLabel.textAlignment = NSTextAlignmentCenter;
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
    self.fluctuationLabel.text = @"التذبذب";
    self.fluctuationLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    self.fluctuationLabel.textColor = UIColor.labelColor;
    [self.fluctuationRow addSubview:self.fluctuationLabel];

    self.fluctuationSwitch = [[UISwitch alloc] init];
    self.fluctuationSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [self.fluctuationSwitch addTarget:self action:@selector(handleFluctuationToggle) forControlEvents:UIControlEventValueChanged];
    [self.fluctuationRow addSubview:self.fluctuationSwitch];

    self.fluctuationRadiusField = [[UITextField alloc] init];
    self.fluctuationRadiusField.translatesAutoresizingMaskIntoConstraints = NO;
    self.fluctuationRadiusField.placeholder = @"نصف القطر (م)";
    self.fluctuationRadiusField.keyboardType = UIKeyboardTypeNumberPad;
    self.fluctuationRadiusField.font = [UIFont monospacedDigitSystemFontOfSize:14.0 weight:UIFontWeightMedium];
    self.fluctuationRadiusField.textColor = UIColor.labelColor;
    self.fluctuationRadiusField.textAlignment = NSTextAlignmentCenter;
    self.fluctuationRadiusField.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.fluctuationRadiusField.layer.cornerRadius = 10.0;
    self.fluctuationRadiusField.layer.cornerCurve = kCACornerCurveContinuous;
    self.fluctuationRadiusField.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.fluctuationRadiusField.layer.borderColor = UIColor.separatorColor.CGColor;
    self.fluctuationRadiusField.delegate = self;
    [self.fluctuationRadiusField addTarget:self action:@selector(handleFluctuationRadiusChanged) forControlEvents:UIControlEventEditingDidEnd];
    [staticPanel addSubview:self.fluctuationRadiusField];

    UIToolbar *fluctuationToolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 0, 44)];
    UIBarButtonItem *flexItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *doneItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismissKeyboard)];
    fluctuationToolbar.items = @[flexItem, doneItem];
    self.fluctuationRadiusField.inputAccessoryView = fluctuationToolbar;

    self.applyButton = [self primaryButtonWithTitle:@"تطبيق الموقع" action:@selector(handleApply)];
    self.cancelButton = [self secondaryButtonWithTitle:@"إلغاء" action:@selector(handleCancel)];
    self.stopButton = [self destructiveOutlineButtonWithTitle:@"إيقاف التزييف" action:@selector(handleStopSpoofing)];

    UIStackView *actionRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.cancelButton, self.applyButton]];
    actionRow.translatesAutoresizingMaskIntoConstraints = NO;
    actionRow.axis = UILayoutConstraintAxisHorizontal;
    actionRow.spacing = 12.0;
    actionRow.distribution = UIStackViewDistributionFillEqually;
    [staticPanel addSubview:actionRow];

    self.actionRow = actionRow;
    [staticPanel addSubview:self.stopButton];
}

#pragma mark - Custom Actions

// الدالة المسؤولة عن تشغيل أداة البلوتوث عند الضغط على الزر الجديد
- (void)handleBluetoothMenuTapped {
    BluetoothSpooferViewController *bluetoothVC = [[BluetoothSpooferViewController alloc] init];
    if (self.navigationController) {
        [self.navigationController pushViewController:bluetoothVC animated:YES];
    } else {
        bluetoothVC.modalPresentationStyle = UIModalPresentationFullScreen;
        [self presentViewController:bluetoothVC animated:YES completion:nil];
    }
}

#pragma mark - Constraints Setup

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
        [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.closeButton.leadingAnchor constant:-12.0],

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

        [self.coordinateModeSegment.topAnchor constraintEqualToAnchor:self.mapControlsContainer.topAnchor],
        [self.coordinateModeSegment.leadingAnchor constraintEqualToAnchor:self.mapControlsContainer.leadingAnchor constant:12.0]
    ]];
}

@end
