#import "MapPickerViewController+Private.h"
#import "PersistenceManager.h"
#import "RouteSimulator.h"

@implementation LSStartAnnotation
@end

@implementation LSDestinationAnnotation
@end

@implementation MapPickerViewController (LSRouteUI)

- (void)buildRouteControls {
    UIView *container = self.routeControlsContainer;

    self.getRouteButton = [self ls_primaryButtonWithTitle:@"جلب المسار" action:@selector(handleGetRouteTapped)];
    self.getRouteButton.hidden = YES;
    [container addSubview:self.getRouteButton];

    self.routeSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.routeSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.routeSpinner.hidesWhenStopped = YES;
    [container addSubview:self.routeSpinner];

    self.transportModeSegment = [[UISegmentedControl alloc] initWithItems:@[@"مشي", @"سيارة", @"مخصص"]];
    self.transportModeSegment.translatesAutoresizingMaskIntoConstraints = NO;
    self.transportModeSegment.selectedSegmentIndex = 1;
    self.transportModeSegment.hidden = YES;
    [self.transportModeSegment addTarget:self action:@selector(handleTransportModeChanged:) forControlEvents:UIControlEventValueChanged];
    [container addSubview:self.transportModeSegment];

    self.customSpeedField = [[UITextField alloc] init];
    self.customSpeedField.translatesAutoresizingMaskIntoConstraints = NO;
    self.customSpeedField.placeholder = @"السرعة المخصصة (كم/س)";
    self.customSpeedField.keyboardType = UIKeyboardTypeDecimalPad;
    self.customSpeedField.borderStyle = UITextBorderStyleRoundedRect;
    self.customSpeedField.textAlignment = NSTextAlignmentCenter;
    self.customSpeedField.text = @"";
    self.customSpeedField.hidden = YES;
    [self.customSpeedField addTarget:self action:@selector(textFieldDidChange:) forControlEvents:UIControlEventEditingChanged];
    [container addSubview:self.customSpeedField];

    self.playRouteButton = [self ls_primaryButtonWithTitle:@"تفعيل الموقع المتحرك" action:@selector(handlePlayRouteTapped)];
    self.playRouteButton.hidden = YES;
    [container addSubview:self.playRouteButton];

    self.pauseRouteButton = [self ls_secondaryButtonWithTitle:@"إيقاف مؤقت" action:@selector(handlePauseRouteTapped)];
    self.pauseRouteButton.hidden = YES;

    self.stopRouteButton = [self ls_secondaryButtonWithTitle:@"إنهاء المسار" action:@selector(handleStopRouteTapped)];
    self.stopRouteButton.hidden = YES;

    self.routeActionRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.pauseRouteButton, self.stopRouteButton]];
    self.routeActionRow.translatesAutoresizingMaskIntoConstraints = NO;
    self.routeActionRow.axis = UILayoutConstraintAxisHorizontal;
    self.routeActionRow.spacing = 12.0;
    self.routeActionRow.distribution = UIStackViewDistributionFillEqually;
    self.routeActionRow.hidden = YES;
    [container addSubview:self.routeActionRow];

    [NSLayoutConstraint activateConstraints:@[
        [self.getRouteButton.heightAnchor constraintEqualToConstant:50.0],
        [self.playRouteButton.heightAnchor constraintEqualToConstant:50.0],
        [self.pauseRouteButton.heightAnchor constraintEqualToConstant:46.0],
        [self.stopRouteButton.heightAnchor constraintEqualToConstant:46.0]
    ]];

    self.customSpeedHeightConstraint = [self.customSpeedField.heightAnchor constraintEqualToConstant:0.0];
    self.customSpeedHeightConstraint.active = YES;
}

