#import "MapPickerViewController.h"
#import "MapPickerViewController+Private.h"
#import "XsGpS.h"
#import "OverlayWindow.h"
#import "PersistenceManager.h"
#import "BookmarksManager.h"
#import "RouteSimulator.h"

#import <CoreLocation/CoreLocation.h>
#import <MapKit/MapKit.h>
#import <Security/Security.h>
#import <WebKit/WebKit.h>
#include <stdlib.h>
#include <math.h>
#import "LSActivationManager.h"
#import "LSActivationViewController.h"
#import "LSBookmarksSheetViewController.h"
#import "LSSettingsViewController.h"
#import "ImageSpoofingManager.h"
#import "LSAppIdentifierProvider.h"
#import "LSUUIDResetManager.h"
#import "LSBluetoothScannerViewController.h"
#import "LSWiFiScannerViewController.h"
#import "LSScheduleManager.h"
#import "LSScheduleEditorViewController.h"

static const CGFloat kLSCornerRadius = 20.0;
static const CGFloat kLSHorizontalInset = 10.0;
static const CGFloat kLSFloatingHorizontalMargin = 22.0;
static const CGFloat kLSFloatingHeightMultiplier = 0.90;
static const CGFloat kLSFloatingPanelCornerRadius = 26.0;
static const CGFloat kLSControlPanelCornerRadius = 22.0;
static const CGFloat kLSSuggestionRowHeight = 48.0;
static const CGFloat kLSSuggestionMaxHeight = 240.0;
static const NSInteger kLSSuggestionMaxVisibleRows = 5;
static const CGFloat kLSMapHeightMultiplier = 0.370;
static const NSTimeInterval kLSRealLocationFreshAgeLimit = 30.0;
static const NSTimeInterval kLSRealLocationCachedAgeLimit = 300.0;
static const NSTimeInterval kLSRealLocationLookupTimeout = 8.0;
static const CLLocationAccuracy kLSRealLocationFreshAccuracyLimit = 5000.0;
static const CLLocationAccuracy kLSRealLocationCachedAccuracyLimit = 3000.0;

static inline UIColor *LSMainSurfaceColor(void) {
    return [UIColor colorWithRed:0.055 green:0.060 blue:0.075 alpha:1.0];
}

static inline UIColor *LSInlineToolCardColor(void) {
    return [UIColor colorWithRed:0.12 green:0.13 blue:0.17 alpha:1.0];
}

@interface MapPickerViewController () <MKMapViewDelegate, UISearchBarDelegate, UITextFieldDelegate, MKLocalSearchCompleterDelegate, UITableViewDataSource, UITableViewDelegate, CLLocationManagerDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIButton *settingsButton;
@property (nonatomic, strong) UIButton *imageToolButton;
@property (nonatomic, strong) UIButton *supportButton;
@property (nonatomic, strong) UIStackView *advancedToolsStack;
@property (nonatomic, strong) UISwitch *inlineLocationSwitch;
@property (nonatomic, strong) UISwitch *inlineScheduleSwitch;
@property (nonatomic, strong) UISwitch *inlinePhotoSwitch;
@property (nonatomic, strong) UISwitch *inlineMovementSwitch;
@property (nonatomic, strong) UILabel *inlineScheduleDetailLabel;
@property (nonatomic, strong) UILabel *inlinePhotoDetailLabel;
@property (nonatomic, strong) UILabel *inlineMovementDetailLabel;
@property (nonatomic, assign) BOOL activationPromptVisible;
@property (nonatomic, strong) LSActivationViewController *activationViewController;
@property (nonatomic, assign) BOOL floatingPanelEntranceAnimationPlayed;
@property (nonatomic, assign) BOOL floatingPanelEntranceAnimationPrepared;
@property (nonatomic, assign) BOOL activationMainPanelRevealInProgress;
@property (nonatomic, strong) CLLocationManager *realLocationManager;
@property (nonatomic, assign) BOOL locatingRealLocation;
@property (nonatomic, assign) NSUInteger realLocationLookupGeneration;
@property (nonatomic, assign) BOOL realLocationRequestIssued;
@property (nonatomic, strong) NSError *lastRealLocationError;
@property (nonatomic, strong) UIButton *mapExpandButton;
@property (nonatomic, assign) BOOL mapExpanded;
@property (nonatomic, strong) UITapGestureRecognizer *backgroundDismissTapGesture;
@property (nonatomic, strong) UIPanGestureRecognizer *panelDismissPanGesture;
@property (nonatomic, assign) BOOL panelDismissalInProgress;
@end

@implementation MapPickerViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    BOOL activationLockedAtLaunch = ![[LSActivationManager shared] isActivated];
    self.view.backgroundColor = activationLockedAtLaunch ? UIColor.clearColor : [UIColor colorWithWhite:0.0 alpha:0.22];
    self.view.opaque = NO;
    self.selectedCoordinate = CLLocationCoordinate2DMake(26.4207, 50.0888);
    self.hasSelectedCoordinate = NO;

    PersistenceManager *store = [PersistenceManager shared];
    if ([store isSpoofingEnabled] || [store hasStoredCoordinate]) {
        self.selectedCoordinate = [store spoofCoordinate];
        self.hasSelectedCoordinate = YES;
    }
    self.panelTab = LSMapPickerPanelTabMap;
    self.coordinateMode = LSMapPickerCoordinateModeStatic;
    self.definesPresentationContext = YES;

    [self buildInterface];
    [self buildBookmarksPanel];
    [self installConstraints];
    [self configureKeyboardToolbar];
    [self configureSearchCompleter];
    [self refreshStatusPill];
    [self syncFieldsFromCoordinate];
    if (self.altitudeField) {
        self.altitudeField.text = [NSString stringWithFormat:@"%.0f", store.altitude];
    }
    if (self.headingSlider) {
        self.headingSlider.value = (float)store.heading;
    }
    [self updateHeadingLabel];
    [self updatePanelTabVisibility];
    [self ls_setActivationLockPresentationActive:activationLockedAtLaunch];

    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(ls_keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(ls_keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    LSSetHooksBypassed(![[PersistenceManager shared] isSpoofingEnabled]);
    [LSOverlayManager setMapPickerVisible:YES];
    [self refreshStatusPill];
    [self ls_refreshInlineToolStates];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (![[PersistenceManager shared] isSpoofingEnabled]) {
        LSSetHooksBypassed(YES);
    }
    if (![self ls_presentActivationIfNeeded]) {
        [self configureMapIfNeeded];
        [self restoreSimulationUIIfNeeded];
        [self ls_animateFloatingPanelInIfNeeded];
    }
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
    self.floatingPanelView = [[UIView alloc] init];
    self.floatingPanelView.translatesAutoresizingMaskIntoConstraints = NO;
    self.floatingPanelView.backgroundColor = LSMainSurfaceColor();
    self.floatingPanelView.layer.cornerRadius = kLSFloatingPanelCornerRadius;
    self.floatingPanelView.layer.cornerCurve = kCACornerCurveContinuous;
    self.floatingPanelView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.floatingPanelView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.16].CGColor;
    self.floatingPanelView.layer.shadowColor = UIColor.blackColor.CGColor;
    self.floatingPanelView.layer.shadowOpacity = 0.38;
    self.floatingPanelView.layer.shadowRadius = 28.0;
    self.floatingPanelView.layer.shadowOffset = CGSizeMake(0.0, 14.0);
    self.floatingPanelView.clipsToBounds = NO;
    [self.view addSubview:self.floatingPanelView];

    self.floatingGrabberView = [[UIView alloc] init];
    self.floatingGrabberView.translatesAutoresizingMaskIntoConstraints = NO;
    self.floatingGrabberView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.34];
    self.floatingGrabberView.layer.cornerRadius = 2.5;
    self.floatingGrabberView.layer.cornerCurve = kCACornerCurveContinuous;
    [self.floatingPanelView addSubview:self.floatingGrabberView];

    self.contentScrollView = [[UIScrollView alloc] init];
    self.contentScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentScrollView.alwaysBounceVertical = YES;
    self.contentScrollView.showsVerticalScrollIndicator = NO;
    self.contentScrollView.scrollEnabled = YES;
    self.contentScrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.contentScrollView.clipsToBounds = YES;
    self.contentScrollView.backgroundColor = UIColor.clearColor;
    [self.floatingPanelView addSubview:self.contentScrollView];

    self.scrollContentView = [[UIView alloc] init];
    self.scrollContentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentScrollView addSubview:self.scrollContentView];

    [self buildHeader];
    [self buildSearchBar];
    [self buildQuickActionsRow];
    [self buildMapSection];
    [self buildMapToolsRow];
    [self buildControlPanel];
    [self ls_installPanelDismissGestures];
}

- (void)buildHeader {
    self.headerView = [[UIView alloc] init];
    self.headerView.translatesAutoresizingMaskIntoConstraints = NO;
    self.headerView.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    self.headerView.backgroundColor = [UIColor colorWithRed:0.105 green:0.115 blue:0.145 alpha:0.98];
    self.headerView.layer.cornerRadius = 20.0;
    self.headerView.layer.cornerCurve = kCACornerCurveContinuous;
    self.headerView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.headerView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.08].CGColor;
    [self.scrollContentView addSubview:self.headerView];

    self.navigationIconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"location.north.fill"]];
    self.navigationIconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.navigationIconView.contentMode = UIViewContentModeScaleAspectFit;
    self.navigationIconView.tintColor = UIColor.systemRedColor;
    // السهم يبقى بدون دائرة خلفية؛ اللون يتغير حسب حالة تفعيل الأداة.
    self.navigationIconView.backgroundColor = UIColor.clearColor;
    self.navigationIconView.layer.cornerRadius = 0.0;
    self.navigationIconView.layer.cornerCurve = kCACornerCurveContinuous;
    self.navigationIconView.clipsToBounds = NO;
    [self.headerView addSubview:self.navigationIconView];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.text = @"XsGpS";
    self.titleLabel.font = [UIFont systemFontOfSize:21.0 weight:UIFontWeightBlack];
    self.titleLabel.textColor = UIColor.whiteColor;
    self.titleLabel.accessibilityTraits = UIAccessibilityTraitHeader;
    [self.headerView addSubview:self.titleLabel];

    self.supportButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.supportButton.hidden = YES;
    self.settingsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.settingsButton.hidden = YES;
    self.imageToolButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.imageToolButton.hidden = YES;

    self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.closeButton setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    self.closeButton.tintColor = UIColor.tertiaryLabelColor;
    self.closeButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    self.closeButton.layer.cornerRadius = 15.0;
    self.closeButton.layer.cornerCurve = kCACornerCurveContinuous;
    [self.closeButton addTarget:self action:@selector(handleCancel) forControlEvents:UIControlEventTouchUpInside];
    [self.headerView addSubview:self.closeButton];

    self.statusPill = [[UIView alloc] init];
    self.statusPill.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusPill.layer.cornerRadius = 14.0;
    self.statusPill.layer.cornerCurve = kCACornerCurveContinuous;
    self.statusPill.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    [self.headerView addSubview:self.statusPill];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.font = [UIFont systemFontOfSize:15.2 weight:UIFontWeightBlack];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.adjustsFontSizeToFitWidth = YES;
    self.statusLabel.minimumScaleFactor = 0.62;
    [self.statusPill addSubview:self.statusLabel];

    self.statusDot = [[UIView alloc] init];
    self.statusDot.hidden = YES;
    self.pillStopLabel = [[UILabel alloc] init];
    self.pillStopLabel.hidden = YES;
    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.hidden = YES;
}

- (void)buildSearchBar {
    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchBar.placeholder = @"عنوان، إحداثيات، أو عنوان وطني";
    self.searchBar.delegate = self;
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.backgroundImage = [[UIImage alloc] init];
    self.searchBar.backgroundColor = UIColor.clearColor;
    self.searchBar.tintColor = [UIColor colorWithRed:0.06 green:0.35 blue:0.95 alpha:1.0];
    self.searchBar.layer.shadowColor = UIColor.blackColor.CGColor;
    self.searchBar.layer.shadowOpacity = 0.05;
    self.searchBar.layer.shadowRadius = 10.0;
    self.searchBar.layer.shadowOffset = CGSizeMake(0.0, 4.0);
    if (@available(iOS 13.0, *)) {
        UITextField *tf = self.searchBar.searchTextField;
        tf.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
        tf.textColor = UIColor.whiteColor;
        tf.backgroundColor = [UIColor colorWithRed:0.15 green:0.16 blue:0.20 alpha:1.0];
        tf.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"عنوان، إحداثيات، أو عنوان وطني" attributes:@{NSForegroundColorAttributeName : [UIColor colorWithWhite:1.0 alpha:0.42]}];
        tf.layer.cornerRadius = 15.0;
        tf.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        tf.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.10].CGColor;
        tf.clipsToBounds = YES;
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
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

- (UIButton *)ls_compactActionButtonWithTitle:(NSString *)title systemImageName:(NSString *)imageName tint:(UIColor *)tint {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:[NSString stringWithFormat:@" %@", title] forState:UIControlStateNormal];
    [button setImage:[UIImage systemImageNamed:imageName] forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.tintColor = UIColor.whiteColor;
    button.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightBold];
    button.backgroundColor = [tint colorWithAlphaComponent:0.38];
    button.layer.cornerRadius = 14.0;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    button.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    button.layer.borderColor = [tint colorWithAlphaComponent:0.62].CGColor;
    button.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    button.imageEdgeInsets = UIEdgeInsetsMake(0.0, 3.0, 0.0, -3.0);
    return button;
}

