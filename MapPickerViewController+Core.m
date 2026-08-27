#import "MapPickerViewController+Private.h"
#import "XsGpS.h"
#import "OverlayWindow.h"
#import "PersistenceManager.h"
#import "RouteSimulator.h"
#import "LSActivationManager.h"

#import <CoreLocation/CoreLocation.h>
#import <MapKit/MapKit.h>
#import <math.h>

@implementation MapPickerViewController (LSCoreUI)

#pragma mark - Setup helpers

- (void)configureKeyboardToolbar {
    UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 0, 44.0)];
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismissKeyboard)];
    toolbar.items = @[flex, done];

    NSArray<UITextField *> *fields = @[
        self.customSpeedField ?: (UITextField *)[NSNull null]
    ];

    for (id object in fields) {
        if (![object isKindOfClass:UITextField.class]) {
            continue;
        }
        UITextField *field = (UITextField *)object;
        field.delegate = self;
        field.inputAccessoryView = toolbar;
        [field addTarget:self action:@selector(textFieldDidChange:) forControlEvents:UIControlEventEditingChanged];
    }
}

- (void)configureMapIfNeeded {
    if (self.mapConfigured) {
        return;
    }

    self.mapConfigured = YES;
    CLLocationCoordinate2D coordinate = self.hasSelectedCoordinate ? self.selectedCoordinate : CLLocationCoordinate2DMake(37.7749, -122.4194);
    if (!CLLocationCoordinate2DIsValid(coordinate)) {
        coordinate = CLLocationCoordinate2DMake(37.7749, -122.4194);
    }

    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(coordinate, 1200.0, 1200.0);
    [self.mapView setRegion:region animated:NO];
    [self updatePinOnMapAnimated:NO];
}

- (UIView *)ls_separatorView {
    UIView *view = [[UIView alloc] init];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    view.backgroundColor = UIColor.separatorColor;
    [view.heightAnchor constraintEqualToConstant:(1.0 / UIScreen.mainScreen.scale)].active = YES;
    return view;
}

- (UIView *)coordinateFieldWithTitle:(NSString *)title placeholder:(NSString *)placeholder textField:(UITextField **)textField {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = title;
    label.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
    label.textColor = UIColor.secondaryLabelColor;
    [container addSubview:label];

    UITextField *field = [[UITextField alloc] init];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.placeholder = placeholder;
    field.keyboardType = UIKeyboardTypeDecimalPad;
    field.textAlignment = NSTextAlignmentCenter;
    field.font = [UIFont monospacedDigitSystemFontOfSize:14.0 weight:UIFontWeightMedium];
    field.textColor = UIColor.labelColor;
    field.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    field.layer.cornerRadius = 10.0;
    field.layer.cornerCurve = kCACornerCurveContinuous;
    field.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    field.layer.borderColor = UIColor.separatorColor.CGColor;
    field.delegate = self;
    [field addTarget:self action:@selector(textFieldDidChange:) forControlEvents:UIControlEventEditingChanged];
    [container addSubview:field];

    [NSLayoutConstraint activateConstraints:@[
        [label.topAnchor constraintEqualToAnchor:container.topAnchor],
        [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [label.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [field.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:6.0],
        [field.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [field.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [field.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        [field.heightAnchor constraintEqualToConstant:42.0]
    ]];

    if (textField) {
        *textField = field;
    }
    return container;
}

- (UIButton *)primaryButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightBold];
    button.backgroundColor = [UIColor colorWithRed:0.06 green:0.35 blue:0.95 alpha:1.0];
    button.layer.cornerRadius = 18.0;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    button.layer.shadowColor = UIColor.systemBlueColor.CGColor;
    button.layer.shadowOpacity = 0.22;
    button.layer.shadowRadius = 16.0;
    button.layer.shadowOffset = CGSizeMake(0.0, 6.0);
    button.layer.masksToBounds = NO;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [button.heightAnchor constraintEqualToConstant:50.0].active = YES;
    return button;
}

- (UIButton *)secondaryButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightBold];
    button.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    button.layer.cornerRadius = 18.0;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    button.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    button.layer.borderColor = UIColor.separatorColor.CGColor;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [button.heightAnchor constraintEqualToConstant:50.0].active = YES;
    return button;
}

- (UIButton *)destructiveOutlineButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.systemRedColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightBold];
    button.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    button.layer.cornerRadius = 18.0;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    button.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    button.layer.borderColor = UIColor.systemRedColor.CGColor;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [button.heightAnchor constraintEqualToConstant:50.0].active = YES;
    return button;
}

