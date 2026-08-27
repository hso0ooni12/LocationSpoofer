#import "MapPickerViewController.h"
#import "RouteSimulator.h"

#import <MapKit/MapKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, LSMapPickerPanelTab) {
    LSMapPickerPanelTabMap = 0,
    LSMapPickerPanelTabBookmarks = 1
};

typedef NS_ENUM(NSInteger, LSMapPickerCoordinateMode) {
    LSMapPickerCoordinateModeStatic = 0,
    LSMapPickerCoordinateModeRoute = 1
};

typedef NS_ENUM(NSInteger, LSRoutePlacementPhase) {
    LSRoutePlacementPhaseStart = 0,
    LSRoutePlacementPhaseDestination = 1
};

@interface LSStartAnnotation : MKPointAnnotation
@end

@interface LSDestinationAnnotation : MKPointAnnotation
@end

@interface MapPickerViewController ()

@property (nonatomic, strong) UIView *floatingPanelView;
@property (nonatomic, strong) UIView *floatingGrabberView;
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIImageView *navigationIconView;
@property (nonatomic, strong) UIView *statusPill;
@property (nonatomic, strong) UIView *statusDot;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UILabel *pillStopLabel;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UIStackView *quickActionsRow;
@property (nonatomic, strong) UIButton *bookmarksQuickButton;
@property (nonatomic, strong) UIStackView *mapToolsRow;
@property (nonatomic, strong) UIButton *locateMeButton;
@property (nonatomic, strong) UISegmentedControl *mapTypeSegment;
@property (nonatomic, strong) UIActivityIndicatorView *searchSpinner;
@property (nonatomic, strong) MKLocalSearchCompleter *searchCompleter;
@property (nonatomic, strong) NSArray<MKLocalSearchCompletion *> *searchCompletions;
@property (nonatomic, strong) UIView *suggestionsPanel;
@property (nonatomic, strong) UITableView *suggestionsTableView;
@property (nonatomic, strong) NSLayoutConstraint *suggestionsHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *mapHeightConstraint;
@property (nonatomic, assign) BOOL searchSuggestionsVisible;
@property (nonatomic, strong) UIScrollView *contentScrollView;
@property (nonatomic, strong) UIView *scrollContentView;
@property (nonatomic, strong) UIView *mapContainer;
@property (nonatomic, strong) MKMapView *mapView;
@property (nonatomic, strong) UILabel *mapHintLabel;
@property (nonatomic, strong) UIActivityIndicatorView *mapSpinner;
@property (nonatomic, strong) UIView *controlPanel;
@property (nonatomic, strong) UISegmentedControl *panelTabSegment;
@property (nonatomic, strong) UISegmentedControl *coordinateModeSegment;
@property (nonatomic, strong) NSLayoutConstraint *panelTabHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *coordinateModeHeightConstraint;
@property (nonatomic, strong) UIView *mapControlsContainer;
@property (nonatomic, strong) UIView *staticControlsContainer;
@property (nonatomic, strong) UIView *routeControlsContainer;
@property (nonatomic, strong) UIView *bookmarksContainer;
@property (nonatomic, strong) UITableView *bookmarksTableView;
@property (nonatomic, strong) UILabel *coordinateTitleLabel;
@property (nonatomic, strong) UILabel *coordinateValueLabel;
@property (nonatomic, strong) UIButton *bookmarkSaveButton;
@property (nonatomic, strong) UIView *separatorCoordFields;
@property (nonatomic, strong) UIView *separatorFieldsHeading;
@property (nonatomic, strong) UIView *separatorHeadingActions;
@property (nonatomic, strong) UIStackView *fieldStack;
@property (nonatomic, strong) UITextField *latitudeField;
@property (nonatomic, strong) UITextField *longitudeField;
@property (nonatomic, strong) UITextField *altitudeField;
@property (nonatomic, strong) UISlider *headingSlider;
@property (nonatomic, strong) UILabel *headingValueLabel;
@property (nonatomic, strong) UILabel *headingDirectionLabel;
@property (nonatomic, strong) UIButton *applyButton;
@property (nonatomic, strong) UIButton *cancelButton;
@property (nonatomic, strong) UIButton *stopButton;
@property (nonatomic, strong) UIView *actionRow;
@property (nonatomic, strong) NSLayoutConstraint *stopButtonHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *mapControlsBottomStaticConstraint;
@property (nonatomic, strong) NSLayoutConstraint *mapControlsBottomStaticNoStopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *mapControlsBottomRouteConstraint;
@property (nonatomic, strong) NSLayoutConstraint *mapControlsBottomRouteEarlyConstraint;
@property (nonatomic, strong) MKPointAnnotation *pinAnnotation;
@property (nonatomic, strong, nullable) LSStartAnnotation *startAnnotation;
@property (nonatomic, strong, nullable) LSDestinationAnnotation *destinationAnnotation;
@property (nonatomic, assign) LSRoutePlacementPhase routePlacementPhase;
@property (nonatomic, strong, nullable) MKRoute *fetchedRoute;
@property (nonatomic, strong, nullable) MKPolyline *routePolyline;
@property (nonatomic, strong) UIButton *getRouteButton;
@property (nonatomic, strong) UISegmentedControl *transportModeSegment;
@property (nonatomic, strong) UITextField *customSpeedField;
@property (nonatomic, strong) UIButton *playRouteButton;
@property (nonatomic, strong) UIActivityIndicatorView *routeSpinner;
@property (nonatomic, strong) UIButton *pauseRouteButton;
@property (nonatomic, strong) UIButton *stopRouteButton;
@property (nonatomic, strong) UIStackView *routeActionRow;
@property (nonatomic, strong) NSLayoutConstraint *customSpeedHeightConstraint;
@property (nonatomic, assign) CLLocationCoordinate2D selectedCoordinate;
@property (nonatomic, assign) BOOL hasSelectedCoordinate;
@property (nonatomic, assign) BOOL mapConfigured;
@property (nonatomic, assign) BOOL suppressFieldSync;
@property (nonatomic, assign) LSMapPickerPanelTab panelTab;
@property (nonatomic, assign) LSMapPickerCoordinateMode coordinateMode;
@property (nonatomic, assign) BOOL bookmarksEditMode;


