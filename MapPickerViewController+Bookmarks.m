#import "MapPickerViewController+Private.h"
#import "XsGpS.h"
#import "BookmarksManager.h"
#import "PersistenceManager.h"

static NSString * const kLSBookmarksCell = @"LSBookmarksCell";

typedef NS_ENUM(NSInteger, LSBookmarksSection) {
    LSBookmarksSectionSaved = 0
};

@implementation MapPickerViewController (LSBookmarksUI)

- (void)buildBookmarksPanel {
    self.bookmarksContainer = [[UIView alloc] init];
    self.bookmarksContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.bookmarksContainer.hidden = YES;
    [self.controlPanel addSubview:self.bookmarksContainer];

    self.bookmarksTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.bookmarksTableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.bookmarksTableView.dataSource = (id<UITableViewDataSource>)self;
    self.bookmarksTableView.delegate = (id<UITableViewDelegate>)self;
    self.bookmarksTableView.backgroundColor = UIColor.clearColor;
    self.bookmarksTableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.bookmarksTableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kLSBookmarksCell];
    [self.bookmarksContainer addSubview:self.bookmarksTableView];

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(ls_handleBookmarksLongPress:)];
    [self.bookmarksTableView addGestureRecognizer:longPress];

    [NSLayoutConstraint activateConstraints:@[
        [self.bookmarksTableView.topAnchor constraintEqualToAnchor:self.bookmarksContainer.topAnchor],
        [self.bookmarksTableView.leadingAnchor constraintEqualToAnchor:self.bookmarksContainer.leadingAnchor],
        [self.bookmarksTableView.trailingAnchor constraintEqualToAnchor:self.bookmarksContainer.trailingAnchor],
        [self.bookmarksTableView.bottomAnchor constraintEqualToAnchor:self.bookmarksContainer.bottomAnchor]
    ]];
}

- (void)updatePanelTabVisibility {
    BOOL mapTab = self.panelTab == LSMapPickerPanelTabMap;

    CGFloat duration = 0.2;
    self.mapControlsContainer.hidden = NO;
    self.bookmarksContainer.hidden = NO;

    [UIView animateWithDuration:duration animations:^{
        self.mapControlsContainer.alpha = mapTab ? 1.0 : 0.0;
        self.bookmarksContainer.alpha = mapTab ? 0.0 : 1.0;
        self.coordinateModeSegment.alpha = 0.0;
    } completion:^(BOOL finished) {
        (void)finished;
        self.mapControlsContainer.hidden = !mapTab;
        self.bookmarksContainer.hidden = mapTab;
        self.coordinateModeSegment.hidden = YES;
    }];

    [self.bookmarksQuickButton setTitle:(mapTab ? @" المحفوظات" : @" رجوع للخريطة") forState:UIControlStateNormal];
    if (!mapTab) {
        [self.bookmarksTableView reloadData];
    } else {
        [self updateCoordinateModeVisibility];
    }
}

- (void)handlePanelTabChanged:(UISegmentedControl *)sender {
    self.panelTab = (LSMapPickerPanelTab)sender.selectedSegmentIndex;
    [self updatePanelTabVisibility];
}

- (void)handleCoordinateModeChanged:(UISegmentedControl *)sender {
    (void)sender;
    self.coordinateMode = LSMapPickerCoordinateModeStatic;
    self.coordinateModeSegment.hidden = YES;
    self.coordinateModeSegment.alpha = 0.0;
    [self updateCoordinateModeVisibility];
}

- (void)handleBookmarkSaveTapped {
    [self presentSaveBookmarkAlertWithSuggestedName:nil coordinate:self.selectedCoordinate];
}