- (void)ls_installRouteConstraintsInRoutePanel {
    UIView *content = self.routeControlsContainer;
    [NSLayoutConstraint activateConstraints:@[
        [self.getRouteButton.topAnchor constraintEqualToAnchor:content.topAnchor],
        [self.getRouteButton.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [self.getRouteButton.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],

        [self.routeSpinner.centerXAnchor constraintEqualToAnchor:self.getRouteButton.centerXAnchor],
        [self.routeSpinner.centerYAnchor constraintEqualToAnchor:self.getRouteButton.centerYAnchor],

        [self.transportModeSegment.topAnchor constraintEqualToAnchor:self.getRouteButton.bottomAnchor constant:8.0],
        [self.transportModeSegment.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [self.transportModeSegment.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],

        [self.customSpeedField.topAnchor constraintEqualToAnchor:self.transportModeSegment.bottomAnchor constant:8.0],
        [self.customSpeedField.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [self.customSpeedField.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],

        [self.playRouteButton.topAnchor constraintEqualToAnchor:self.customSpeedField.bottomAnchor constant:8.0],
        [self.playRouteButton.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [self.playRouteButton.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],

        [self.routeActionRow.topAnchor constraintEqualToAnchor:self.playRouteButton.topAnchor],
        [self.routeActionRow.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [self.routeActionRow.trailingAnchor constraintEqualToAnchor:content.trailingAnchor]
    ]];
}

- (void)updateCoordinateModeVisibility {
    // الواجهة الحالية تعتمد على الموقع الثابت فقط؛ إخفاء مسار الحركة نهائياً.
    self.coordinateMode = LSMapPickerCoordinateModeStatic;
    self.coordinateModeSegment.hidden = YES;
    self.coordinateModeSegment.alpha = 0.0;
    BOOL routeMode = NO;
    BOOL staticMode = YES;

    BOOL hasRoute = self.routePolyline != nil;
    BOOL hasEndpoints = self.startAnnotation != nil && self.destinationAnnotation != nil;
    self.getRouteButton.hidden = !routeMode || !hasEndpoints || hasRoute || [[LSRouteSimulator shared] isSimulating];
    self.transportModeSegment.hidden = !routeMode || !hasRoute;
    self.playRouteButton.hidden = !routeMode || !hasRoute;
    self.routeActionRow.hidden = YES;

    if (routeMode) {
        if (self.pinAnnotation) {
            [self.mapView removeAnnotation:self.pinAnnotation];
        }
        if (!self.startAnnotation) {
            self.routePlacementPhase = LSRoutePlacementPhaseStart;
            self.mapHintLabel.text = @"  حدّد نقطة البداية من الخريطة  ";
        }
    } else {
        if (![[LSRouteSimulator shared] isSimulating]) {
            [self ls_clearRouteAnnotationsAndOverlay];
            self.mapHintLabel.text = @"  اضغط على الخريطة أو اسحب الدبوس  ";
        }
        if (self.pinAnnotation && self.mapConfigured) {
            [self.mapView addAnnotation:self.pinAnnotation];
        }
    }

    [UIView animateWithDuration:0.2 animations:^{
        self.staticControlsContainer.alpha = staticMode ? 1.0 : 0.0;
        self.routeControlsContainer.alpha = routeMode ? 1.0 : 0.0;
    } completion:^(BOOL finished) {
        (void)finished;
        self.staticControlsContainer.hidden = !staticMode;
        self.routeControlsContainer.hidden = !routeMode;
    }];
    self.staticControlsContainer.hidden = NO;
    self.routeControlsContainer.hidden = NO;
    [self refreshStatusPill];

    [self ls_updateCustomSpeedVisibility];
    [self ls_updateRoutePlaybackButtons];
    [self ls_updateMapControlsBottomConstraint];
}

- (void)ls_updateMapControlsBottomConstraint {
    if (!self.mapControlsBottomStaticConstraint || !self.mapControlsBottomStaticNoStopConstraint ||
        !self.mapControlsBottomRouteConstraint || !self.mapControlsBottomRouteEarlyConstraint) {
        return;
    }

    self.mapControlsBottomStaticConstraint.active = NO;
    self.mapControlsBottomStaticNoStopConstraint.active = NO;
    self.mapControlsBottomRouteConstraint.active = NO;
    self.mapControlsBottomRouteEarlyConstraint.active = NO;

    BOOL routeMode = self.coordinateMode == LSMapPickerCoordinateModeRoute;
    if (!routeMode) {
        if (self.stopButton.hidden) {
            self.mapControlsBottomStaticNoStopConstraint.active = YES;
        } else {
            self.mapControlsBottomStaticConstraint.active = YES;
        }
        return;
    }

    if (self.routePolyline != nil || [[LSRouteSimulator shared] isSimulating]) {
        self.mapControlsBottomRouteConstraint.active = YES;
    } else {
        self.mapControlsBottomRouteEarlyConstraint.active = YES;
    }
}

- (void)ls_clearRouteAnnotationsAndOverlay {
    if (self.startAnnotation) {
        [self.mapView removeAnnotation:self.startAnnotation];
        self.startAnnotation = nil;
    }
    if (self.destinationAnnotation) {
        [self.mapView removeAnnotation:self.destinationAnnotation];
        self.destinationAnnotation = nil;
    }
    if (self.routePolyline) {
        [self.mapView removeOverlay:self.routePolyline];
        self.routePolyline = nil;
    }
    self.fetchedRoute = nil;
}

- (void)ls_handleRouteMapTap:(CLLocationCoordinate2D)coordinate {
    if (self.routePlacementPhase == LSRoutePlacementPhaseStart || !self.startAnnotation) {
        if (!self.startAnnotation) {
            self.startAnnotation = [[LSStartAnnotation alloc] init];
            self.startAnnotation.title = @"بدء";
            [self.mapView addAnnotation:self.startAnnotation];
        }
        self.startAnnotation.coordinate = coordinate;
        self.routePlacementPhase = LSRoutePlacementPhaseDestination;
        self.mapHintLabel.text = @"  اضغط على الخريطة لتحديد الوجهة  ";
    } else {
        if (!self.destinationAnnotation) {
            self.destinationAnnotation = [[LSDestinationAnnotation alloc] init];
            self.destinationAnnotation.title = @"الوجهة";
            [self.mapView addAnnotation:self.destinationAnnotation];
        }
        self.destinationAnnotation.coordinate = coordinate;
        self.routePlacementPhase = LSRoutePlacementPhaseStart;
        self.mapHintLabel.text = @"  يمكنك تعديل البداية أو النهاية من الخريطة  ";
    }

    self.fetchedRoute = nil;
    if (self.routePolyline) {
        [self.mapView removeOverlay:self.routePolyline];
        self.routePolyline = nil;
    }
    self.getRouteButton.hidden = !(self.startAnnotation && self.destinationAnnotation);
    [self updateCoordinateModeVisibility];
}

- (MKDirectionsTransportType)ls_directionsTransportType {
    return self.transportModeSegment.selectedSegmentIndex == 0 ? MKDirectionsTransportTypeWalking : MKDirectionsTransportTypeAutomobile;
}

- (LSTransportMode)ls_selectedTransportMode {
    switch (self.transportModeSegment.selectedSegmentIndex) {
        case 0: return LSTransportModeWalking;
        case 2: return LSTransportModeCustom;
        case 1:
        default: return LSTransportModeDriving;
    }
}

- (void)handleGetRouteTapped {
    if (!self.startAnnotation || !self.destinationAnnotation) {
        [self playRouteFailureHaptic];
        return;
    }

    self.getRouteButton.hidden = YES;
    [self.routeSpinner startAnimating];
    self.statusLabel.text = @"جاري جلب المسار...";

    [self ls_fetchRouteWithTransportType:[self ls_directionsTransportType] allowRetry:YES];
}

- (void)ls_fetchRouteWithTransportType:(MKDirectionsTransportType)transportType allowRetry:(BOOL)allowRetry {
    MKDirectionsRequest *request = [[MKDirectionsRequest alloc] init];
    request.source = [[MKMapItem alloc] initWithPlacemark:[[MKPlacemark alloc] initWithCoordinate:self.startAnnotation.coordinate]];
    request.destination = [[MKMapItem alloc] initWithPlacemark:[[MKPlacemark alloc] initWithCoordinate:self.destinationAnnotation.coordinate]];
    request.transportType = transportType;
    request.requestsAlternateRoutes = NO;

    MKDirections *directions = [[MKDirections alloc] initWithRequest:request];
    __weak typeof(self) weakSelf = self;
    [directions calculateDirectionsWithCompletionHandler:^(MKDirectionsResponse * _Nullable response, NSError * _Nullable error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error || response.routes.count == 0) {
                if (allowRetry && transportType != MKDirectionsTransportTypeAutomobile) {
                    strongSelf.statusLabel.text = @"تعذر مسار المشي، نجرب القيادة...";
                    [strongSelf ls_fetchRouteWithTransportType:MKDirectionsTransportTypeAutomobile allowRetry:NO];
                    return;
                }

                [strongSelf.routeSpinner stopAnimating];
                [strongSelf ls_buildAndShowDirectFallbackRouteWithMessage:@"تم إنشاء مسار مباشر" ];
                return;
            }

            [strongSelf.routeSpinner stopAnimating];
            strongSelf.fetchedRoute = response.routes.firstObject;
            [strongSelf ls_applyFetchedRoutePolyline:strongSelf.fetchedRoute.polyline statusMessage:@"تم جلب المسار"];
        });
    }];
}

- (void)ls_applyFetchedRoutePolyline:(MKPolyline *)polyline statusMessage:(NSString *)message {
    if (!polyline || polyline.pointCount < 2) {
        [self ls_buildAndShowDirectFallbackRouteWithMessage:@"تم إنشاء مسار مباشر"];
        return;
    }

    [self playRouteSuccessHaptic];
    if (self.routePolyline) {
        [self.mapView removeOverlay:self.routePolyline];
    }
    self.routePolyline = polyline;
    [self.mapView addOverlay:self.routePolyline];
    [self.mapView setVisibleMapRect:self.routePolyline.boundingMapRect edgePadding:UIEdgeInsetsMake(48, 48, 48, 48) animated:YES];
    self.statusLabel.text = message;
    [self updateCoordinateModeVisibility];
}

- (BOOL)ls_buildAndShowDirectFallbackRouteWithMessage:(NSString *)message {
    if (!self.startAnnotation || !self.destinationAnnotation) {
        [self playRouteFailureHaptic];
        self.getRouteButton.hidden = NO;
        self.statusLabel.text = @"اختر بداية ووجهة للمسار";
        return NO;
    }

    CLLocationCoordinate2D start = self.startAnnotation.coordinate;
    CLLocationCoordinate2D end = self.destinationAnnotation.coordinate;
    if (!CLLocationCoordinate2DIsValid(start) || !CLLocationCoordinate2DIsValid(end)) {
        [self playRouteFailureHaptic];
        self.getRouteButton.hidden = NO;
        self.statusLabel.text = @"نقاط المسار غير صالحة";
        return NO;
    }

    const NSUInteger count = 64;
    CLLocationCoordinate2D *coords = malloc(sizeof(CLLocationCoordinate2D) * count);
    if (!coords) {
        [self playRouteFailureHaptic];
        self.getRouteButton.hidden = NO;
        self.statusLabel.text = @"تعذر إنشاء المسار";
        return NO;
    }

    for (NSUInteger index = 0; index < count; index++) {
        double progress = (double)index / (double)(count - 1);
        coords[index] = CLLocationCoordinate2DMake(start.latitude + ((end.latitude - start.latitude) * progress),
                                                   start.longitude + ((end.longitude - start.longitude) * progress));
    }

    MKPolyline *fallbackPolyline = [MKPolyline polylineWithCoordinates:coords count:count];
    free(coords);

    self.fetchedRoute = nil;
    [self ls_applyFetchedRoutePolyline:fallbackPolyline statusMessage:message];
    return YES;
}

- (void)handleTransportModeChanged:(UISegmentedControl *)sender {
    (void)sender;
    [self ls_updateCustomSpeedVisibility];
    LSRouteSimulator *simulator = [LSRouteSimulator shared];
    if (simulator.isSimulating) {
        simulator.transportMode = [self ls_selectedTransportMode];
        if (simulator.transportMode == LSTransportModeCustom) {
            NSNumber *parsed = [self ls_parsedCoordinateComponentFromText:self.customSpeedField.text];
            simulator.customSpeedKmh = parsed ? parsed.doubleValue : 30.0;
        }
    }
}

- (void)ls_updateCustomSpeedVisibility {
    if (!self.transportModeSegment || !self.customSpeedField || !self.customSpeedHeightConstraint) {
        return;
    }

    BOOL custom = self.transportModeSegment.selectedSegmentIndex == 2;
    self.customSpeedField.hidden = !custom;
    self.customSpeedHeightConstraint.constant = custom ? 40.0 : 0.0;
    if (custom && self.customSpeedField.text.length == 0) {
        self.customSpeedField.text = @"30";
    }
}

- (void)handlePlayRouteTapped {
    if (!self.routePolyline || self.routePolyline.pointCount < 2) {
        [self playRouteFailureHaptic];
        self.statusLabel.text = @"المسار غير جاهز";
        return;
    }

    LSRouteSimulator *simulator = [LSRouteSimulator shared];
    simulator.delegate = self;
    simulator.transportMode = [self ls_selectedTransportMode];
    if (simulator.transportMode == LSTransportModeCustom) {
        NSNumber *parsed = [self ls_parsedCoordinateComponentFromText:self.customSpeedField.text];
        simulator.customSpeedKmh = MAX(parsed ? parsed.doubleValue : 30.0, 1.0);
    }

    CLLocationCoordinate2D start = self.startAnnotation.coordinate;
    if (!CLLocationCoordinate2DIsValid(start) ||
        ![[PersistenceManager shared] setSpoofCoordinate:start enabled:YES]) {
        [self playRouteFailureHaptic];
        self.statusLabel.text = @"بداية المسار غير صالحة";
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf refreshStatusPill];
        });
        return;
    }
    [PersistenceManager shared].simulationWasActive = YES;

    [simulator startWithPolyline:self.routePolyline];
    [self ls_updateRoutePlaybackButtons];
    [self refreshStatusPill];
}