// Core helpers used by MapPickerViewController.m
- (BOOL)ls_presentActivationIfNeeded;
- (void)configureKeyboardToolbar;
- (void)configureMapIfNeeded;
- (UIView *)ls_separatorView;
- (UIView *)coordinateFieldWithTitle:(NSString *)title placeholder:(NSString *)placeholder textField:(UITextField **)textField;
- (UIButton *)primaryButtonWithTitle:(NSString *)title action:(SEL)action;
- (UIButton *)secondaryButtonWithTitle:(NSString *)title action:(SEL)action;
- (UIButton *)destructiveOutlineButtonWithTitle:(NSString *)title action:(SEL)action;
- (void)handleStatusPillTapped;
- (void)handleToolsCenterTapped;
- (void)handleApply;
- (void)handleCancel;
- (void)ls_dismissToolPanelAnimatedDown;
- (void)handleStopSpoofing;
- (void)handleBookmarksQuickTapped;
- (void)handleLocateMeTapped;
- (void)handleRestoreOriginalLocationTapped;
- (BOOL)ls_shouldShowUserLocationWhileSpoofingDisabled;
- (void)handleMapTypeChanged:(UISegmentedControl *)sender;
- (void)textFieldDidChange:(UITextField *)textField;
- (void)ls_keyboardWillShow:(NSNotification *)notification;
- (void)ls_keyboardWillHide:(NSNotification *)notification;
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText;
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar;
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView;
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section;
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section;
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section;
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath;
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath;
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath;
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath;
- (void)completerDidUpdateResults:(MKLocalSearchCompleter *)completer;
- (void)completer:(MKLocalSearchCompleter *)completer didFailWithError:(NSError *)error;
- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id<MKAnnotation>)annotation;
- (MKOverlayRenderer *)mapView:(MKMapView *)mapView rendererForOverlay:(id<MKOverlay>)overlay;
- (void)mapView:(MKMapView *)mapView annotationView:(MKAnnotationView *)view didChangeDragState:(MKAnnotationViewDragState)newState fromOldState:(MKAnnotationViewDragState)oldState;