- (void)buildQuickActionsRow {
    self.bookmarkSaveButton = [self ls_compactActionButtonWithTitle:@"حفظ" systemImageName:@"plus.circle.fill" tint:UIColor.systemGreenColor];
    self.bookmarkSaveButton.accessibilityLabel = @"حفظ";
    [self.bookmarkSaveButton addTarget:self action:@selector(handleBookmarkSaveTapped) forControlEvents:UIControlEventTouchUpInside];

    self.bookmarksQuickButton = [self ls_compactActionButtonWithTitle:@"المحفوظات" systemImageName:@"bookmark.fill" tint:[UIColor colorWithRed:0.74 green:0.47 blue:0.10 alpha:1.0]];
    self.bookmarksQuickButton.accessibilityLabel = @"المحفوظات";
    [self.bookmarksQuickButton addTarget:self action:@selector(handleBookmarksQuickTapped) forControlEvents:UIControlEventTouchUpInside];

    UIButton *restore = [self ls_compactActionButtonWithTitle:@"استعادة" systemImageName:@"location.circle.fill" tint:UIColor.systemRedColor];
    [restore addTarget:self action:@selector(handleRestoreOriginalLocationTapped) forControlEvents:UIControlEventTouchUpInside];

    self.quickActionsRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.bookmarksQuickButton, self.bookmarkSaveButton, restore]];
    self.quickActionsRow.translatesAutoresizingMaskIntoConstraints = NO;
    self.quickActionsRow.axis = UILayoutConstraintAxisHorizontal;
    self.quickActionsRow.spacing = 7.0;
    self.quickActionsRow.distribution = UIStackViewDistributionFillEqually;
    self.quickActionsRow.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    [self.scrollContentView addSubview:self.quickActionsRow];
}

- (void)buildMapToolsRow {
    self.locateMeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.locateMeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.locateMeButton setTitle:@" موقعي" forState:UIControlStateNormal];
    [self.locateMeButton setImage:[UIImage systemImageNamed:@"location.fill"] forState:UIControlStateNormal];
    [self.locateMeButton setTitleColor:[UIColor colorWithRed:0.20 green:0.66 blue:1.0 alpha:1.0] forState:UIControlStateNormal];
    self.locateMeButton.tintColor = [UIColor colorWithRed:0.20 green:0.66 blue:1.0 alpha:1.0];
    self.locateMeButton.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightBold];
    self.locateMeButton.backgroundColor = [UIColor colorWithRed:0.10 green:0.22 blue:0.38 alpha:0.92];
    self.locateMeButton.layer.cornerRadius = 14.0;
    self.locateMeButton.layer.cornerCurve = kCACornerCurveContinuous;
    self.locateMeButton.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.locateMeButton.layer.borderColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.45].CGColor;
    self.locateMeButton.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    [self.locateMeButton addTarget:self action:@selector(handleLocateMeTapped) forControlEvents:UIControlEventTouchUpInside];

    self.mapTypeSegment = [[UISegmentedControl alloc] initWithItems:@[@"عادي", @"قمر صناعي"]];
    self.mapTypeSegment.translatesAutoresizingMaskIntoConstraints = NO;
    self.mapTypeSegment.selectedSegmentIndex = 0;
    self.mapTypeSegment.backgroundColor = [UIColor colorWithRed:0.15 green:0.16 blue:0.20 alpha:1.0];
    self.mapTypeSegment.layer.cornerRadius = 14.0;
    self.mapTypeSegment.layer.cornerCurve = kCACornerCurveContinuous;
    self.mapTypeSegment.clipsToBounds = YES;
    if (@available(iOS 13.0, *)) {
        self.mapTypeSegment.selectedSegmentTintColor = UIColor.whiteColor;
    }
    [self.mapTypeSegment setTitleTextAttributes:@{NSForegroundColorAttributeName : UIColor.whiteColor, NSFontAttributeName : [UIFont systemFontOfSize:16.0 weight:UIFontWeightBold]} forState:UIControlStateNormal];
    [self.mapTypeSegment setTitleTextAttributes:@{NSForegroundColorAttributeName : UIColor.blackColor, NSFontAttributeName : [UIFont systemFontOfSize:16.0 weight:UIFontWeightBold]} forState:UIControlStateSelected];
    [self.mapTypeSegment addTarget:self action:@selector(handleMapTypeChanged:) forControlEvents:UIControlEventValueChanged];

    self.mapToolsRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.mapTypeSegment, self.locateMeButton]];
    self.mapToolsRow.translatesAutoresizingMaskIntoConstraints = NO;
    self.mapToolsRow.axis = UILayoutConstraintAxisHorizontal;
    self.mapToolsRow.alignment = UIStackViewAlignmentFill;
    self.mapToolsRow.spacing = 10.0;
    self.mapToolsRow.distribution = UIStackViewDistributionFill;
    self.mapToolsRow.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    [self.scrollContentView addSubview:self.mapToolsRow];
    [self.mapTypeSegment.widthAnchor constraintEqualToConstant:210.0].active = YES;
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
    self.mapContainer.layer.cornerRadius = 24.0;
    self.mapContainer.layer.cornerCurve = kCACornerCurveContinuous;
    self.mapContainer.clipsToBounds = NO;
    self.mapContainer.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.mapContainer.layer.borderColor = UIColor.separatorColor.CGColor;
    self.mapContainer.layer.shadowColor = UIColor.blackColor.CGColor;
    self.mapContainer.layer.shadowOpacity = 0.08;
    self.mapContainer.layer.shadowRadius = 18.0;
    self.mapContainer.layer.shadowOffset = CGSizeMake(0.0, 8.0);
    self.mapContainer.layer.masksToBounds = NO;
    [self.scrollContentView addSubview:self.mapContainer];

    self.mapView = [[MKMapView alloc] initWithFrame:CGRectZero];
    self.mapView.translatesAutoresizingMaskIntoConstraints = NO;
    self.mapView.delegate = self;
    self.mapView.layer.cornerRadius = 24.0;
    self.mapView.layer.cornerCurve = kCACornerCurveContinuous;
    self.mapView.clipsToBounds = YES;
    self.mapView.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.mapView.showsUserLocation = [self ls_shouldShowUserLocationWhileSpoofingDisabled];
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
    self.mapHintLabel.text = @"   اضغط على الخريطة لتحديد الموقع   ";
    self.mapHintLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    self.mapHintLabel.textColor = UIColor.labelColor;
    self.mapHintLabel.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.mapHintLabel.layer.cornerRadius = 12.0;
    self.mapHintLabel.layer.cornerCurve = kCACornerCurveContinuous;
    self.mapHintLabel.clipsToBounds = YES;
    self.mapHintLabel.textAlignment = NSTextAlignmentCenter;
    [self.mapContainer addSubview:self.mapHintLabel];

    self.mapExpandButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.mapExpandButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.mapExpandButton.accessibilityLabel = @"تكبير الخريطة";
    self.mapExpandButton.accessibilityHint = @"يضغط لتكبير مساحة الخريطة أو تصغيرها";
    UIImage *expandImage = [UIImage systemImageNamed:@"arrow.up.left.and.arrow.down.right"];
    if (!expandImage) { expandImage = [UIImage systemImageNamed:@"plus.magnifyingglass"]; }
    [self.mapExpandButton setImage:expandImage forState:UIControlStateNormal];
    [self.mapExpandButton setTitle:nil forState:UIControlStateNormal];
    self.mapExpandButton.tintColor = UIColor.whiteColor;
    self.mapExpandButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.62];
    self.mapExpandButton.layer.cornerRadius = 23.0;
    self.mapExpandButton.layer.cornerCurve = kCACornerCurveContinuous;
    self.mapExpandButton.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.mapExpandButton.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.24].CGColor;
    self.mapExpandButton.contentEdgeInsets = UIEdgeInsetsMake(8.0, 8.0, 8.0, 8.0);
    [self.mapExpandButton addTarget:self action:@selector(handleMapExpandTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.mapContainer addSubview:self.mapExpandButton];

    self.mapSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.mapSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.mapSpinner.hidesWhenStopped = YES;
    self.mapSpinner.color = UIColor.systemGrayColor;
    [self.mapContainer addSubview:self.mapSpinner];
}

- (UIButton *)ls_miniToolButtonWithTitle:(NSString *)title tintColor:(UIColor *)tint action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:tint forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightBlack];
    button.titleLabel.adjustsFontSizeToFitWidth = YES;
    button.titleLabel.minimumScaleFactor = 0.70;
    button.backgroundColor = [tint colorWithAlphaComponent:0.16];
    button.layer.cornerRadius = 14.0;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    button.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    button.layer.borderColor = [tint colorWithAlphaComponent:0.32].CGColor;
    button.contentEdgeInsets = UIEdgeInsetsMake(0.0, 10.0, 0.0, 10.0);
    [button.heightAnchor constraintEqualToConstant:40.0].active = YES;
    if (action != NULL) {
        [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    }
    return button;
}

- (UIView *)ls_featureRowWithTitle:(NSString *)title
                   systemImageName:(NSString *)imageName
                         tintColor:(UIColor *)tint
                       primaryTitle:(NSString *)primaryTitle
                      primaryAction:(SEL)primaryAction
                     secondaryTitle:(NSString *)secondaryTitle
                    secondaryAction:(SEL)secondaryAction
                           switchOn:(BOOL)switchOn
                       switchAction:(SEL)switchAction {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    card.layer.cornerRadius = 18.0;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    card.layer.borderColor = UIColor.separatorColor.CGColor;

    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:imageName]];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.tintColor = tint;
    [card addSubview:iconView];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = title;
    titleLabel.textColor = UIColor.labelColor;
    titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightBlack];
    titleLabel.adjustsFontSizeToFitWidth = YES;
    titleLabel.minimumScaleFactor = 0.78;
    [card addSubview:titleLabel];

    NSMutableArray<UIView *> *controls = [NSMutableArray array];
    if (secondaryTitle.length > 0) {
        [controls addObject:[self ls_miniToolButtonWithTitle:secondaryTitle tintColor:tint action:secondaryAction]];
    }
    if (primaryTitle.length > 0) {
        [controls addObject:[self ls_miniToolButtonWithTitle:primaryTitle tintColor:tint action:primaryAction]];
    }
    if (switchAction != NULL) {
        UISwitch *toggle = [[UISwitch alloc] init];
        toggle.translatesAutoresizingMaskIntoConstraints = NO;
        toggle.on = switchOn;
        toggle.onTintColor = tint;
        [toggle addTarget:self action:switchAction forControlEvents:UIControlEventValueChanged];
        [controls addObject:toggle];
    }

    UIStackView *controlsStack = [[UIStackView alloc] initWithArrangedSubviews:controls];
    controlsStack.translatesAutoresizingMaskIntoConstraints = NO;
    controlsStack.axis = UILayoutConstraintAxisHorizontal;
    controlsStack.alignment = UIStackViewAlignmentCenter;
    controlsStack.spacing = 8.0;
    controlsStack.distribution = UIStackViewDistributionFill;
    [card addSubview:controlsStack];

    [NSLayoutConstraint activateConstraints:@[
        [card.heightAnchor constraintEqualToConstant:47.0],
        [iconView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [iconView.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:30.0],
        [iconView.heightAnchor constraintEqualToConstant:30.0],

        [titleLabel.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor constant:12.0],
        [titleLabel.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:controlsStack.leadingAnchor constant:-8.0],

        [controlsStack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12.0],
        [controlsStack.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [controlsStack.leadingAnchor constraintGreaterThanOrEqualToAnchor:titleLabel.trailingAnchor constant:8.0]
    ]];

    return card;
}

- (UIView *)ls_identifierToolRow {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [UIColor colorWithRed:0.15 green:0.16 blue:0.20 alpha:1.0];
    card.layer.cornerRadius = 18.0;

    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"iphone"]];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.tintColor = UIColor.systemOrangeColor;
    [card addSubview:iconView];

    UILabel *lbl = [[UILabel alloc] init];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    lbl.text = @"معرف الجهاز";
    lbl.textColor = UIColor.whiteColor;
    lbl.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightBold];
    [card addSubview:lbl];

    // هنا تفعيل الأزرار وربطها بالدالات (النسخ، التعبئة، الأصلي)
    UIButton *copyBtn = [self ls_miniToolButtonWithTitle:@"نسخ" tintColor:UIColor.systemOrangeColor action:@selector(handleCopyAppIdentifierTapped)];
    UIButton *fillBtn = [self ls_miniToolButtonWithTitle:@"تعبئة" tintColor:UIColor.systemBlueColor action:@selector(handleFillAppIdentifierTapped)];
    UIButton *restBtn = [self ls_miniToolButtonWithTitle:@"الأصلي" tintColor:UIColor.systemGreenColor action:@selector(handleRestoreAppIdentifierTapped)];

    UIStackView *stk = [[UIStackView alloc] initWithArrangedSubviews:@[restBtn, fillBtn, copyBtn]];
    stk.translatesAutoresizingMaskIntoConstraints = NO;
    stk.axis = UILayoutConstraintAxisHorizontal;
    stk.spacing = 6.0;
    [card addSubview:stk];

    [NSLayoutConstraint activateConstraints:@[
        [card.heightAnchor constraintEqualToConstant:50.0],
        [iconView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14.0],
        [iconView.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:22.0],
        [iconView.heightAnchor constraintEqualToConstant:22.0],
        [lbl.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor constant:10.0],
        [lbl.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [stk.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12.0],
        [stk.centerYAnchor constraintEqualToAnchor:card.centerYAnchor]
    ]];
    return card;
}