- (void)handlePauseRouteTapped {
    LSRouteSimulator *simulator = [LSRouteSimulator shared];
    if (simulator.isPaused) {
        [simulator resume];
        [self.pauseRouteButton setTitle:@"إيقاف مؤقت" forState:UIControlStateNormal];
    } else {
        [simulator pause];
        [self.pauseRouteButton setTitle:@"استئناف" forState:UIControlStateNormal];
        CLLocationCoordinate2D coord = simulator.currentCoordinate;
        if (CLLocationCoordinate2DIsValid(coord)) {
            [[PersistenceManager shared] setSpoofCoordinate:coord enabled:YES];
        }
    }
}

- (void)handleStopRouteTapped {
    LSRouteSimulator *simulator = [LSRouteSimulator shared];
    CLLocationCoordinate2D coord = simulator.currentCoordinate;
    if (CLLocationCoordinate2DIsValid(coord)) {
        [[PersistenceManager shared] setSpoofCoordinate:coord enabled:YES];
    }
    [simulator stop];
    [PersistenceManager shared].simulationWasActive = NO;
    [self playSimulationStopHaptic];
    [self ls_updateRoutePlaybackButtons];
    [self refreshStatusPill];
}

- (void)ls_updateRoutePlaybackButtons {
    LSRouteSimulator *simulator = [LSRouteSimulator shared];
    if (!simulator.isSimulating) {
        [self.playRouteButton setTitle:@"تفعيل الموقع المتحرك" forState:UIControlStateNormal];
        self.playRouteButton.hidden = self.routePolyline == nil || self.coordinateMode != LSMapPickerCoordinateModeRoute;
        self.routeActionRow.hidden = YES;
        return;
    }

    self.playRouteButton.hidden = YES;
    self.routeActionRow.hidden = NO;
    self.pauseRouteButton.hidden = NO;
    self.stopRouteButton.hidden = NO;
    self.getRouteButton.hidden = YES;
    [self.pauseRouteButton setTitle:simulator.isPaused ? @"استئناف" : @"إيقاف مؤقت" forState:UIControlStateNormal];
}