- (void)refreshStatusPill;
- (void)syncFieldsFromCoordinate;
- (void)updateCoordinateLabel;
- (void)movePinToCoordinate:(CLLocationCoordinate2D)coordinate animated:(BOOL)animated;
- (void)updatePinOnMapAnimated:(BOOL)animated;
- (nullable NSNumber *)ls_parsedCoordinateComponentFromText:(NSString *)text;
- (BOOL)applyFieldsToCoordinate;
- (BOOL)applyAltitudeField;
- (void)updateHeadingLabel;
- (void)showInvalidCoordinateFeedback;
- (void)playApplyHaptic;
- (void)playRouteSuccessHaptic;
- (void)playRouteFailureHaptic;
- (void)playBookmarkSavedHaptic;
- (void)playSimulationStopHaptic;
- (void)dismissKeyboard;
- (void)handleMapTap:(UITapGestureRecognizer *)gesture;
- (void)handleMapLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)handleHeadingSliderChanged:(UISlider *)sender;

// Extra route/bookmark helpers implemented in category files.
- (void)ls_clearRouteAnnotationsAndOverlay;
- (MKDirectionsTransportType)ls_directionsTransportType;
- (LSTransportMode)ls_selectedTransportMode;
- (void)ls_updateCustomSpeedVisibility;
- (void)ls_updateRoutePlaybackButtons;
- (UIButton *)ls_primaryButtonWithTitle:(NSString *)title action:(SEL)action;
- (UIButton *)ls_secondaryButtonWithTitle:(NSString *)title action:(SEL)action;

- (BOOL)ls_buildAndShowDirectFallbackRouteWithMessage:(NSString *)message;
- (void)ls_applyFetchedRoutePolyline:(MKPolyline *)polyline statusMessage:(NSString *)message;
- (void)ls_fetchRouteWithTransportType:(MKDirectionsTransportType)transportType allowRetry:(BOOL)allowRetry;
- (void)handleGetRouteTapped;
- (void)handleTransportModeChanged:(UISegmentedControl *)sender;
- (void)handlePlayRouteTapped;
- (void)handlePauseRouteTapped;
- (void)handleStopRouteTapped;
- (void)ls_handleBookmarksLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)ls_toggleBookmarksEditMode;
- (void)ls_applyBookmarkFromButton:(UIButton *)sender;

@end

@interface MapPickerViewController (LSRouteUI) <LSRouteSimulatorDelegate>

- (void)buildRouteControls;
- (void)ls_handleRouteMapTap:(CLLocationCoordinate2D)coordinate;
- (void)updateCoordinateModeVisibility;
- (void)ls_updateMapControlsBottomConstraint;
- (void)restoreSimulationUIIfNeeded;
- (void)restoreRouteUIFromSimulator;
- (void)ls_installRouteConstraintsInRoutePanel;
- (MKOverlayRenderer *)ls_rendererForMapOverlay:(id<MKOverlay>)overlay;
- (nullable MKAnnotationView *)ls_viewForRouteAnnotation:(id<MKAnnotation>)annotation;
- (void)ls_routeAnnotationDragEnded:(MKAnnotationView *)view;

@end

@interface MapPickerViewController (LSBookmarksUI)

- (void)buildBookmarksPanel;
- (void)updatePanelTabVisibility;
- (void)handlePanelTabChanged:(UISegmentedControl *)sender;
- (void)handleCoordinateModeChanged:(UISegmentedControl *)sender;
- (void)handleBookmarkSaveTapped;
- (void)presentSaveBookmarkAlertWithSuggestedName:(nullable NSString *)name coordinate:(CLLocationCoordinate2D)coordinate;
- (BOOL)ls_isBookmarksTableView:(UITableView *)tableView;
- (NSInteger)ls_bookmarksNumberOfSections;
- (NSInteger)ls_bookmarksNumberOfRowsInSection:(NSInteger)section;
- (NSString *)ls_bookmarksTitleForHeaderInSection:(NSInteger)section;
- (UITableViewCell *)ls_bookmarksCellForRowAtIndexPath:(NSIndexPath *)indexPath;
- (void)ls_bookmarksDidSelectRowAtIndexPath:(NSIndexPath *)indexPath;
- (BOOL)ls_bookmarksCanEditRowAtIndexPath:(NSIndexPath *)indexPath;
- (void)ls_bookmarksCommitDeleteAtIndexPath:(NSIndexPath *)indexPath;
- (BOOL)ls_bookmarksCanMoveRowAtIndexPath:(NSIndexPath *)indexPath;
- (void)ls_bookmarksMoveFromIndexPath:(NSIndexPath *)source toIndexPath:(NSIndexPath *)destination;
- (UIView *)ls_bookmarksHeaderForSection:(NSInteger)section;
- (void)ls_presentStaticMapActionSheetAtCoordinate:(CLLocationCoordinate2D)coordinate;

@end

NS_ASSUME_NONNULL_END