- (void)ls_showQuickAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"موافق" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (UIButton *)ls_inlineMiniButton:(NSString *)title tint:(UIColor *)tint action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:tint forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightBold];
    button.backgroundColor = [tint colorWithAlphaComponent:0.15];
    button.layer.cornerRadius = 9.0;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    button.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    button.layer.borderColor = [tint colorWithAlphaComponent:0.45].CGColor;
    [button.heightAnchor constraintEqualToConstant:29.0].active = YES;
    [button.widthAnchor constraintGreaterThanOrEqualToConstant:51.0].active = YES;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (UIView *)ls_inlineToolCardWithTitle:(NSString *)title
                                detail:(NSString *)detail
                            systemImage:(NSString *)systemImage
                                   tint:(UIColor *)tint
                                buttons:(NSArray<UIButton *> *)buttons
                                 toggle:(UISwitch *)toggle {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    // لون موحد بدون حد علوي فاتح حتى لا يظهر الخط الأبيض فوق بطاقة تفعيل الأداة.
    card.backgroundColor = LSInlineToolCardColor();
    card.opaque = NO;
    card.layer.cornerRadius = 15.0;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderWidth = 0.0;
    card.layer.borderColor = UIColor.clearColor.CGColor;
    card.layer.shadowOpacity = 0.0;
    card.layer.masksToBounds = YES;
    card.layer.contentsScale = UIScreen.mainScreen.scale;
    card.clipsToBounds = YES;

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:systemImage]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = tint;
    icon.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:20.0 weight:UIImageSymbolWeightSemibold];
    [card addSubview:icon];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = title;
    titleLabel.textColor = UIColor.whiteColor;
    titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightBold];
    titleLabel.textAlignment = NSTextAlignmentRight;
    titleLabel.adjustsFontSizeToFitWidth = YES;
    titleLabel.minimumScaleFactor = 0.75;
    [card addSubview:titleLabel];

    UILabel *detailLabel = [[UILabel alloc] init];
    detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    detailLabel.text = detail ?: @"";
    detailLabel.hidden = YES;
    detailLabel.tag = 9101;
    [card addSubview:detailLabel];

    UIStackView *buttonsStack = [[UIStackView alloc] initWithArrangedSubviews:buttons ?: @[]];
    buttonsStack.translatesAutoresizingMaskIntoConstraints = NO;
    buttonsStack.axis = UILayoutConstraintAxisHorizontal;
    buttonsStack.spacing = 5.0;
    buttonsStack.alignment = UIStackViewAlignmentCenter;
    buttonsStack.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    [card addSubview:buttonsStack];

    NSLayoutXAxisAnchor *rightAnchor = card.trailingAnchor;
    if (toggle) {
        toggle.translatesAutoresizingMaskIntoConstraints = NO;
        toggle.transform = CGAffineTransformMakeScale(0.92, 0.92);
        toggle.onTintColor = tint;
        [card addSubview:toggle];
        [NSLayoutConstraint activateConstraints:@[
            [toggle.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
            [toggle.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-8.0]
        ]];
        rightAnchor = toggle.leadingAnchor;
    }

    [NSLayoutConstraint activateConstraints:@[
        [card.heightAnchor constraintEqualToConstant:44.0],
        [icon.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12.0],
        [icon.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:21.0],
        [icon.heightAnchor constraintEqualToConstant:21.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:9.0],
        [titleLabel.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:rightAnchor constant:-7.0],
        [buttonsStack.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [buttonsStack.trailingAnchor constraintEqualToAnchor:rightAnchor constant:-7.0],
        [buttonsStack.leadingAnchor constraintGreaterThanOrEqualToAnchor:titleLabel.trailingAnchor constant:6.0]
    ]];
    return card;
}

- (void)buildControlPanel {
    self.controlPanel = [[UIView alloc] init];
    self.controlPanel.translatesAutoresizingMaskIntoConstraints = NO;
    self.controlPanel.layer.cornerRadius = 0.0;
    self.controlPanel.layer.borderWidth = 0.0;
    self.controlPanel.backgroundColor = UIColor.clearColor;
    self.controlPanel.clipsToBounds = NO;
    [self.scrollContentView addSubview:self.controlPanel];

    UIView *content = self.controlPanel;
    self.panelTabSegment = [[UISegmentedControl alloc] initWithItems:@[@"الخريطة", @"المحفوظات"]];
    self.panelTabSegment.translatesAutoresizingMaskIntoConstraints = NO;
    self.panelTabSegment.selectedSegmentIndex = LSMapPickerPanelTabMap;
    self.panelTabSegment.hidden = YES;
    [self.panelTabSegment addTarget:self action:@selector(handlePanelTabChanged:) forControlEvents:UIControlEventValueChanged];
    [content addSubview:self.panelTabSegment];

    self.mapControlsContainer = [[UIView alloc] init];
    self.mapControlsContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:self.mapControlsContainer];

    self.staticControlsContainer = [[UIView alloc] init];
    self.staticControlsContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.staticControlsContainer.backgroundColor = LSMainSurfaceColor();
    self.staticControlsContainer.opaque = YES;
    self.staticControlsContainer.clipsToBounds = YES;
    [self.mapControlsContainer addSubview:self.staticControlsContainer];

    self.routeControlsContainer = [[UIView alloc] init];
    self.routeControlsContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.routeControlsContainer.backgroundColor = LSMainSurfaceColor();
    self.routeControlsContainer.opaque = YES;
    self.routeControlsContainer.hidden = YES;
    [self.mapControlsContainer addSubview:self.routeControlsContainer];

    [self buildRouteControls];

    // أُبقي كـ spacer مخفي للتوافق مع القيود القديمة، بدون أزرار اختيار؛ الأداة تعمل على الموقع الثابت فقط.
    self.coordinateModeSegment = [[UISegmentedControl alloc] init];
    self.coordinateModeSegment.translatesAutoresizingMaskIntoConstraints = NO;
    self.coordinateModeSegment.hidden = YES;
    self.coordinateModeSegment.alpha = 0.0;
    self.coordinateModeSegment.userInteractionEnabled = NO;
    self.coordinateModeSegment.selectedSegmentIndex = UISegmentedControlNoSegment;
    [self.mapControlsContainer addSubview:self.coordinateModeSegment];

    self.applyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.stopButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.stopButton.hidden = ![[PersistenceManager shared] isSpoofingEnabled];

    self.inlineLocationSwitch = [[UISwitch alloc] init];
    [self.inlineLocationSwitch addTarget:self action:@selector(handleInlineLocationSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    UIView *locationCard = [self ls_inlineToolCardWithTitle:@"تفعيل الأداة" detail:nil systemImage:@"power.circle.fill" tint:UIColor.systemGreenColor buttons:@[] toggle:self.inlineLocationSwitch];
    self.inlineLocationSwitch.transform = CGAffineTransformIdentity;
    // نفس شكل بطاقات الأدوات الأخرى؛ زر تفعيل الأداة أصبح بزوايا دائرية.
    locationCard.layer.cornerRadius = 15.0;
    locationCard.layer.cornerCurve = kCACornerCurveContinuous;
    locationCard.layer.masksToBounds = YES;
    locationCard.clipsToBounds = YES;

    self.inlineScheduleSwitch = [[UISwitch alloc] init];
    [self.inlineScheduleSwitch addTarget:self action:@selector(handleScheduleSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    UIButton *scheduleButton = [self ls_inlineMiniButton:@"إعداد" tint:[UIColor colorWithRed:0.22 green:0.74 blue:0.89 alpha:1.0] action:@selector(handleScheduleToolTapped)];
    UIView *scheduleCard = [self ls_inlineToolCardWithTitle:@"جدولة الموقع" detail:@"غير مفعل" systemImage:@"calendar.badge.clock" tint:[UIColor colorWithRed:0.22 green:0.74 blue:0.89 alpha:1.0] buttons:@[scheduleButton] toggle:self.inlineScheduleSwitch];
    self.inlineScheduleDetailLabel = (UILabel *)[scheduleCard viewWithTag:9101];

    // أزرار الصورة البديلة: عرض، رفع، حذف. زر الرفع يفتح الاستديو مباشرة بدون صفحة إضافية.
    self.inlinePhotoSwitch = [[UISwitch alloc] init];
    [self.inlinePhotoSwitch addTarget:self action:@selector(handlePhotoToolSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    UIButton *uploadButton = [self ls_inlineMiniButton:@"رفع" tint:UIColor.systemOrangeColor action:@selector(handleImageToolTapped)];
    UIButton *previewButton = [self ls_inlineMiniButton:@"عرض" tint:UIColor.systemGreenColor action:@selector(handleInlineViewImageTapped)];
    UIButton *deleteButton = [self ls_inlineMiniButton:@"حذف" tint:UIColor.systemRedColor action:@selector(handleClearImageToolTapped)];
    
    // ترتيب الأزرار داخل البطاقة: عرض، رفع، حذف.
    UIView *photoCard = [self ls_inlineToolCardWithTitle:@"صورة بديلة" detail:@"لا توجد صورة" systemImage:@"camera.fill" tint:UIColor.systemOrangeColor buttons:@[previewButton, uploadButton, deleteButton] toggle:self.inlinePhotoSwitch];
    self.inlinePhotoDetailLabel = (UILabel *)[photoCard viewWithTag:9101];

    UIButton *copyUUID = [self ls_inlineMiniButton:@"نسخ" tint:UIColor.systemOrangeColor action:@selector(handleCopyAppIdentifierTapped)];
    UIButton *fillUUID = [self ls_inlineMiniButton:@"تعبئة" tint:[UIColor colorWithRed:0.19 green:0.75 blue:0.94 alpha:1.0] action:@selector(handleFillAppIdentifierTapped)];
    UIButton *restoreUUID = [self ls_inlineMiniButton:@"استعادة الأصل" tint:UIColor.systemGreenColor action:@selector(handleRestoreAppIdentifierTapped)];
    UIView *uuidCard = [self ls_inlineToolCardWithTitle:@"معرف الجهاز" detail:nil systemImage:@"iphone" tint:UIColor.systemOrangeColor buttons:@[copyUUID, fillUUID, restoreUUID] toggle:nil];

    self.actionRow = locationCard;
    [self.staticControlsContainer addSubview:self.actionRow];

    UIView *activationCardTopFill = [[UIView alloc] init];
    activationCardTopFill.translatesAutoresizingMaskIntoConstraints = NO;
    activationCardTopFill.userInteractionEnabled = NO;
    activationCardTopFill.backgroundColor = LSInlineToolCardColor();
    activationCardTopFill.opaque = YES;
    [self.staticControlsContainer addSubview:activationCardTopFill];
    [NSLayoutConstraint activateConstraints:@[
        [activationCardTopFill.topAnchor constraintEqualToAnchor:self.staticControlsContainer.topAnchor],
        [activationCardTopFill.leadingAnchor constraintEqualToAnchor:self.staticControlsContainer.leadingAnchor],
        [activationCardTopFill.trailingAnchor constraintEqualToAnchor:self.staticControlsContainer.trailingAnchor],
        [activationCardTopFill.heightAnchor constraintEqualToConstant:(2.0 / UIScreen.mainScreen.scale)]
    ]];

    self.advancedToolsStack = [[UIStackView alloc] initWithArrangedSubviews:@[scheduleCard, photoCard, uuidCard]];
    self.advancedToolsStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.advancedToolsStack.axis = UILayoutConstraintAxisVertical;
    self.advancedToolsStack.spacing = 3.0;
    [self.staticControlsContainer addSubview:self.advancedToolsStack];
}

- (void)ls_refreshInlineToolStates {
    PersistenceManager *store = [PersistenceManager shared];
    self.inlineLocationSwitch.on = [store isSpoofingEnabled];
    self.inlineScheduleSwitch.on = [LSScheduleManager isEnabled];
    self.inlinePhotoSwitch.on = [ImageSpoofingManager sharedManager].referenceEnabled;
    self.inlineMovementSwitch.on = store.fluctuationEnabled;
    self.inlineScheduleDetailLabel.text = [LSScheduleManager summaryText];
    self.inlinePhotoDetailLabel.text = [[ImageSpoofingManager sharedManager] getSelectedImage] ? @"صورة محفوظة" : @"لا توجد صورة";
    CGFloat radius = store.fluctuationRadius > 0.0 ? store.fluctuationRadius : 100.0;
    self.inlineMovementDetailLabel.text = [NSString stringWithFormat:@"النطاق: %.0f متر", radius];
}

- (void)handleInlineLocationSwitchChanged:(UISwitch *)sender {
    if (sender.isOn) {
        [self handleApply];
    } else {
        [self handleStopSpoofing];
    }
    sender.on = [[PersistenceManager shared] isSpoofingEnabled];
    [self ls_refreshInlineToolStates];
}

#pragma mark - Custom Actions

// دالة لمعاينة وعرض الصورة المخزنة بأمان تام
- (void)handleInlineViewImageTapped {
    UIImage *savedImage = [[ImageSpoofingManager sharedManager] getSelectedImage];

    if (!savedImage) {
        [self ls_showQuickAlertWithTitle:@"لا توجد صورة" message:@"لم يتم اختيار أو رفع صورة بديلة حتى الآن."];
        return;
    }

    UIViewController *previewVC = [[UIViewController alloc] init];
    previewVC.modalPresentationStyle = UIModalPresentationOverFullScreen;
    previewVC.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    previewVC.view.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.46];
    previewVC.view.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;

    UIView *panel = [[UIView alloc] init];
    panel.translatesAutoresizingMaskIntoConstraints = NO;
    panel.backgroundColor = UIColor.blackColor;
    panel.layer.cornerRadius = 30.0;
    panel.layer.cornerCurve = kCACornerCurveContinuous;
    panel.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    panel.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
    panel.layer.shadowColor = UIColor.blackColor.CGColor;
    panel.layer.shadowOpacity = 0.40;
    panel.layer.shadowRadius = 28.0;
    panel.layer.shadowOffset = CGSizeMake(0.0, 14.0);
    panel.clipsToBounds = NO;
    [previewVC.view addSubview:panel];

    UIView *grabber = [[UIView alloc] init];
    grabber.translatesAutoresizingMaskIntoConstraints = NO;
    grabber.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.34];
    grabber.layer.cornerRadius = 2.5;
    grabber.layer.cornerCurve = kCACornerCurveContinuous;
    [panel addSubview:grabber];

    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [closeButton setTitle:@"إغلاق" forState:UIControlStateNormal];
    [closeButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    closeButton.titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightBold];
    [closeButton addTarget:self action:@selector(ls_dismissInlinePreview) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:closeButton];

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"معاينة الصورة البديلة";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont systemFontOfSize:20.0 weight:UIFontWeightBlack];
    title.textAlignment = NSTextAlignmentCenter;
    [panel addSubview:title];

    UIImageView *imageView = [[UIImageView alloc] init];
    imageView.translatesAutoresizingMaskIntoConstraints = NO;
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    imageView.image = savedImage;
    imageView.backgroundColor = UIColor.blackColor;
    imageView.layer.cornerRadius = 22.0;
    imageView.layer.cornerCurve = kCACornerCurveContinuous;
    imageView.clipsToBounds = YES;
    [panel addSubview:imageView];

    UILayoutGuide *safe = previewVC.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [panel.topAnchor constraintEqualToAnchor:safe.topAnchor constant:10.0],
        [panel.leadingAnchor constraintEqualToAnchor:previewVC.view.leadingAnchor constant:14.0],
        [panel.trailingAnchor constraintEqualToAnchor:previewVC.view.trailingAnchor constant:-14.0],
        [panel.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-10.0],

        [grabber.topAnchor constraintEqualToAnchor:panel.topAnchor constant:8.0],
        [grabber.centerXAnchor constraintEqualToAnchor:panel.centerXAnchor],
        [grabber.widthAnchor constraintEqualToConstant:58.0],
        [grabber.heightAnchor constraintEqualToConstant:5.0],

        [closeButton.topAnchor constraintEqualToAnchor:panel.topAnchor constant:20.0],
        [closeButton.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:22.0],
        [closeButton.widthAnchor constraintGreaterThanOrEqualToConstant:70.0],

        [title.topAnchor constraintEqualToAnchor:panel.topAnchor constant:22.0],
        [title.centerXAnchor constraintEqualToAnchor:panel.centerXAnchor],
        [title.leadingAnchor constraintGreaterThanOrEqualToAnchor:closeButton.trailingAnchor constant:8.0],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:panel.trailingAnchor constant:-22.0],

        [imageView.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:14.0],
        [imageView.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:12.0],
        [imageView.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-12.0],
        [imageView.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-14.0]
    ]];

    [self presentViewController:previewVC animated:YES completion:nil];
}