#pragma mark - State/UI sync

- (void)refreshStatusPill {
    PersistenceManager *store = [PersistenceManager shared];
    BOOL enabled = [store isSpoofingEnabled];

    self.statusLabel.text = enabled ? @"✅ تغيير الموقع مفعل" : @"❌ تغيير الموقع غير مفعل";
    UIColor *stateColor = enabled ? UIColor.systemGreenColor : UIColor.systemRedColor;
    self.statusDot.backgroundColor = stateColor;
    self.statusDot.hidden = YES;
    self.navigationIconView.tintColor = stateColor;
    self.statusPill.backgroundColor = [stateColor colorWithAlphaComponent:0.10];
    self.statusPill.layer.borderColor = [stateColor colorWithAlphaComponent:0.26].CGColor;
    self.statusLabel.textColor = stateColor;
    self.subtitleLabel.text = @"";
    self.subtitleLabel.hidden = YES;
    self.pillStopLabel.hidden = YES;
    self.stopButton.hidden = !enabled;
    self.mapView.showsUserLocation = [self ls_shouldShowUserLocationWhileSpoofingDisabled];
    if (self.mapControlsBottomStaticConstraint) {
        [self ls_updateMapControlsBottomConstraint];
    }
    [self updateCoordinateLabel];
}

- (void)syncFieldsFromCoordinate {
    if (self.suppressFieldSync) {
        return;
    }
    if (!CLLocationCoordinate2DIsValid(self.selectedCoordinate)) {
        self.latitudeField.text = @"";
        self.longitudeField.text = @"";
        [self updateCoordinateLabel];
        return;
    }
    self.latitudeField.text = [NSString stringWithFormat:@"%.6f", self.selectedCoordinate.latitude];
    self.longitudeField.text = [NSString stringWithFormat:@"%.6f", self.selectedCoordinate.longitude];
    [self updateCoordinateLabel];
}

- (void)updateCoordinateLabel {
    if (!CLLocationCoordinate2DIsValid(self.selectedCoordinate)) {
        self.coordinateValueLabel.text = @"لم يتم اختيار موقع";
        return;
    }
    self.coordinateValueLabel.text = [NSString stringWithFormat:@"%.6f, %.6f", self.selectedCoordinate.latitude, self.selectedCoordinate.longitude];
}

- (void)movePinToCoordinate:(CLLocationCoordinate2D)coordinate animated:(BOOL)animated {
    if (!CLLocationCoordinate2DIsValid(coordinate)) {
        return;
    }
    self.selectedCoordinate = coordinate;
    self.hasSelectedCoordinate = YES;
    [self syncFieldsFromCoordinate];
    [self updatePinOnMapAnimated:animated];
}

- (void)updatePinOnMapAnimated:(BOOL)animated {
    if (!self.mapConfigured || !CLLocationCoordinate2DIsValid(self.selectedCoordinate)) {
        return;
    }
    if (!self.pinAnnotation) {
        self.pinAnnotation = [[MKPointAnnotation alloc] init];
        self.pinAnnotation.title = @"الموقع المختار";
        [self.mapView addAnnotation:self.pinAnnotation];
    } else if (![self.mapView.annotations containsObject:self.pinAnnotation]) {
        [self.mapView addAnnotation:self.pinAnnotation];
    }
    self.pinAnnotation.coordinate = self.selectedCoordinate;
    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(self.selectedCoordinate, 1000.0, 1000.0);
    [self.mapView setRegion:region animated:animated];
}

- (NSNumber *)ls_parsedCoordinateComponentFromText:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        return nil;
    }
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    NSNumber *number = [formatter numberFromString:trimmed];
    if (number) {
        return number;
    }
    NSScanner *scanner = [NSScanner scannerWithString:trimmed];
    scanner.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    double value = 0.0;
    if ([scanner scanDouble:&value]) {
        return @(value);
    }
    return nil;
}