- (void)restoreSimulationUIIfNeeded {
    LSRouteSimulator *simulator = [LSRouteSimulator shared];
    if (simulator.isSimulating) {
        [simulator stop];
    }

    if ([PersistenceManager shared].simulationWasActive) {
        [PersistenceManager shared].simulationWasActive = NO;
    }

    self.coordinateMode = LSMapPickerCoordinateModeStatic;
    self.coordinateModeSegment.hidden = YES;
    self.coordinateModeSegment.alpha = 0.0;
    [self updateCoordinateModeVisibility];
}

- (void)restoreRouteUIFromSimulator {
    LSRouteSimulator *simulator = [LSRouteSimulator shared];
    NSArray<LSRoutePoint *> *points = simulator.routePoints;
    if (points.count < 2) return;

    self.startAnnotation = [[LSStartAnnotation alloc] init];
    self.startAnnotation.title = @"بدء";
    self.startAnnotation.coordinate = simulator.startCoordinate;
    [self.mapView addAnnotation:self.startAnnotation];

    self.destinationAnnotation = [[LSDestinationAnnotation alloc] init];
    self.destinationAnnotation.title = @"الوجهة";
    self.destinationAnnotation.coordinate = simulator.destinationCoordinate;
    [self.mapView addAnnotation:self.destinationAnnotation];

    NSUInteger count = points.count;
    CLLocationCoordinate2D *coords = malloc(sizeof(CLLocationCoordinate2D) * count);
    for (NSUInteger i = 0; i < count; i++) {
        coords[i] = points[i].coordinate;
    }
    self.routePolyline = [MKPolyline polylineWithCoordinates:coords count:count];
    free(coords);
    [self.mapView addOverlay:self.routePolyline];

    [self.mapView setVisibleMapRect:self.routePolyline.boundingMapRect
                        edgePadding:UIEdgeInsetsMake(48.0, 48.0, 48.0, 48.0)
                           animated:NO];

    if (self.pinAnnotation) {
        [self.mapView removeAnnotation:self.pinAnnotation];
    }

    self.coordinateMode = LSMapPickerCoordinateModeRoute;
    self.coordinateModeSegment.selectedSegmentIndex = LSMapPickerCoordinateModeRoute;
    self.mapHintLabel.text = @"";

    self.staticControlsContainer.alpha = 0.0;
    self.staticControlsContainer.hidden = YES;
    self.routeControlsContainer.alpha = 1.0;
    self.routeControlsContainer.hidden = NO;

    self.selectedCoordinate = simulator.currentCoordinate;
    [self syncFieldsFromCoordinate];

    self.getRouteButton.hidden = YES;
    switch (simulator.transportMode) {
        case LSTransportModeWalking: self.transportModeSegment.selectedSegmentIndex = 0; break;
        case LSTransportModeCustom: self.transportModeSegment.selectedSegmentIndex = 2; break;
        case LSTransportModeCycling:
        case LSTransportModeDriving:
        default: self.transportModeSegment.selectedSegmentIndex = 1; break;
    }
    self.transportModeSegment.hidden = NO;
    [self ls_updateCustomSpeedVisibility];
    [self ls_updateRoutePlaybackButtons];
    [self ls_updateMapControlsBottomConstraint];
    [self refreshStatusPill];
}