- (void)ls_dismissInlinePreview {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)ls_prepareFloatingPanelEntranceAnimationIfNeeded {
    if (!self.floatingPanelView || self.floatingPanelEntranceAnimationPlayed || self.floatingPanelEntranceAnimationPrepared) {
        return;
    }

    self.floatingPanelEntranceAnimationPrepared = YES;
    self.floatingPanelView.alpha = 0.0;
    self.floatingPanelView.transform = CGAffineTransformConcat(CGAffineTransformMakeTranslation(0.0, 12.0),
                                                               CGAffineTransformMakeScale(0.965, 0.965));
}

- (void)ls_animateFloatingPanelInIfNeeded {
    if (!self.floatingPanelView || self.floatingPanelView.hidden || self.floatingPanelEntranceAnimationPlayed) {
        return;
    }

    if (!self.floatingPanelEntranceAnimationPrepared) {
        [self ls_prepareFloatingPanelEntranceAnimationIfNeeded];
    }

    self.floatingPanelEntranceAnimationPlayed = YES;
    self.floatingPanelEntranceAnimationPrepared = NO;
    [self.view layoutIfNeeded];

    [UIView animateWithDuration:0.24
                          delay:0.0
                        options:(UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState)
                     animations:^{
        self.floatingPanelView.alpha = 1.0;
        self.floatingPanelView.transform = CGAffineTransformIdentity;
    } completion:nil];
}


#pragma mark - Panel Dismiss Gestures

- (void)ls_installPanelDismissGestures {
    if (!self.backgroundDismissTapGesture) {
        self.backgroundDismissTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(ls_handleBackgroundDismissTap:)];
        self.backgroundDismissTapGesture.delegate = self;
        self.backgroundDismissTapGesture.cancelsTouchesInView = YES;
        self.backgroundDismissTapGesture.delaysTouchesBegan = NO;
        self.backgroundDismissTapGesture.delaysTouchesEnded = NO;
        [self.view addGestureRecognizer:self.backgroundDismissTapGesture];
    }

    if (!self.panelDismissPanGesture) {
        self.panelDismissPanGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(ls_handleFloatingPanelGrabberPan:)];
        self.panelDismissPanGesture.delegate = self;
        self.panelDismissPanGesture.maximumNumberOfTouches = 1;
        self.panelDismissPanGesture.cancelsTouchesInView = YES;
        [self.floatingPanelView addGestureRecognizer:self.panelDismissPanGesture];
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if (self.activationPromptVisible || self.activationViewController || self.panelDismissalInProgress || !self.floatingPanelView || self.floatingPanelView.hidden || self.presentedViewController) {
        return NO;
    }

    if (gestureRecognizer == self.backgroundDismissTapGesture) {
        CGPoint panelPoint = [touch locationInView:self.floatingPanelView];
        return !CGRectContainsPoint(self.floatingPanelView.bounds, panelPoint);
    }

    if (gestureRecognizer == self.panelDismissPanGesture) {
        CGPoint panelPoint = [touch locationInView:self.floatingPanelView];
        CGFloat dragHandleHeight = 38.0;
        CGFloat dragHandleHorizontalPadding = 120.0;
        CGFloat panelMidX = CGRectGetMidX(self.floatingPanelView.bounds);
        BOOL withinGrabberVerticalZone = (panelPoint.y >= 0.0 && panelPoint.y <= dragHandleHeight);
        BOOL withinGrabberHorizontalZone = (fabs(panelPoint.x - panelMidX) <= dragHandleHorizontalPadding);
        return CGRectContainsPoint(self.floatingPanelView.bounds, panelPoint) && withinGrabberVerticalZone && withinGrabberHorizontalZone;
    }

    return YES;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == self.panelDismissPanGesture) {
        UIPanGestureRecognizer *pan = (UIPanGestureRecognizer *)gestureRecognizer;
        CGPoint velocity = [pan velocityInView:self.view];
        if (velocity.y <= 0.0 && fabs(velocity.x) > fabs(velocity.y)) {
            return NO;
        }
    }
    return YES;
}

- (void)ls_handleBackgroundDismissTap:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded) {
        return;
    }
    [self ls_dismissToolPanelAnimatedDown];
}

- (void)ls_handleFloatingPanelGrabberPan:(UIPanGestureRecognizer *)gesture {
    if (!self.floatingPanelView || self.panelDismissalInProgress) {
        return;
    }

    CGPoint translation = [gesture translationInView:self.view];
    CGFloat yOffset = MAX(0.0, translation.y);
    CGFloat progress = MIN(1.0, yOffset / 220.0);

    switch (gesture.state) {
        case UIGestureRecognizerStateBegan: {
            [self dismissKeyboard];
            [self.floatingPanelView.layer removeAllAnimations];
            [self.view.layer removeAllAnimations];
            break;
        }
        case UIGestureRecognizerStateChanged: {
            CGFloat scale = 1.0 - (0.018 * progress);
            self.floatingPanelView.transform = CGAffineTransformConcat(CGAffineTransformMakeTranslation(0.0, yOffset),
                                                                       CGAffineTransformMakeScale(scale, scale));
            self.floatingPanelView.alpha = 1.0 - (0.16 * progress);
            self.view.backgroundColor = [UIColor colorWithWhite:0.0 alpha:(0.22 * (1.0 - progress))];
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            CGPoint velocity = [gesture velocityInView:self.view];
            BOOL shouldDismiss = (yOffset > 86.0 || velocity.y > 620.0);
            if (shouldDismiss) {
                [self ls_dismissToolPanelAnimatedDown];
            } else {
                [self ls_restoreFloatingPanelAfterCancelledDrag];
            }
            break;
        }
        default:
            break;
    }
}

- (void)ls_restoreFloatingPanelAfterCancelledDrag {
    if (!self.floatingPanelView) {
        return;
    }

    [UIView animateWithDuration:0.22
                          delay:0.0
         usingSpringWithDamping:0.86
          initialSpringVelocity:0.0
                        options:(UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState)
                     animations:^{
        self.floatingPanelView.alpha = 1.0;
        self.floatingPanelView.transform = CGAffineTransformIdentity;
        self.view.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.22];
    } completion:nil];
}

- (void)ls_dismissToolPanelAnimatedDown {
    if (self.panelDismissalInProgress) {
        return;
    }

    self.panelDismissalInProgress = YES;
    [self dismissKeyboard];
    [self.floatingPanelView.layer removeAllAnimations];
    [self.view.layer removeAllAnimations];

    CGFloat fallbackDistance = self.view.bounds.size.height + 80.0;
    CGFloat panelBottom = CGRectGetMaxY([self.floatingPanelView.superview convertRect:self.floatingPanelView.frame toView:self.view]);
    CGFloat dismissDistance = MAX(260.0, self.view.bounds.size.height - panelBottom + self.floatingPanelView.bounds.size.height + 80.0);
    if (!isfinite(dismissDistance) || dismissDistance <= 0.0) {
        dismissDistance = fallbackDistance;
    }

    [UIView animateWithDuration:0.24
                          delay:0.0
                        options:(UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState)
                     animations:^{
        self.floatingPanelView.alpha = 0.0;
        self.floatingPanelView.transform = CGAffineTransformMakeTranslation(0.0, dismissDistance);
        self.view.backgroundColor = UIColor.clearColor;
    } completion:^(__unused BOOL finished) {
        [LSOverlayManager restoreMapPickerSessionState];
        [self dismissViewControllerAnimated:NO completion:^{
            self.panelDismissalInProgress = NO;
        }];
    }];
}
- (void)ls_forceMainPanelVisibleFinalState {
    self.activationMainPanelRevealInProgress = NO;
    self.view.opaque = NO;
    self.view.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.22];
    self.view.alpha = 1.0;
    self.view.hidden = NO;
    self.floatingPanelView.hidden = NO;
    self.floatingPanelView.alpha = 1.0;
    self.floatingPanelView.transform = CGAffineTransformIdentity;
    self.contentScrollView.hidden = NO;
    self.floatingPanelEntranceAnimationPlayed = YES;
    self.floatingPanelEntranceAnimationPrepared = NO;
    [self.view setNeedsLayout];
}

- (void)ls_revealMainPanelAfterActivationAnimated:(BOOL)animated {
    if (!self.floatingPanelView) {
        return;
    }

    [self ls_setActivationLockPresentationActive:NO];
    [self refreshStatusPill];
    [self configureMapIfNeeded];
    [self restoreSimulationUIIfNeeded];

    if (self.activationMainPanelRevealInProgress) {
        return;
    }

    self.activationMainPanelRevealInProgress = YES;
    self.floatingPanelView.hidden = NO;
    self.contentScrollView.hidden = NO;
    self.floatingPanelEntranceAnimationPlayed = YES;
    self.floatingPanelEntranceAnimationPrepared = NO;

    if (!animated) {
        [self ls_forceMainPanelVisibleFinalState];
        return;
    }

    self.floatingPanelView.alpha = 0.0;
    self.floatingPanelView.transform = CGAffineTransformConcat(CGAffineTransformMakeTranslation(0.0, 12.0),
                                                               CGAffineTransformMakeScale(0.965, 0.965));
    [self.view layoutIfNeeded];

    [UIView animateWithDuration:0.24
                          delay:0.0
                        options:(UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState)
                     animations:^{
        self.floatingPanelView.alpha = 1.0;
        self.floatingPanelView.transform = CGAffineTransformIdentity;
    } completion:^(__unused BOOL finished) {
        [self ls_forceMainPanelVisibleFinalState];
    }];
}