- (BOOL)applyFieldsToCoordinate {
    if (!CLLocationCoordinate2DIsValid(self.selectedCoordinate)) {
        return NO;
    }
    self.hasSelectedCoordinate = YES;
    [self updatePinOnMapAnimated:YES];
    [self updateCoordinateLabel];
    return YES;
}

- (BOOL)applyAltitudeField {
    return YES;
}

- (void)updateHeadingLabel {
    double heading = self.headingSlider ? (double)self.headingSlider.value : [PersistenceManager shared].heading;
    heading = fmod(heading, 360.0);
    if (heading < 0) {
        heading += 360.0;
    }
    if (self.headingSlider) {
        [PersistenceManager shared].heading = heading;
    }
    self.headingValueLabel.text = [NSString stringWithFormat:@"الاتجاه %.0f°", heading];

    NSArray<NSString *> *directions = @[@"شمال", @"شمال شرق", @"شرق", @"جنوب شرق", @"جنوب", @"جنوب غرب", @"غرب", @"شمال غرب"];
    NSInteger index = (NSInteger)llround(heading / 45.0) % directions.count;
    self.headingDirectionLabel.text = directions[index];
}

#pragma mark - Actions

- (void)showInvalidCoordinateFeedback {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"إحداثيات غير صالحة"
                                                                   message:@"تأكد من إدخال خط عرض بين -90 و 90 وخط طول بين -180 و 180."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"موافق" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)handleApply {
    if (!CLLocationCoordinate2DIsValid(self.selectedCoordinate)) {
        [self showInvalidCoordinateFeedback];
        [self playRouteFailureHaptic];
        return;
    }
    PersistenceManager *store = [PersistenceManager shared];
    if (![store setSpoofCoordinate:self.selectedCoordinate enabled:YES]) {
        [self showInvalidCoordinateFeedback];
        [self playRouteFailureHaptic];
        return;
    }
    [store recordRecentCoordinate:self.selectedCoordinate name:nil];
    [self playApplyHaptic];
    LSSetHooksBypassed(NO);
    [LSOverlayManager setMapPickerVisible:YES];
    [self refreshStatusPill];
    self.mapHintLabel.text = @"   تم تفعيل الأداة   ";
}

- (void)handleCancel {
    [self ls_dismissToolPanelAnimatedDown];
}

- (void)handleStopSpoofing {
    [[LSRouteSimulator shared] stop];
    [[PersistenceManager shared] clearSpoof];
    [self playSimulationStopHaptic];
    [self refreshStatusPill];
    [self updateCoordinateModeVisibility];
}

- (void)handleStatusPillTapped {
    if ([[PersistenceManager shared] isSpoofingEnabled]) {
        [self handleStopSpoofing];
    }
}


- (void)handleHeadingSliderChanged:(UISlider *)sender {
    (void)sender;
    [self updateHeadingLabel];
}

- (void)textFieldDidChange:(UITextField *)textField {
    if (textField == self.latitudeField || textField == self.longitudeField) {
        [self applyFieldsToCoordinate];
    } else if (textField == self.altitudeField) {
        [self applyAltitudeField];    }
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

- (void)handleMapTap:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded) {
        return;
    }
    CLLocationCoordinate2D coordinate = [self.mapView convertPoint:[gesture locationInView:self.mapView] toCoordinateFromView:self.mapView];
    if (self.coordinateMode == LSMapPickerCoordinateModeRoute) {
        [self ls_handleRouteMapTap:coordinate];
    } else {
        [self movePinToCoordinate:coordinate animated:YES];
    }
}

- (void)handleMapLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) {
        return;
    }
    CLLocationCoordinate2D coordinate = [self.mapView convertPoint:[gesture locationInView:self.mapView] toCoordinateFromView:self.mapView];
    if (self.coordinateMode == LSMapPickerCoordinateModeRoute) {
        [self ls_handleRouteMapTap:coordinate];
    } else {
        [self ls_presentStaticMapActionSheetAtCoordinate:coordinate];
    }
}

#pragma mark - Haptics

- (void)playApplyHaptic {
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [generator impactOccurred];
}

- (void)playRouteSuccessHaptic {
    UINotificationFeedbackGenerator *generator = [[UINotificationFeedbackGenerator alloc] init];
    [generator notificationOccurred:UINotificationFeedbackTypeSuccess];
}