#pragma mark - LSRouteSimulatorDelegate

- (void)routeSimulator:(LSRouteSimulator *)simulator didUpdateCoordinate:(CLLocationCoordinate2D)coordinate heading:(CLLocationDirection)heading {
    if (!CLLocationCoordinate2DIsValid(coordinate)) {
        return;
    }

    PersistenceManager *store = [PersistenceManager shared];
    [store setSpoofCoordinate:coordinate enabled:YES];
    store.heading = heading;
    store.simulationWasActive = YES;

    double kmh = [LSRouteSimulator speedMetersPerSecondForMode:simulator.transportMode customSpeedKmh:simulator.customSpeedKmh] * 3.6;
    self.statusLabel.text = @"تغيير الموقع مفعل ✅";
    self.statusDot.backgroundColor = UIColor.systemGreenColor;
    self.subtitleLabel.text = [NSString stringWithFormat:@"سرعة الحركة %.1f كم/س", kmh];
    self.subtitleLabel.hidden = NO;

    self.selectedCoordinate = coordinate;
    self.startAnnotation.coordinate = coordinate;
    self.pinAnnotation.coordinate = coordinate;
    self.suppressFieldSync = YES;
    self.latitudeField.text = [NSString stringWithFormat:@"%.6f", coordinate.latitude];
    self.longitudeField.text = [NSString stringWithFormat:@"%.6f", coordinate.longitude];
    self.suppressFieldSync = NO;
    [self updateCoordinateLabel];
}