- (void)ls_setActivationLockPresentationActive:(BOOL)active {
    self.view.opaque = NO;
    self.view.backgroundColor = active ? UIColor.clearColor : [UIColor colorWithWhite:0.0 alpha:0.22];
    self.contentScrollView.hidden = active;

    if (active) {
        self.floatingPanelEntranceAnimationPlayed = NO;
        self.floatingPanelEntranceAnimationPrepared = NO;
        self.floatingPanelView.hidden = YES;
        self.floatingPanelView.alpha = 0.0;
        self.floatingPanelView.transform = CGAffineTransformIdentity;
        return;
    }

    self.floatingPanelView.hidden = NO;
    [self ls_prepareFloatingPanelEntranceAnimationIfNeeded];
}

- (void)ls_removeActivationPromptAnimated:(BOOL)animated completion:(void (^)(void))completion {
    LSActivationViewController *activationVC = self.activationViewController;
    if (!activationVC) {
        self.activationPromptVisible = NO;
        if (completion) {
            completion();
        }
        return;
    }

    self.activationViewController = nil;
    self.activationPromptVisible = NO;

    void (^removeBlock)(void) = ^{
        [activationVC willMoveToParentViewController:nil];
        [activationVC.view removeFromSuperview];
        [activationVC removeFromParentViewController];
        if (completion) {
            completion();
        }
    };

    if (!animated) {
        removeBlock();
        return;
    }

    [UIView animateWithDuration:0.14
                          delay:0.0
                        options:(UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState)
                     animations:^{
        activationVC.view.alpha = 0.0;
    } completion:^(__unused BOOL finished) {
        removeBlock();
    }];
}

- (BOOL)ls_presentActivationIfNeeded {
    if ([[LSActivationManager shared] isActivated]) {
        [self ls_removeActivationPromptAnimated:NO completion:nil];
        [self ls_setActivationLockPresentationActive:NO];
        return NO;
    }

    [self ls_setActivationLockPresentationActive:YES];
    if (self.activationPromptVisible || self.activationViewController) {
        return YES;
    }

    self.activationPromptVisible = YES;
    LSActivationViewController *activationVC = [[LSActivationViewController alloc] init];
    activationVC.view.translatesAutoresizingMaskIntoConstraints = NO;
    activationVC.view.backgroundColor = UIColor.clearColor;
    self.activationViewController = activationVC;

    __weak typeof(self) weakSelf = self;
    activationVC.onActivationAccepted = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        // فور نجاح الكود: اكشف شاشة الأداة الآن، بينما كرت التفعيل يختفي فوقها.
        [strongSelf ls_revealMainPanelAfterActivationAnimated:YES];
    };

    activationVC.onActivationSuccess = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        // كرت التفعيل عمل أنيميشن الخروج من داخله؛ هنا نزيل حاوية التفعيل فقط
        // بدون أنيميشن إضافي حتى لا يصير تأخير أو وميض ثاني.
        [strongSelf ls_removeActivationPromptAnimated:NO completion:^{
            [strongSelf ls_forceMainPanelVisibleFinalState];
        }];
    };

    activationVC.onCancel = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        [strongSelf ls_removeActivationPromptAnimated:YES completion:^{
            [strongSelf ls_setActivationLockPresentationActive:YES];
            [LSOverlayManager restoreMapPickerSessionState];
            [strongSelf dismissViewControllerAnimated:NO completion:nil];
        }];
    };

    [self addChildViewController:activationVC];
    [self.view addSubview:activationVC.view];
    [NSLayoutConstraint activateConstraints:@[
        [activationVC.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [activationVC.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [activationVC.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [activationVC.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    [activationVC didMoveToParentViewController:self];
    [activationVC playPresentationAnimationIfNeeded];
    return YES;
}

- (void)handleToolsCenterTapped {
    CGPoint target = CGPointMake(0.0, MAX(0.0, self.controlPanel.frame.origin.y - 12.0));
    [self.contentScrollView setContentOffset:target animated:YES];
}

- (void)handleImageToolTapped {
    ImageSpoofingManager *manager = [ImageSpoofingManager sharedManager];
    __weak typeof(self) weakSelf = self;
    manager.completionHandler = ^(__unused UIImage *image) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf ls_refreshInlineToolStates];
        [strongSelf ls_showQuickAlertWithTitle:@"تم الرفع" message:@"تم اختيار الصورة البديلة وتفعيلها."];
        [ImageSpoofingManager sharedManager].completionHandler = nil;
    };
    [manager openPhotoLibraryFromViewController:self];
}

- (void)handleClearImageToolTapped {
    ImageSpoofingManager *manager = [ImageSpoofingManager sharedManager];
    [manager clearSelectedImage];
    [manager disableReference];
    [self ls_refreshInlineToolStates];
    [self ls_showQuickAlertWithTitle:@"تم الحذف" message:@"تم حذف الصورة البديلة وإيقافها داخل أداة الاختبار."];
}

- (void)handlePhotoToolSwitchChanged:(UISwitch *)sender {
    ImageSpoofingManager *manager = [ImageSpoofingManager sharedManager];
    if (sender.isOn) {
        [manager enableReference];
    } else {
        [manager disableReference];
    }
    [self ls_refreshInlineToolStates];
}

- (NSUserDefaults *)ls_sharedToolDefaults {
    return [[NSUserDefaults alloc] initWithSuiteName:@"com.xsgps.dylib"];
}

- (void)handleScheduleToolTapped {
    if (!self.hasSelectedCoordinate || !CLLocationCoordinate2DIsValid(self.selectedCoordinate)) {
        [self ls_showQuickAlertWithTitle:@"حدد موقعًا أولاً" message:@"اختر موقعًا من الخريطة قبل فتح إعداد الجدولة."];
        return;
    }

    LSScheduleEditorViewController *editor = [[LSScheduleEditorViewController alloc] init];
    editor.selectedCoordinate = self.selectedCoordinate;
    editor.hasSelectedCoordinate = self.hasSelectedCoordinate;
    __weak typeof(self) weakSelf = self;
    editor.onSaved = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.inlineScheduleSwitch.on = [LSScheduleManager isEnabled];
        strongSelf.inlineScheduleDetailLabel.text = [LSScheduleManager summaryText];
    };
    editor.modalPresentationStyle = UIModalPresentationOverFullScreen;
    editor.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [self presentViewController:editor animated:YES completion:nil];
}

- (void)handleScheduleSwitchChanged:(UISwitch *)sender {
    if (sender.isOn && ![LSScheduleManager isEnabled]) {
        sender.on = NO;
        [self handleScheduleToolTapped];
        return;
    }
    [LSScheduleManager setEnabled:sender.isOn];
    self.inlineScheduleDetailLabel.text = [LSScheduleManager summaryText];
}

- (void)handleRandomScopeTapped {
    CGFloat currentRadius = [PersistenceManager shared].fluctuationRadius;
    if (currentRadius <= 0.0) currentRadius = 10.0;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"نطاق الحركة العشوائية"
                                                                   message:@"اكتب المسافة بالمتر أو اختر أحد الخيارات الجاهزة."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"المسافة بالمتر";
        textField.text = [NSString stringWithFormat:@"%.0f", currentRadius];
        textField.keyboardType = UIKeyboardTypeDecimalPad;
        textField.textAlignment = NSTextAlignmentCenter;
    }];

    __weak typeof(self) weakSelf = self;
    void (^applyRadius)(CGFloat) = ^(CGFloat meters) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        CGFloat validRadius = MAX(1.0, MIN(meters, 5000.0));
        [PersistenceManager shared].fluctuationRadius = validRadius;
        NSUserDefaults *defaults = [strongSelf ls_sharedToolDefaults];
        [defaults setDouble:validRadius forKey:@"LSRandomMovementRadius"];
        [defaults synchronize];
        strongSelf.inlineMovementDetailLabel.text = [NSString stringWithFormat:@"النطاق: %.0f متر", validRadius];
    };

    [alert addAction:[UIAlertAction actionWithTitle:@"تطبيق" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction * _Nonnull action) {
        NSString *value = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        CGFloat meters = value.doubleValue;
        if (meters <= 0.0) {
            [weakSelf ls_showQuickAlertWithTitle:@"قيمة غير صحيحة" message:@"أدخل رقمًا أكبر من صفر بالمتر."];
            return;
        }
        applyRadius(meters);
    }]];

    NSArray<NSNumber *> *presets = @[@100, @500, @1000, @5000];
    for (NSNumber *preset in presets) {
        NSString *title = preset.integerValue >= 1000 ? [NSString stringWithFormat:@"%.0f كم", preset.doubleValue / 1000.0] : [NSString stringWithFormat:@"%@ م", preset];
        [alert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction * _Nonnull action) {
            applyRadius(preset.doubleValue);
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)handleRandomMovementSwitchChanged:(UISwitch *)sender {
    [PersistenceManager shared].fluctuationEnabled = sender.isOn;
    NSUserDefaults *defaults = [self ls_sharedToolDefaults];
    [defaults setBool:sender.isOn forKey:@"LSRandomMovementEnabled"];
    [defaults synchronize];
    if (sender.isOn && [PersistenceManager shared].fluctuationRadius <= 0.0) {
        [PersistenceManager shared].fluctuationRadius = 100.0;
    }
    [self ls_refreshInlineToolStates];
}

- (void)handleBluetoothToolTapped {
    LSBluetoothScannerViewController *vc = [[LSBluetoothScannerViewController alloc] init];
    vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
    vc.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)handleWiFiToolTapped {
    LSWiFiScannerViewController *vc = [[LSWiFiScannerViewController alloc] init];
    vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
    vc.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)handleHideToolTapped {
    [self ls_dismissToolPanelAnimatedDown];
}

- (void)handleCopyAppIdentifierTapped {
    NSString *identifier = [LSAppIdentifierProvider applicationIdentifierForClipboard];
    UIPasteboard.generalPasteboard.string = identifier;
    [self ls_showQuickAlertWithTitle:@"تم النسخ" message:[NSString stringWithFormat:@"تم نسخ UUID التطبيق:\n%@", identifier]];
}

- (void)handleFillAppIdentifierTapped {
    NSString *clipboard = (UIPasteboard.generalPasteboard.string ?: @"");
    NSString *normalizedUUID = [LSAppIdentifierProvider normalizedApplicationIdentifier:clipboard];
    if (normalizedUUID.length != 32) {
        [self ls_showQuickAlertWithTitle:@"تعذر التعبئة"
                                 message:@"انسخ UUID صحيح أولاً، ثم اضغط تعبئة. الصيغ المقبولة: 32 خانة بدون شرطات أو UUID بشرطات."];
        return;
    }

    NSString *errorMessage = nil;
    BOOL saved = [LSAppIdentifierProvider saveReplacementApplicationIdentifier:normalizedUUID errorMessage:&errorMessage];
    if (!saved) {
        [self ls_showQuickAlertWithTitle:@"تعذر التعبئة" message:errorMessage ?: @"تعذر حفظ UUID من الحافظة."];
        return;
    }

    // توحيد الحافظة على الصيغة الأساسية التي تعتمدها الأداة حتى يكون النسخ/التفعيل بنفس UUID.
    UIPasteboard.generalPasteboard.string = normalizedUUID;

    BOOL appliedNow = [LSAppIdentifierProvider isReplacementIdentifierAppliedInCurrentProcess];
    NSString *applyStatus = appliedNow ? @"تم التحقق: identifierForVendor داخل العملية الحالية يقرأ UUID الجديد." : @"تم الحفظ. إذا كان التطبيق قرأ UUID القديم مسبقاً، فإعادة التشغيل والتنظيف ستجبر القراءة الجديدة عند الفتح القادم.";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"تمت التعبئة"
                                                                   message:[NSString stringWithFormat:@"تم أخذ UUID من الحافظة واستبداله فعلياً داخل مخزن الأداة:\n%@\n\n%@\n\nعند الضغط على إعادة التشغيل الآن سيتم تنظيف بيانات التطبيق وملفاته المؤقتة والـ Keychain ثم إغلاقه لتطبيق UUID الجديد.", normalizedUUID, applyStatus]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"إعادة التشغيل الآن" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [weakSelf ls_restartApplicationProcess];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (BOOL)ls_shouldPreserveToolFileAtPath:(NSString *)path {
    NSString *name = path.lastPathComponent.lowercaseString ?: @"";
    if ([name hasPrefix:@"com.xsgps."]) {
        return YES;
    }
    if ([name containsString:@"xsgps"]) {
        return YES;
    }
    return NO;
}

- (void)ls_removeContentsAtPath:(NSString *)path preserveToolFiles:(BOOL)preserveToolFiles {
    if (path.length == 0) {
        return;
    }

    NSFileManager *fileManager = NSFileManager.defaultManager;
    BOOL isDirectory = NO;
    if (![fileManager fileExistsAtPath:path isDirectory:&isDirectory] || !isDirectory) {
        return;
    }

    NSArray<NSString *> *children = [fileManager contentsOfDirectoryAtPath:path error:nil] ?: @[];
    for (NSString *child in children) {
        @autoreleasepool {
            NSString *childPath = [path stringByAppendingPathComponent:child];
            if (preserveToolFiles && [self ls_shouldPreserveToolFileAtPath:childPath]) {
                continue;
            }
            [fileManager removeItemAtPath:childPath error:nil];
        }
    }
}

- (void)ls_deleteHostKeychainItemsForUUIDRestart {
    NSArray *classes = @[
        (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecClassInternetPassword,
        (__bridge id)kSecClassCertificate,
        (__bridge id)kSecClassKey,
        (__bridge id)kSecClassIdentity
    ];

    for (id secClass in classes) {
        NSMutableDictionary *query = [@{(__bridge id)kSecClass: secClass} mutableCopy];
        SecItemDelete((__bridge CFDictionaryRef)query);

        query[(__bridge id)kSecAttrSynchronizable] = (__bridge id)kSecAttrSynchronizableAny;
        SecItemDelete((__bridge CFDictionaryRef)query);
    }
}

- (void)ls_clearURLAndWebStorageForUUIDRestart {
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
    [NSHTTPCookieStorage.sharedHTTPCookieStorage.cookies enumerateObjectsUsingBlock:^(NSHTTPCookie *cookie, NSUInteger idx, BOOL *stop) {
        (void)idx;
        (void)stop;
        [NSHTTPCookieStorage.sharedHTTPCookieStorage deleteCookie:cookie];
    }];

    if (@available(iOS 9.0, *)) {
        NSSet *types = [NSSet setWithArray:@[
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeCookies,
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeSessionStorage,
            WKWebsiteDataTypeIndexedDBDatabases,
            WKWebsiteDataTypeWebSQLDatabases
        ]];
        [[WKWebsiteDataStore defaultDataStore] removeDataOfTypes:types modifiedSince:[NSDate distantPast] completionHandler:^{}];
    }
}

- (void)ls_clearHostApplicationDataForUUIDRestart {
    // نحفظ UUID في مخزن الأداة الثابت قبل تنظيف بيانات التطبيق حتى لا يضيع بعد حذف ملفات التطبيق.
    NSString *replacementUUID = [LSAppIdentifierProvider replacementApplicationIdentifier];
    if (replacementUUID.length > 0) {
        NSString *errorMessage = nil;
        [LSAppIdentifierProvider saveReplacementApplicationIdentifier:replacementUUID errorMessage:&errorMessage];
    }

    NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier;
    if (bundleIdentifier.length > 0) {
        [NSUserDefaults.standardUserDefaults removePersistentDomainForName:bundleIdentifier];
        [NSUserDefaults.standardUserDefaults synchronize];
    }

    [self ls_clearURLAndWebStorageForUUIDRestart];

    NSArray<NSString *> *documentsDirectories = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    for (NSString *directory in documentsDirectories) {
        [self ls_removeContentsAtPath:directory preserveToolFiles:NO];
    }

    NSArray<NSString *> *libraryDirectories = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    for (NSString *libraryDirectory in libraryDirectories) {
        NSArray<NSString *> *libraryChildren = [NSFileManager.defaultManager contentsOfDirectoryAtPath:libraryDirectory error:nil] ?: @[];
        for (NSString *child in libraryChildren) {
            NSString *childPath = [libraryDirectory stringByAppendingPathComponent:child];
            if ([child isEqualToString:@"Preferences"]) {
                [self ls_removeContentsAtPath:childPath preserveToolFiles:YES];
            } else {
                [NSFileManager.defaultManager removeItemAtPath:childPath error:nil];
            }
        }
    }

    [self ls_removeContentsAtPath:NSTemporaryDirectory() preserveToolFiles:NO];

    // الأهم: كثير من التطبيقات تحفظ installation id/session في Keychain، وهذا لا ينحذف مع Documents/Library.
    // حذف keychain الحالي يجعل التشغيل القادم أقرب لتثبيت جديد.
    [self ls_deleteHostKeychainItemsForUUIDRestart];

    // إعادة كتابة UUID بعد التنظيف للتأكد أن الهوك يقرأه فور التشغيل التالي.
    if (replacementUUID.length > 0) {
        NSString *errorMessage = nil;
        [LSAppIdentifierProvider saveReplacementApplicationIdentifier:replacementUUID errorMessage:&errorMessage];
    }
}

- (void)ls_restartApplicationProcess {
    [LSUUIDResetManager restartAfterApplyingUUID];
}

- (void)handleRestoreAppIdentifierTapped {
    [LSAppIdentifierProvider clearReplacementApplicationIdentifier];
    [self ls_showQuickAlertWithTitle:@"تمت الاستعادة" message:@"تم الرجوع للمعرّف الأصلي."];
}

- (void)handleRestoreOriginalLocationTapped {
    if ([[PersistenceManager shared] isSpoofingEnabled]) {
        [self handleStopSpoofing];
    }
    LSSetHooksBypassed(YES);
    [self handleLocateMeTapped];
    self.mapHintLabel.text = @"   تم الرجوع إلى موقعك الأصلي   ";
    [self refreshStatusPill];
}

- (void)handleMapExpandTapped {
    self.mapExpanded = !self.mapExpanded;
    self.mapHeightConstraint.active = NO;
    CGFloat multiplier = self.mapExpanded ? 0.86 : kLSMapHeightMultiplier;
    self.mapHeightConstraint = [self.mapContainer.heightAnchor constraintEqualToAnchor:self.floatingPanelView.heightAnchor multiplier:multiplier];
    self.mapHeightConstraint.active = YES;

    NSString *symbolName = self.mapExpanded ? @"arrow.down.right.and.arrow.up.left" : @"arrow.up.left.and.arrow.down.right";
    UIImage *symbol = [UIImage systemImageNamed:symbolName];
    if (!symbol) { symbol = [UIImage systemImageNamed:(self.mapExpanded ? @"minus.magnifyingglass" : @"plus.magnifyingglass")]; }
    self.mapExpandButton.accessibilityLabel = self.mapExpanded ? @"تصغير الخريطة" : @"تكبير الخريطة";
    [self.mapExpandButton setImage:symbol forState:UIControlStateNormal];
    self.mapHintLabel.text = self.mapExpanded ? @"   الخريطة مكبرة — اضغط وحدد بدقة   " : @"   اضغط على الخريطة لتحديد الموقع   ";
    self.contentScrollView.scrollEnabled = YES;

    if (self.mapExpanded) {
        CGFloat top = MAX(0.0, self.mapContainer.frame.origin.y - 6.0);
        [self.contentScrollView setContentOffset:CGPointMake(0.0, top) animated:YES];
    } else {
        [self.contentScrollView setContentOffset:CGPointZero animated:YES];
    }

    [UIView animateWithDuration:0.24 delay:0.0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        [self.view layoutIfNeeded];
    } completion:nil];
}

- (void)handleSettingsTapped {
    PersistenceManager *store = [PersistenceManager shared];
    BOOL active = [store isSpoofingEnabled];
    LSSettingsViewController *settings = [[LSSettingsViewController alloc] initWithSubscriptionText:[LSActivationManager shared].subscriptionStatusText
                                                                                       spoofingActive:active];
    __weak typeof(self) weakSelf = self;
    settings.onClearRecents = ^{
        [[PersistenceManager shared] clearRecentLocations];
    };
    settings.onStopSpoofing = ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf handleStopSpoofing];
    };
    [self presentViewController:settings animated:YES completion:nil];
}