- (void)playRouteFailureHaptic {
    UINotificationFeedbackGenerator *generator = [[UINotificationFeedbackGenerator alloc] init];
    [generator notificationOccurred:UINotificationFeedbackTypeError];
}

- (void)playBookmarkSavedHaptic {
    UINotificationFeedbackGenerator *generator = [[UINotificationFeedbackGenerator alloc] init];
    [generator notificationOccurred:UINotificationFeedbackTypeSuccess];
}

- (void)playSimulationStopHaptic {
    UINotificationFeedbackGenerator *generator = [[UINotificationFeedbackGenerator alloc] init];
    [generator notificationOccurred:UINotificationFeedbackTypeWarning];
}

#pragma mark - Keyboard

- (void)ls_keyboardWillShow:(NSNotification *)notification {
    CGRect frame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    UIEdgeInsets inset = self.contentScrollView.contentInset;
    inset.bottom = frame.size.height;
    self.contentScrollView.contentInset = inset;
    self.contentScrollView.scrollIndicatorInsets = inset;
}

- (void)ls_keyboardWillHide:(NSNotification *)notification {
    (void)notification;
    UIEdgeInsets inset = self.contentScrollView.contentInset;
    inset.bottom = 0.0;
    self.contentScrollView.contentInset = inset;
    self.contentScrollView.scrollIndicatorInsets = inset;
}

#pragma mark - Search

- (void)ls_setSuggestionsVisible:(BOOL)visible animated:(BOOL)animated {
    self.searchSuggestionsVisible = visible;
    CGFloat height = visible ? MIN((CGFloat)self.searchCompletions.count, 5.0) * 48.0 : 0.0;
    self.suggestionsHeightConstraint.constant = height;
    void (^changes)(void) = ^{
        self.suggestionsPanel.alpha = visible ? 1.0 : 0.0;
        [self.view layoutIfNeeded];
    };
    self.suggestionsPanel.hidden = NO;
    if (animated) {
        [UIView animateWithDuration:0.2 animations:changes completion:^(BOOL finished) {
            (void)finished;
            self.suggestionsPanel.hidden = !visible;
        }];
    } else {
        changes();
        self.suggestionsPanel.hidden = !visible;
    }
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    self.searchCompleter.queryFragment = searchText ?: @"";
    if (searchText.length == 0) {
        self.searchCompletions = @[];
        [self.suggestionsTableView reloadData];
        [self ls_setSuggestionsVisible:NO animated:YES];
    }
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    NSString *query = searchBar.text ?: @"";
    if (query.length == 0) {
        return;
    }
    MKLocalSearchRequest *request = [[MKLocalSearchRequest alloc] init];
    request.naturalLanguageQuery = query;
    if (self.mapConfigured) {
        request.region = self.mapView.region;
    }
    [self.searchSpinner startAnimating];
    MKLocalSearch *search = [[MKLocalSearch alloc] initWithRequest:request];
    __weak typeof(self) weakSelf = self;
    [search startWithCompletionHandler:^(MKLocalSearchResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf.searchSpinner stopAnimating];
            MKMapItem *item = response.mapItems.firstObject;
            if (!error && item) {
                [strongSelf movePinToCoordinate:item.placemark.coordinate animated:YES];
                [strongSelf ls_setSuggestionsVisible:NO animated:YES];
            }
        });
    }];
}

- (void)completerDidUpdateResults:(MKLocalSearchCompleter *)completer {
    self.searchCompletions = completer.results ?: @[];
    [self.suggestionsTableView reloadData];
    [self ls_setSuggestionsVisible:self.searchCompletions.count > 0 animated:YES];
}

- (void)completer:(MKLocalSearchCompleter *)completer didFailWithError:(NSError *)error {
    (void)completer;
    (void)error;
    self.searchCompletions = @[];
    [self.suggestionsTableView reloadData];
    [self ls_setSuggestionsVisible:NO animated:YES];
}