- (void)routeSimulatorDidFinish:(LSRouteSimulator *)simulator {
    (void)simulator;
    [PersistenceManager shared].simulationWasActive = NO;

    CLLocationCoordinate2D finalCoord = kCLLocationCoordinate2DInvalid;
    if (self.routePolyline && self.routePolyline.pointCount > 0) {
        [self.routePolyline getCoordinates:&finalCoord
                                     range:NSMakeRange(self.routePolyline.pointCount - 1, 1)];
    }
    if (CLLocationCoordinate2DIsValid(finalCoord)) {
        PersistenceManager *store = [PersistenceManager shared];
        if ([store setSpoofCoordinate:finalCoord enabled:YES]) {
            self.selectedCoordinate = finalCoord;
            [self syncFieldsFromCoordinate];
        } else {
            [self playRouteFailureHaptic];
            self.statusLabel.text = @"اكتمل المسار (تم رفض التزييف)";
        }
    }

    self.statusLabel.text = @"اكتمل المسار";
    [self ls_updateRoutePlaybackButtons];
    [self refreshStatusPill];
}

- (MKOverlayRenderer *)ls_rendererForMapOverlay:(id<MKOverlay>)overlay {
    if (overlay == self.routePolyline) {
        MKPolylineRenderer *renderer = [[MKPolylineRenderer alloc] initWithPolyline:(MKPolyline *)overlay];
        renderer.strokeColor = UIColor.systemBlueColor;
        renderer.lineWidth = 4.0;
        return renderer;
    }
    return nil;
}