- (void)handleBookmarksQuickTapped {
    NSArray<LSBookmark *> *bookmarks = [[BookmarksManager shared] allBookmarks];

    LSBookmarksSheetViewController *sheet = [[LSBookmarksSheetViewController alloc] initWithBookmarks:bookmarks];
    __weak typeof(self) weakSelf = self;
    sheet.onPreviewCoordinate = ^(CLLocationCoordinate2D coordinate, NSString * _Nullable name) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf movePinToCoordinate:coordinate animated:YES];
        if (name.length > 0) {
            strongSelf.mapHintLabel.text = [NSString stringWithFormat:@"   تم اختيار %@   ", name];
        }
    };
    sheet.onApplyCoordinate = ^(CLLocationCoordinate2D coordinate, NSString * _Nullable name) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        PersistenceManager *store = [PersistenceManager shared];
        if (![store setSpoofCoordinate:coordinate enabled:YES]) {
            [strongSelf playRouteFailureHaptic];
            return;
        }
        [strongSelf playApplyHaptic];
        [strongSelf refreshStatusPill];
        LSSetHooksBypassed(NO);
        [LSOverlayManager restoreMapPickerSessionState];
        [strongSelf dismissViewControllerAnimated:YES completion:nil];
    };
    sheet.onDeleteBookmarkAtIndex = ^(NSUInteger index) {
        [[BookmarksManager shared] removeBookmarkAtIndex:index];
    };
    sheet.onRenameBookmarkAtIndex = ^(NSUInteger index, NSString *newName) {
        [[BookmarksManager shared] renameBookmark:newName atIndex:index];
    };

    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)handleLocateMeTapped {
    [self ls_startRealLocationLookup];
}

- (CLAuthorizationStatus)ls_currentRealLocationAuthorizationStatus {
    if (@available(iOS 14.0, *)) {
        if (self.realLocationManager) {
            return self.realLocationManager.authorizationStatus;
        }
    }
    return [CLLocationManager authorizationStatus];
}

- (BOOL)ls_hostApplicationHasLocationUsageDescription {
    NSBundle *bundle = NSBundle.mainBundle;
    NSArray<NSString *> *keys = @[
        @"NSLocationWhenInUseUsageDescription",
        @"NSLocationAlwaysAndWhenInUseUsageDescription",
        @"NSLocationAlwaysUsageDescription",
        @"NSLocationUsageDescription"
    ];

    for (NSString *key in keys) {
        id value = [bundle objectForInfoDictionaryKey:key];
        if ([value isKindOfClass:NSString.class] && ((NSString *)value).length > 0) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)ls_authorizationAllowsRealLocation:(CLAuthorizationStatus)status {
    return status == kCLAuthorizationStatusAuthorizedWhenInUse ||
           status == kCLAuthorizationStatusAuthorizedAlways ||
           status == kCLAuthorizationStatusAuthorized;
}


- (BOOL)ls_shouldShowUserLocationWhileSpoofingDisabled {
    if ([[PersistenceManager shared] isSpoofingEnabled]) { return NO; }
    if (![CLLocationManager locationServicesEnabled]) { return NO; }

    CLAuthorizationStatus status = [self ls_currentRealLocationAuthorizationStatus];
    if (status == kCLAuthorizationStatusDenied || status == kCLAuthorizationStatusRestricted) { return NO; }

    // إذا كانت الصلاحية غير محددة، لا نسمح لـ MKMapView بطلبها إلا إذا كان التطبيق المضيف يحتوي وصف الصلاحية.
    // هذا يمنع crash في التطبيقات التي لا تملك NSLocationUsageDescription.
    if (status == kCLAuthorizationStatusNotDetermined) {
        return [self ls_hostApplicationHasLocationUsageDescription];
    }

    return [self ls_authorizationAllowsRealLocation:status];
}

- (BOOL)ls_canSafelyTouchRealLocationWithStatus:(CLAuthorizationStatus)status {
    // داخل tweak يتم حقن الأداة في تطبيقات مختلفة. بعض التطبيقات لا تحتوي مفاتيح
    // NSLocationUsageDescription في Info.plist؛ طلب الصلاحية داخل هذه التطبيقات قد يسبب crash من iOS.
    return [self ls_hostApplicationHasLocationUsageDescription] || [self ls_authorizationAllowsRealLocation:status];
}

- (BOOL)ls_isValidRealLocation:(CLLocation *)location allowOldCachedLocation:(BOOL)allowOldCachedLocation {
    if (!location || !CLLocationCoordinate2DIsValid(location.coordinate)) { return NO; }
    if (fabs(location.coordinate.latitude) > 90.0 || fabs(location.coordinate.longitude) > 180.0) { return NO; }

    CLLocationAccuracy horizontalAccuracy = location.horizontalAccuracy;
    if (horizontalAccuracy < 0.0) { return NO; }

    NSTimeInterval age = fabs(location.timestamp.timeIntervalSinceNow);
    NSTimeInterval maxAge = allowOldCachedLocation ? kLSRealLocationCachedAgeLimit : kLSRealLocationFreshAgeLimit;
    CLLocationAccuracy maxAccuracy = allowOldCachedLocation ? kLSRealLocationCachedAccuracyLimit : kLSRealLocationFreshAccuracyLimit;

    if (age > maxAge) { return NO; }
    if (horizontalAccuracy > maxAccuracy) { return NO; }

    return YES;
}

- (nullable CLLocation *)ls_bestRealLocationFromLocations:(NSArray<CLLocation *> *)locations allowOldCachedLocation:(BOOL)allowOldCachedLocation {
    CLLocation *best = nil;
    for (CLLocation *candidate in locations) {
        if (![self ls_isValidRealLocation:candidate allowOldCachedLocation:allowOldCachedLocation]) { continue; }
        if (!best) {
            best = candidate;
            continue;
        }

        NSTimeInterval candidateAge = fabs(candidate.timestamp.timeIntervalSinceNow);
        NSTimeInterval bestAge = fabs(best.timestamp.timeIntervalSinceNow);
        BOOL candidateIsFresh = candidateAge <= kLSRealLocationFreshAgeLimit;
        BOOL bestIsFresh = bestAge <= kLSRealLocationFreshAgeLimit;

        if (candidateIsFresh != bestIsFresh) {
            if (candidateIsFresh) { best = candidate; }
            continue;
        }

        CLLocationAccuracy candidateAccuracy = candidate.horizontalAccuracy;
        CLLocationAccuracy bestAccuracy = best.horizontalAccuracy;
        if (candidateAccuracy >= 0.0 && (bestAccuracy < 0.0 || candidateAccuracy < bestAccuracy)) {
            best = candidate;
            continue;
        }

        if (candidateAge < bestAge) {
            best = candidate;
        }
    }
    return best;
}

- (nullable CLLocation *)ls_cachedRealLocationFallback {
    NSMutableArray<CLLocation *> *candidates = [NSMutableArray array];
    if (self.realLocationManager.location) { [candidates addObject:self.realLocationManager.location]; }
    if (self.mapView.userLocation.location) { [candidates addObject:self.mapView.userLocation.location]; }
    return [self ls_bestRealLocationFromLocations:candidates allowOldCachedLocation:YES];
}

- (void)ls_startRealLocationLookup {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self ls_startRealLocationLookupOnMainThread];
    });
}