- (void)presentSaveBookmarkAlertWithSuggestedName:(NSString *)name coordinate:(CLLocationCoordinate2D)coordinate {
    NSString *suggested = name.length > 0 ? name : @"الموقع";

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"حفظ الموقع"
                                                                    message:nil
                                                             preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = suggested;
        textField.placeholder = @"الاسم";
    }];

    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"موافق" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        NSString *bookmarkName = alert.textFields.firstObject.text;
        if (bookmarkName.length == 0) {
            bookmarkName = @"الموقع";
        }
        [[BookmarksManager shared] addBookmarkWithName:bookmarkName coordinate:coordinate];
        [strongSelf playBookmarkSavedHaptic];
        [strongSelf.bookmarksTableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];

    if (name.length == 0) {
        CLLocation *location = [[CLLocation alloc] initWithLatitude:coordinate.latitude
                                                           longitude:coordinate.longitude];
        CLGeocoder *geocoder = [[CLGeocoder alloc] init];
        [geocoder reverseGeocodeLocation:location completionHandler:^(NSArray<CLPlacemark *> *placemarks, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!error && placemarks.firstObject.name.length > 0) {
                    UITextField *field = alert.textFields.firstObject;
                    if ([field.text isEqualToString:@"الموقع"]) {
                        field.text = placemarks.firstObject.name;
                    }
                }
            });
        }];
    }
}

- (BOOL)ls_isBookmarksTableView:(UITableView *)tableView {
    return tableView == self.bookmarksTableView;
}

- (NSInteger)ls_bookmarksNumberOfSections {
    return 1;
}

- (NSInteger)ls_bookmarksNumberOfRowsInSection:(NSInteger)section {
    (void)section;
    return (NSInteger)[BookmarksManager shared].allBookmarks.count;
}

- (NSString *)ls_bookmarksTitleForHeaderInSection:(NSInteger)section {
    (void)section;
    return @"المواقع المحفوظة";
}

- (UITableViewCell *)ls_bookmarksCellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [self.bookmarksTableView dequeueReusableCellWithIdentifier:kLSBookmarksCell forIndexPath:indexPath];
    NSArray<LSBookmark *> *bookmarks = [BookmarksManager shared].allBookmarks;
    LSBookmark *bookmark = indexPath.row < (NSInteger)bookmarks.count ? bookmarks[(NSUInteger)indexPath.row] : nil;

    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.text = bookmark.name.length > 0 ? bookmark.name : @"موقع محفوظ";
    content.textProperties.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    content.secondaryText = bookmark ? [NSString stringWithFormat:@"%.5f, %.5f", bookmark.coordinate.latitude, bookmark.coordinate.longitude] : @"";
    content.secondaryTextProperties.font = [UIFont monospacedDigitSystemFontOfSize:12.0 weight:UIFontWeightRegular];
    content.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    content.image = [UIImage systemImageNamed:@"bookmark.fill"];
    content.imageProperties.tintColor = UIColor.systemOrangeColor;
    cell.contentConfiguration = content;

    UIButton *applyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    applyButton.frame = CGRectMake(0, 0, 64, 32);
    [applyButton setTitle:@"تطبيق" forState:UIControlStateNormal];
    applyButton.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
    applyButton.tag = indexPath.row;
    [applyButton addTarget:self action:@selector(ls_applyBookmarkFromButton:) forControlEvents:UIControlEventTouchUpInside];
    cell.accessoryView = applyButton;
    cell.accessoryType = UITableViewCellAccessoryNone;
    return cell;
}

- (void)ls_bookmarksDidSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray<LSBookmark *> *bookmarks = [BookmarksManager shared].allBookmarks;
    if (indexPath.row < 0 || indexPath.row >= (NSInteger)bookmarks.count) return;
    [self movePinToCoordinate:bookmarks[(NSUInteger)indexPath.row].coordinate animated:YES];
}

- (BOOL)ls_bookmarksCanEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == LSBookmarksSectionSaved;
}