#pragma mark - Table views

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if ([self ls_isBookmarksTableView:tableView]) {
        return [self ls_bookmarksNumberOfSections];
    }
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if ([self ls_isBookmarksTableView:tableView]) {
        return [self ls_bookmarksNumberOfRowsInSection:section];
    }
    return (NSInteger)self.searchCompletions.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self ls_isBookmarksTableView:tableView]) {
        return [self ls_bookmarksCellForRowAtIndexPath:indexPath];
    }
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"LSSearchSuggestionCell" forIndexPath:indexPath];
    MKLocalSearchCompletion *completion = indexPath.row < (NSInteger)self.searchCompletions.count ? self.searchCompletions[indexPath.row] : nil;
    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.text = completion.title ?: @"";
    content.secondaryText = completion.subtitle ?: @"";
    cell.contentConfiguration = content;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ([self ls_isBookmarksTableView:tableView]) {
        [self ls_bookmarksDidSelectRowAtIndexPath:indexPath];
        return;
    }
    if (indexPath.row >= (NSInteger)self.searchCompletions.count) {
        return;
    }
    MKLocalSearchCompletion *completion = self.searchCompletions[indexPath.row];
    MKLocalSearchRequest *request = [[MKLocalSearchRequest alloc] initWithCompletion:completion];
    [self.searchSpinner startAnimating];
    MKLocalSearch *search = [[MKLocalSearch alloc] initWithRequest:request];
    __weak typeof(self) weakSelf = self;
    [search startWithCompletionHandler:^(MKLocalSearchResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf.searchSpinner stopAnimating];
            MKMapItem *item = response.mapItems.firstObject;
            if (!error && item) {
                [strongSelf movePinToCoordinate:item.placemark.coordinate animated:YES];
                strongSelf.searchBar.text = item.name ?: completion.title;
                [strongSelf ls_setSuggestionsVisible:NO animated:YES];
                [strongSelf.searchBar resignFirstResponder];
            }
        });
    }];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if ([self ls_isBookmarksTableView:tableView]) {
        return [self ls_bookmarksTitleForHeaderInSection:section];
    }
    return nil;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if ([self ls_isBookmarksTableView:tableView]) {
        return [self ls_bookmarksHeaderForSection:section];
    }
    return nil;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self ls_isBookmarksTableView:tableView] ? [self ls_bookmarksCanEditRowAtIndexPath:indexPath] : NO;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self ls_isBookmarksTableView:tableView] && editingStyle == UITableViewCellEditingStyleDelete) {
        [self ls_bookmarksCommitDeleteAtIndexPath:indexPath];
    }
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self ls_isBookmarksTableView:tableView] ? [self ls_bookmarksCanMoveRowAtIndexPath:indexPath] : NO;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    if ([self ls_isBookmarksTableView:tableView]) {
        [self ls_bookmarksMoveFromIndexPath:sourceIndexPath toIndexPath:destinationIndexPath];
    }
}

#pragma mark - Text field delegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    [self textFieldDidChange:textField];
}

#pragma mark - Map view delegate

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id<MKAnnotation>)annotation {
    if ([annotation isKindOfClass:MKUserLocation.class]) {
        return nil;
    }
    MKAnnotationView *routeView = [self ls_viewForRouteAnnotation:annotation];
    if (routeView) {
        return routeView;
    }
    static NSString *identifier = @"LSPinAnnotation";
    MKMarkerAnnotationView *view = (MKMarkerAnnotationView *)[mapView dequeueReusableAnnotationViewWithIdentifier:identifier];
    if (!view) {
        view = [[MKMarkerAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:identifier];
        view.canShowCallout = YES;
        view.draggable = YES;
    } else {
        view.annotation = annotation;
    }
    return view;
}

- (MKOverlayRenderer *)mapView:(MKMapView *)mapView rendererForOverlay:(id<MKOverlay>)overlay {
    (void)mapView;
    return [self ls_rendererForMapOverlay:overlay];
}

- (void)mapView:(MKMapView *)mapView annotationView:(MKAnnotationView *)view didChangeDragState:(MKAnnotationViewDragState)newState fromOldState:(MKAnnotationViewDragState)oldState {
    (void)mapView;
    (void)oldState;
    if (newState != MKAnnotationViewDragStateEnding && newState != MKAnnotationViewDragStateCanceling) {
        return;
    }
    if (view.annotation == self.pinAnnotation) {
        [self movePinToCoordinate:view.annotation.coordinate animated:NO];
        view.dragState = MKAnnotationViewDragStateNone;
        return;
    }
    [self ls_routeAnnotationDragEnded:view];
    view.dragState = MKAnnotationViewDragStateNone;
}

@end