- (void)ls_startRealLocationLookupOnMainThread {
    if (![CLLocationManager locationServicesEnabled]) {
        self.mapHintLabel.text = @"   خدمات الموقع غير مفعلة من إعدادات الجهاز   ";
        return;
    }

    if (!self.realLocationManager) {
        self.realLocationManager = [[CLLocationManager alloc] init];
        self.realLocationManager.pausesLocationUpdatesAutomatically = NO;
        if ([self.realLocationManager respondsToSelector:@selector(setActivityType:)]) {
            self.realLocationManager.activityType = CLActivityTypeOther;
        }
    }
    // زر "موقعي" يحتاج إحداثية حقيقية بسرعة، لا جلسة GPS طويلة بدقة مبالغ فيها.
    // kCLLocationAccuracyHundredMeters يجعل CoreLocation يرجع آخر fix صالح أو fix Wi‑Fi/Cell سريع بدل الانتظار الطويل لـ GPS.
    self.realLocationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters;
    self.realLocationManager.distanceFilter = 10.0;
    self.realLocationManager.delegate = self;

    CLAuthorizationStatus status = [self ls_currentRealLocationAuthorizationStatus];
    BOOL canTouchLocation = [self ls_canSafelyTouchRealLocationWithStatus:status];
    if (!canTouchLocation) {
        [self ls_finishRealLocationLookupWithMessage:@"   لا يمكن طلب موقعك الحقيقي داخل هذا التطبيق لأنه لا يحتوي صلاحية موقع في Info.plist   " generation:0];
        return;
    }

    if (status == kCLAuthorizationStatusDenied || status == kCLAuthorizationStatusRestricted) {
        [self ls_finishRealLocationLookupWithMessage:@"   اسمح للأداة باستخدام الموقع من إعدادات التطبيق ثم حاول مرة ثانية   " generation:0];
        return;
    }

    // تجاوز هوك تغيير الموقع مؤقتاً حتى يقرأ زر "موقعي" الموقع الحقيقي وليس الموقع المزيف المحفوظ.
    LSSetHooksBypassed(YES);
    self.realLocationLookupGeneration += 1;
    NSUInteger generation = self.realLocationLookupGeneration;
    self.lastRealLocationError = nil;
    self.realLocationRequestIssued = NO;
    self.locatingRealLocation = YES;

    // المسار السريع: CoreLocation غالباً يملك آخر موقع حقيقي صالح بالفعل.
    // نطبّقه فوراً بدل تشغيل طلب جديد والانتظار حتى timeout، ثم لا نبدأ جلسة تحديث إلا إذا ما وجدنا موقعاً صالحاً.
    CLLocation *instantLocation = [self ls_cachedRealLocationFallback];
    if (instantLocation) {
        [self ls_applyRealLocation:instantLocation generation:generation];
        return;
    }

    self.locateMeButton.enabled = NO;
    self.locateMeButton.alpha = 0.55;
    self.mapView.showsUserLocation = YES;
    self.mapHintLabel.text = @"   جاري تحديد موقعك الحقيقي…   ";
    [self.mapSpinner startAnimating];

    [self ls_requestRealLocationIfAuthorizedForGeneration:generation];

    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kLSRealLocationLookupTimeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.locatingRealLocation || strongSelf.realLocationLookupGeneration != generation) { return; }

        CLLocation *fallback = [strongSelf ls_cachedRealLocationFallback];
        if (fallback) {
            [strongSelf ls_applyRealLocation:fallback generation:generation];
            return;
        }

        // لا نعرض localizedDescription مباشرة للمستخدم؛ kCLErrorLocationUnknown (code 0)
        // خطأ مؤقت شائع وقد ينتج عنه النص غير المفيد: "kCLErrorDomain error 0".
        // إذا لم يصل fix خلال المهلة نعرض رسالة مفهومة فقط، بينما يحتفظ الـ delegate
        // بالأخطاء الحقيقية (مثل denied) لمعالجتها فوراً.
        NSString *message = @"   تعذر تحديد موقعك الآن. تأكد من تفعيل خدمات الموقع والصلاحية ثم حاول مرة ثانية   ";
        [strongSelf ls_finishRealLocationLookupWithMessage:message generation:generation];
    });
}

- (void)ls_requestRealLocationIfAuthorizedForGeneration:(NSUInteger)generation {
    if (!self.locatingRealLocation || self.realLocationLookupGeneration != generation) { return; }

    CLAuthorizationStatus status = [self ls_currentRealLocationAuthorizationStatus];

    if (status == kCLAuthorizationStatusNotDetermined) {
        if (![self ls_hostApplicationHasLocationUsageDescription]) {
            [self ls_finishRealLocationLookupWithMessage:@"   لا يمكن طلب إذن الموقع داخل هذا التطبيق لعدم وجود وصف صلاحية الموقع   " generation:generation];
            return;
        }
        [self.realLocationManager requestWhenInUseAuthorization];
        return;
    }

    if (status == kCLAuthorizationStatusDenied || status == kCLAuthorizationStatusRestricted) {
        [self ls_finishRealLocationLookupWithMessage:@"   اسمح للأداة باستخدام الموقع من إعدادات التطبيق ثم حاول مرة ثانية   " generation:generation];
        return;
    }

    if (![self ls_authorizationAllowsRealLocation:status]) {
        [self ls_finishRealLocationLookupWithMessage:@"   لم يتم منح صلاحية الموقع بعد   " generation:generation];
        return;
    }

    if (self.realLocationRequestIssued) { return; }
    self.realLocationRequestIssued = YES;

    // نستخدم جلسة updates واحدة حتى تستمر المحاولة عند kCLErrorLocationUnknown.
    // الجمع بين startUpdatingLocation و requestLocation ليس مطلوباً هنا؛ الطلب one-shot
    // قد ينتهي بخطأ مؤقت code 0 بينما التحديث المستمر يستطيع إعطاء fix بعد لحظات.
    [self.realLocationManager startUpdatingLocation];
}

- (void)ls_applyRealLocation:(CLLocation *)location generation:(NSUInteger)generation {
    if (!self.locatingRealLocation || self.realLocationLookupGeneration != generation) { return; }

    CLLocation *usableLocation = [self ls_isValidRealLocation:location allowOldCachedLocation:YES] ? location : nil;
    if (!usableLocation) {
        [self ls_finishRealLocationLookupWithMessage:@"   تعذر قراءة الإحداثيات الحقيقية   " generation:generation];
        return;
    }

    [self.realLocationManager stopUpdatingLocation];
    self.locatingRealLocation = NO;
    self.realLocationRequestIssued = NO;
    self.locateMeButton.enabled = YES;
    self.locateMeButton.alpha = 1.0;
    [self.mapSpinner stopAnimating];

    CLLocationCoordinate2D coordinate = usableLocation.coordinate;
    [self movePinToCoordinate:coordinate animated:YES];
    [self.mapView setUserTrackingMode:MKUserTrackingModeNone animated:NO];
    [self.mapView setRegion:MKCoordinateRegionMakeWithDistance(coordinate, 800.0, 800.0) animated:YES];
    self.mapHintLabel.text = @"   تم تحديد موقعك الحقيقي   ";
    [self ls_restoreHookStateAfterRealLocationLookup];
}

- (void)ls_finishRealLocationLookupWithMessage:(NSString *)message generation:(NSUInteger)generation {
    if (generation != 0 && self.realLocationLookupGeneration != generation) { return; }

    [self.realLocationManager stopUpdatingLocation];
    self.locatingRealLocation = NO;
    self.realLocationRequestIssued = NO;
    self.locateMeButton.enabled = YES;
    self.locateMeButton.alpha = 1.0;
    [self.mapSpinner stopAnimating];
    self.mapHintLabel.text = message;
    [self ls_restoreHookStateAfterRealLocationLookup];
}

- (void)ls_restoreHookStateAfterRealLocationLookup {
    BOOL spoofingEnabled = [[PersistenceManager shared] isSpoofingEnabled];
    LSSetHooksBypassed(!spoofingEnabled);
    self.mapView.showsUserLocation = [self ls_shouldShowUserLocationWhileSpoofingDisabled];
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    (void)manager;
    if (!self.locatingRealLocation) { return; }
    NSUInteger generation = self.realLocationLookupGeneration;
    CLLocation *location = [self ls_bestRealLocationFromLocations:locations allowOldCachedLocation:NO];
    if (location) {
        [self ls_applyRealLocation:location generation:generation];
        return;
    }

    CLLocation *fallback = [self ls_bestRealLocationFromLocations:locations allowOldCachedLocation:YES];
    if (fallback) {
        [self ls_applyRealLocation:fallback generation:generation];
        return;
    }
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    (void)manager;
    if (!self.locatingRealLocation) { return; }

    BOOL isCoreLocationError = [error.domain isEqualToString:kCLErrorDomain];
    if (isCoreLocationError && (error.code == kCLErrorDenied || error.code == kCLErrorRegionMonitoringDenied)) {
        self.lastRealLocationError = error;
        [self ls_finishRealLocationLookupWithMessage:@"   تم رفض صلاحية الموقع. فعّلها من إعدادات التطبيق ثم حاول مرة ثانية   " generation:self.realLocationLookupGeneration];
        return;
    }

    // code 0 = kCLErrorLocationUnknown: ليس فشلاً نهائياً. يحصل مؤقتاً عندما CoreLocation
    // لم يملك fix مناسباً بعد. لا نخزنه كآخر خطأ حتى لا يظهر نص النظام الخام في الـ UI.
    if (isCoreLocationError && error.code == kCLErrorLocationUnknown) {
        self.lastRealLocationError = nil;

        // أحياناً يصل cached fix إلى CLLocationManager/MKMapView بالتزامن مع callback الخطأ.
        CLLocation *fallback = [self ls_cachedRealLocationFallback];
        if (fallback) {
            [self ls_applyRealLocation:fallback generation:self.realLocationLookupGeneration];
            return;
        }

        self.mapHintLabel.text = @"   جاري تحديد موقعك الحقيقي…   ";
        return;
    }

    self.lastRealLocationError = error;

    CLLocation *fallback = [self ls_cachedRealLocationFallback];
    if (fallback) {
        [self ls_applyRealLocation:fallback generation:self.realLocationLookupGeneration];
        return;
    }

    self.mapHintLabel.text = @"   تعذر تحديد الموقع الآن، جاري المحاولة…   ";
}

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
    (void)manager;
    if (self.locatingRealLocation) {
        [self ls_requestRealLocationIfAuthorizedForGeneration:self.realLocationLookupGeneration];
    }
}

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
    (void)manager;
    (void)status;
    if (self.locatingRealLocation) {
        [self ls_requestRealLocationIfAuthorizedForGeneration:self.realLocationLookupGeneration];
    }
}

- (void)handleMapTypeChanged:(UISegmentedControl *)sender {
    self.mapView.mapType = sender.selectedSegmentIndex == 1 ? MKMapTypeSatellite : MKMapTypeStandard;
}

#pragma mark - Constraints Setup