- (nullable MKAnnotationView *)ls_viewForRouteAnnotation:(id<MKAnnotation>)annotation {
    if ([annotation isKindOfClass:[LSStartAnnotation class]]) {
        static NSString * const identifier = @"LSStartPin";
        MKMarkerAnnotationView *view = (MKMarkerAnnotationView *)[self.mapView dequeueReusableAnnotationViewWithIdentifier:identifier];
        if (!view) {
            view = [[MKMarkerAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:identifier];
            view.canShowCallout = YES;
            view.draggable = YES;
        } else {
            view.annotation = annotation;
        }
        view.markerTintColor = UIColor.systemGreenColor;
        return view;
    }

    if ([annotation isKindOfClass:[LSDestinationAnnotation class]]) {
        static NSString * const identifier = @"LSDestinationPin";
        MKMarkerAnnotationView *view = (MKMarkerAnnotationView *)[self.mapView dequeueReusableAnnotationViewWithIdentifier:identifier];
        if (!view) {
            view = [[MKMarkerAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:identifier];
            view.canShowCallout = YES;
            view.draggable = YES;
        } else {
            view.annotation = annotation;
        }
        view.markerTintColor = UIColor.systemRedColor;
        return view;
    }

    return nil;
}

- (void)ls_routeAnnotationDragEnded:(MKAnnotationView *)view {
    if (view.annotation == self.startAnnotation || view.annotation == self.destinationAnnotation) {
        self.fetchedRoute = nil;
        if (self.routePolyline) {
            [self.mapView removeOverlay:self.routePolyline];
            self.routePolyline = nil;
        }
        [self updateCoordinateModeVisibility];
    }
}

- (UIButton *)ls_primaryButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    button.backgroundColor = UIColor.systemBlueColor;
    button.layer.cornerRadius = 12.0;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (UIButton *)ls_secondaryButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    button.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    button.layer.cornerRadius = 12.0;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

@end