- (void)ls_bookmarksCommitDeleteAtIndexPath:(NSIndexPath *)indexPath {
    NSArray<LSBookmark *> *bookmarks = [BookmarksManager shared].allBookmarks;
    NSString *name = (indexPath.row < (NSInteger)bookmarks.count) ? bookmarks[indexPath.row].name : @"this bookmark";

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"حذف الموقع المحفوظ"
                                                                   message:[NSString stringWithFormat:@"Delete \"%@\"?", name]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *action) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf.bookmarksTableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"حذف" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        [[BookmarksManager shared] removeBookmarkAtIndex:(NSUInteger)indexPath.row];
        [strongSelf.bookmarksTableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationLeft];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (BOOL)ls_bookmarksCanMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == LSBookmarksSectionSaved && self.bookmarksEditMode;
}

- (void)ls_bookmarksMoveFromIndexPath:(NSIndexPath *)source toIndexPath:(NSIndexPath *)destination {
    [[BookmarksManager shared] moveBookmarkFromIndex:(NSUInteger)source.row toIndex:(NSUInteger)destination.row];
}

- (UIView *)ls_bookmarksHeaderForSection:(NSInteger)section {
    if (section != LSBookmarksSectionSaved) {
        return nil;
    }

    UIView *header = [[UIView alloc] init];
    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"المحفوظات";
    title.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    title.textColor = UIColor.secondaryLabelColor;
    [header addSubview:title];

    UIButton *editButton = [UIButton buttonWithType:UIButtonTypeSystem];
    editButton.translatesAutoresizingMaskIntoConstraints = NO;
    [editButton setTitle:self.bookmarksEditMode ? @"تم" : @"تعديل" forState:UIControlStateNormal];
    editButton.titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    [editButton addTarget:self action:@selector(ls_toggleBookmarksEditMode) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:editButton];

    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20.0],
        [title.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [editButton.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16.0],
        [editButton.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [header.heightAnchor constraintEqualToConstant:28.0]
    ]];
    return header;
}

- (void)ls_handleBookmarksLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) {
        return;
    }

    CGPoint point = [gesture locationInView:self.bookmarksTableView];
    NSIndexPath *indexPath = [self.bookmarksTableView indexPathForRowAtPoint:point];
    if (!indexPath || indexPath.section != LSBookmarksSectionSaved) {
        return;
    }

    NSArray<LSBookmark *> *bookmarks = [BookmarksManager shared].allBookmarks;
    if (indexPath.row >= (NSInteger)bookmarks.count) {
        return;
    }

    LSBookmark *bookmark = bookmarks[indexPath.row];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"إعادة تسمية الموقع"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = bookmark.name;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    __weak typeof(alert) weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"حفظ" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        UIAlertController *strongAlert = weakAlert;
        if (!strongAlert) return;
        NSString *name = strongAlert.textFields.firstObject.text;
        if (name.length == 0) {
            return;
        }
        [[BookmarksManager shared] renameBookmark:name atIndex:(NSUInteger)indexPath.row];
        [strongSelf.bookmarksTableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)ls_toggleBookmarksEditMode {
    self.bookmarksEditMode = !self.bookmarksEditMode;
    [self.bookmarksTableView setEditing:self.bookmarksEditMode animated:YES];
    [self.bookmarksTableView reloadData];
}

- (void)ls_applyBookmarkFromButton:(UIButton *)sender {
    NSArray<LSBookmark *> *bookmarks = [BookmarksManager shared].allBookmarks;
    NSUInteger index = sender.tag;
    if (index >= bookmarks.count) {
        return;
    }

    LSBookmark *bookmark = bookmarks[index];
    PersistenceManager *store = [PersistenceManager shared];
    if (![store setSpoofCoordinate:bookmark.coordinate enabled:YES]) {
        [self playRouteFailureHaptic];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"خطأ"
                                                                       message:@"هذا الموقع المحفوظ يحتوي على إحداثيات غير صالحة."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"موافق" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    [self playApplyHaptic];
    LSSetHooksBypassed(NO);
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)ls_presentStaticMapActionSheetAtCoordinate:(CLLocationCoordinate2D)coordinate {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"ضع الدبوس هنا" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf movePinToCoordinate:coordinate animated:YES];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"حفظ كموقع" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf presentSaveBookmarkAlertWithSuggestedName:nil coordinate:coordinate];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

@end