- (void)installConstraints {
    UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;
    UIView *panelContent = self.controlPanel;
    UIView *staticPanel = self.staticControlsContainer;

    self.suggestionsHeightConstraint = [self.suggestionsPanel.heightAnchor constraintEqualToConstant:0.0];
    self.panelTabHeightConstraint = [self.panelTabSegment.heightAnchor constraintEqualToConstant:0.0];
    self.coordinateModeHeightConstraint = [self.coordinateModeSegment.heightAnchor constraintEqualToConstant:0.0];
    self.mapHeightConstraint = [self.mapContainer.heightAnchor constraintEqualToAnchor:self.floatingPanelView.heightAnchor multiplier:kLSMapHeightMultiplier];

    self.mapControlsBottomStaticConstraint = [self.advancedToolsStack.bottomAnchor constraintEqualToAnchor:staticPanel.bottomAnchor];
    self.mapControlsBottomStaticNoStopConstraint = [self.advancedToolsStack.bottomAnchor constraintEqualToAnchor:staticPanel.bottomAnchor];
    self.mapControlsBottomRouteConstraint = [self.playRouteButton.bottomAnchor constraintEqualToAnchor:self.routeControlsContainer.bottomAnchor];
    self.mapControlsBottomRouteEarlyConstraint = [self.getRouteButton.bottomAnchor constraintEqualToAnchor:self.routeControlsContainer.bottomAnchor];
    self.mapControlsBottomStaticNoStopConstraint.active = YES;

    [NSLayoutConstraint activateConstraints:@[
        [self.floatingPanelView.centerYAnchor constraintEqualToAnchor:safeArea.centerYAnchor],
        [self.floatingPanelView.heightAnchor constraintEqualToAnchor:safeArea.heightAnchor multiplier:kLSFloatingHeightMultiplier],
        [self.floatingPanelView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:kLSFloatingHorizontalMargin],
        [self.floatingPanelView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-kLSFloatingHorizontalMargin],

        [self.floatingGrabberView.topAnchor constraintEqualToAnchor:self.floatingPanelView.topAnchor constant:8.0],
        [self.floatingGrabberView.centerXAnchor constraintEqualToAnchor:self.floatingPanelView.centerXAnchor],
        [self.floatingGrabberView.widthAnchor constraintEqualToConstant:58.0],
        [self.floatingGrabberView.heightAnchor constraintEqualToConstant:5.0],

        [self.contentScrollView.topAnchor constraintEqualToAnchor:self.floatingPanelView.topAnchor constant:18.0],
        [self.contentScrollView.leadingAnchor constraintEqualToAnchor:self.floatingPanelView.leadingAnchor],
        [self.contentScrollView.trailingAnchor constraintEqualToAnchor:self.floatingPanelView.trailingAnchor],
        [self.contentScrollView.bottomAnchor constraintEqualToAnchor:self.floatingPanelView.bottomAnchor constant:-8.0],

        [self.scrollContentView.topAnchor constraintEqualToAnchor:self.contentScrollView.contentLayoutGuide.topAnchor],
        [self.scrollContentView.leadingAnchor constraintEqualToAnchor:self.contentScrollView.contentLayoutGuide.leadingAnchor],
        [self.scrollContentView.trailingAnchor constraintEqualToAnchor:self.contentScrollView.contentLayoutGuide.trailingAnchor],
        [self.scrollContentView.bottomAnchor constraintEqualToAnchor:self.contentScrollView.contentLayoutGuide.bottomAnchor],
        [self.scrollContentView.widthAnchor constraintEqualToAnchor:self.contentScrollView.frameLayoutGuide.widthAnchor],

        [self.headerView.topAnchor constraintEqualToAnchor:self.scrollContentView.topAnchor constant:7.0],
        [self.headerView.leadingAnchor constraintEqualToAnchor:self.scrollContentView.leadingAnchor constant:kLSHorizontalInset],
        [self.headerView.trailingAnchor constraintEqualToAnchor:self.scrollContentView.trailingAnchor constant:-kLSHorizontalInset],
        [self.headerView.heightAnchor constraintEqualToConstant:44.0],

        [self.navigationIconView.leadingAnchor constraintEqualToAnchor:self.headerView.leadingAnchor constant:10.0],
        [self.navigationIconView.centerYAnchor constraintEqualToAnchor:self.headerView.centerYAnchor],
        [self.navigationIconView.widthAnchor constraintEqualToConstant:32.0],
        [self.navigationIconView.heightAnchor constraintEqualToConstant:32.0],

        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.navigationIconView.trailingAnchor constant:8.0],
        [self.titleLabel.centerYAnchor constraintEqualToAnchor:self.headerView.centerYAnchor],

        [self.closeButton.trailingAnchor constraintEqualToAnchor:self.headerView.trailingAnchor constant:-10.0],
        [self.closeButton.centerYAnchor constraintEqualToAnchor:self.headerView.centerYAnchor],
        [self.closeButton.widthAnchor constraintEqualToConstant:28.0],
        [self.closeButton.heightAnchor constraintEqualToConstant:28.0],

        [self.statusPill.trailingAnchor constraintEqualToAnchor:self.closeButton.leadingAnchor constant:-8.0],
        [self.statusPill.centerYAnchor constraintEqualToAnchor:self.headerView.centerYAnchor],
        [self.statusPill.heightAnchor constraintEqualToConstant:32.0],
        [self.statusPill.widthAnchor constraintGreaterThanOrEqualToConstant:162.0],
        [self.statusPill.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.titleLabel.trailingAnchor constant:4.0],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.statusPill.leadingAnchor constant:8.0],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.statusPill.trailingAnchor constant:-8.0],
        [self.statusLabel.centerYAnchor constraintEqualToAnchor:self.statusPill.centerYAnchor],

        [self.searchBar.topAnchor constraintEqualToAnchor:self.headerView.bottomAnchor constant:7.0],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:self.scrollContentView.leadingAnchor constant:kLSHorizontalInset],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:self.scrollContentView.trailingAnchor constant:-kLSHorizontalInset],
        [self.searchBar.heightAnchor constraintEqualToConstant:36.0],

        [self.searchSpinner.centerYAnchor constraintEqualToAnchor:self.searchBar.centerYAnchor],
        [self.searchSpinner.trailingAnchor constraintEqualToAnchor:self.searchBar.trailingAnchor constant:-16.0],

        [self.suggestionsPanel.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor constant:2.0],
        [self.suggestionsPanel.leadingAnchor constraintEqualToAnchor:self.searchBar.leadingAnchor],
        [self.suggestionsPanel.trailingAnchor constraintEqualToAnchor:self.searchBar.trailingAnchor],
        self.suggestionsHeightConstraint,

        [self.suggestionsTableView.topAnchor constraintEqualToAnchor:self.suggestionsPanel.topAnchor],
        [self.suggestionsTableView.leadingAnchor constraintEqualToAnchor:self.suggestionsPanel.leadingAnchor],
        [self.suggestionsTableView.trailingAnchor constraintEqualToAnchor:self.suggestionsPanel.trailingAnchor],
        [self.suggestionsTableView.bottomAnchor constraintEqualToAnchor:self.suggestionsPanel.bottomAnchor],

        [self.quickActionsRow.topAnchor constraintEqualToAnchor:self.suggestionsPanel.bottomAnchor constant:6.0],
        [self.quickActionsRow.leadingAnchor constraintEqualToAnchor:self.scrollContentView.leadingAnchor constant:kLSHorizontalInset],
        [self.quickActionsRow.trailingAnchor constraintEqualToAnchor:self.scrollContentView.trailingAnchor constant:-kLSHorizontalInset],
        [self.quickActionsRow.heightAnchor constraintEqualToConstant:36.0],

        [self.mapContainer.topAnchor constraintEqualToAnchor:self.quickActionsRow.bottomAnchor constant:7.0],
        [self.mapContainer.leadingAnchor constraintEqualToAnchor:self.scrollContentView.leadingAnchor constant:kLSHorizontalInset],
        [self.mapContainer.trailingAnchor constraintEqualToAnchor:self.scrollContentView.trailingAnchor constant:-kLSHorizontalInset],
        self.mapHeightConstraint,

        [self.mapView.topAnchor constraintEqualToAnchor:self.mapContainer.topAnchor],
        [self.mapView.leadingAnchor constraintEqualToAnchor:self.mapContainer.leadingAnchor],
        [self.mapView.trailingAnchor constraintEqualToAnchor:self.mapContainer.trailingAnchor],
        [self.mapView.bottomAnchor constraintEqualToAnchor:self.mapContainer.bottomAnchor],
        [self.mapHintLabel.bottomAnchor constraintEqualToAnchor:self.mapContainer.bottomAnchor constant:-12.0],
        [self.mapHintLabel.centerXAnchor constraintEqualToAnchor:self.mapContainer.centerXAnchor],
        [self.mapExpandButton.topAnchor constraintEqualToAnchor:self.mapView.topAnchor constant:12.0],
        [self.mapExpandButton.leadingAnchor constraintEqualToAnchor:self.mapView.leadingAnchor constant:12.0],
        [self.mapExpandButton.heightAnchor constraintEqualToConstant:46.0],
        [self.mapExpandButton.widthAnchor constraintEqualToConstant:46.0],
        [self.mapSpinner.centerXAnchor constraintEqualToAnchor:self.mapContainer.centerXAnchor],
        [self.mapSpinner.centerYAnchor constraintEqualToAnchor:self.mapContainer.centerYAnchor],

        [self.mapToolsRow.topAnchor constraintEqualToAnchor:self.mapContainer.bottomAnchor constant:7.0],
        [self.mapToolsRow.leadingAnchor constraintEqualToAnchor:self.scrollContentView.leadingAnchor constant:kLSHorizontalInset],
        [self.mapToolsRow.trailingAnchor constraintEqualToAnchor:self.scrollContentView.trailingAnchor constant:-kLSHorizontalInset],
        [self.mapToolsRow.heightAnchor constraintEqualToConstant:36.0],

        [self.controlPanel.topAnchor constraintEqualToAnchor:self.mapToolsRow.bottomAnchor constant:6.0],
        [self.controlPanel.leadingAnchor constraintEqualToAnchor:self.scrollContentView.leadingAnchor constant:kLSHorizontalInset],
        [self.controlPanel.trailingAnchor constraintEqualToAnchor:self.scrollContentView.trailingAnchor constant:-kLSHorizontalInset],
        [self.controlPanel.bottomAnchor constraintEqualToAnchor:self.scrollContentView.bottomAnchor constant:-10.0],

        [self.panelTabSegment.topAnchor constraintEqualToAnchor:panelContent.topAnchor],
        [self.panelTabSegment.leadingAnchor constraintEqualToAnchor:panelContent.leadingAnchor],
        [self.panelTabSegment.trailingAnchor constraintEqualToAnchor:panelContent.trailingAnchor],
        self.panelTabHeightConstraint,

        [self.mapControlsContainer.topAnchor constraintEqualToAnchor:panelContent.topAnchor constant:0.0],
        [self.mapControlsContainer.leadingAnchor constraintEqualToAnchor:panelContent.leadingAnchor constant:0.0],
        [self.mapControlsContainer.trailingAnchor constraintEqualToAnchor:panelContent.trailingAnchor constant:0.0],
        [self.mapControlsContainer.bottomAnchor constraintEqualToAnchor:panelContent.bottomAnchor constant:0.0],

        [self.staticControlsContainer.topAnchor constraintEqualToAnchor:self.mapControlsContainer.topAnchor constant:0.0],
        [self.staticControlsContainer.leadingAnchor constraintEqualToAnchor:self.mapControlsContainer.leadingAnchor],
        [self.staticControlsContainer.trailingAnchor constraintEqualToAnchor:self.mapControlsContainer.trailingAnchor],
        [self.staticControlsContainer.bottomAnchor constraintEqualToAnchor:self.mapControlsContainer.bottomAnchor],

        [self.routeControlsContainer.topAnchor constraintEqualToAnchor:self.mapControlsContainer.topAnchor constant:0.0],
        [self.routeControlsContainer.leadingAnchor constraintEqualToAnchor:self.mapControlsContainer.leadingAnchor],
        [self.routeControlsContainer.trailingAnchor constraintEqualToAnchor:self.mapControlsContainer.trailingAnchor],
        [self.routeControlsContainer.bottomAnchor constraintEqualToAnchor:self.mapControlsContainer.bottomAnchor],

        [self.coordinateModeSegment.topAnchor constraintEqualToAnchor:self.mapControlsContainer.topAnchor],
        [self.coordinateModeSegment.leadingAnchor constraintEqualToAnchor:self.mapControlsContainer.leadingAnchor],
        [self.coordinateModeSegment.trailingAnchor constraintEqualToAnchor:self.mapControlsContainer.trailingAnchor],
        self.coordinateModeHeightConstraint,

        [self.bookmarksContainer.topAnchor constraintEqualToAnchor:panelContent.topAnchor],
        [self.bookmarksContainer.leadingAnchor constraintEqualToAnchor:panelContent.leadingAnchor],
        [self.bookmarksContainer.trailingAnchor constraintEqualToAnchor:panelContent.trailingAnchor],
        [self.bookmarksContainer.bottomAnchor constraintEqualToAnchor:panelContent.bottomAnchor],

        [self.actionRow.topAnchor constraintEqualToAnchor:staticPanel.topAnchor],
        [self.actionRow.leadingAnchor constraintEqualToAnchor:staticPanel.leadingAnchor],
        [self.actionRow.trailingAnchor constraintEqualToAnchor:staticPanel.trailingAnchor],
        [self.advancedToolsStack.topAnchor constraintEqualToAnchor:self.actionRow.bottomAnchor constant:4.0],
        [self.advancedToolsStack.leadingAnchor constraintEqualToAnchor:staticPanel.leadingAnchor],
        [self.advancedToolsStack.trailingAnchor constraintEqualToAnchor:staticPanel.trailingAnchor]
    ]];

    [self ls_installRouteConstraintsInRoutePanel];
}

@end
