#import "LSBookmarksSheetViewController.h"
#import "LSFloatingPanel.h"

static NSString * const kLSBookmarkSheetCellID = @"LSBookmarkSheetCell";

@interface LSBookmarkApplyButton : UIButton
@property (nonatomic, assign) NSInteger rowIndex;
@end
@implementation LSBookmarkApplyButton
@end

@interface LSBookmarksSheetViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) NSMutableArray<LSBookmark *> *bookmarks;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *emptyLabel;
@end

@implementation LSBookmarksSheetViewController

- (instancetype)initWithBookmarks:(NSArray<LSBookmark *> *)bookmarks {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _bookmarks = [bookmarks mutableCopy] ?: [NSMutableArray array];
        self.modalPresentationStyle = UIModalPresentationOverFullScreen;
        self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    self.view.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;

    UIView *panel = [self ls_xsgps_installFloatingPanelWithBackgroundColor:UIColor.systemGroupedBackgroundColor];
    [self ls_xsgps_addGrabberToFloatingPanel:panel color:[UIColor colorWithWhite:0.45 alpha:0.35]];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = @"المواقع المحفوظة";
    titleLabel.font = [UIFont systemFontOfSize:25.0 weight:UIFontWeightBlack];
    titleLabel.textColor = UIColor.labelColor;
    [panel addSubview:titleLabel];

    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subtitleLabel.text = @"اضغط تطبيق لاختيار الموقع. اسحب لليسار لتعديل الاسم أو الحذف.";
    subtitleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
    subtitleLabel.textColor = UIColor.secondaryLabelColor;
    subtitleLabel.numberOfLines = 2;
    [panel addSubview:subtitleLabel];

    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [closeButton setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    closeButton.tintColor = UIColor.tertiaryLabelColor;
    [closeButton addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:closeButton];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.rowHeight = 74.0;
    self.tableView.separatorInset = UIEdgeInsetsMake(0.0, 18.0, 0.0, 18.0);
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:kLSBookmarkSheetCellID];
    [panel addSubview:self.tableView];

    self.emptyLabel = [[UILabel alloc] init];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.text = @"لا توجد مواقع محفوظة حاليًا";
    self.emptyLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
    self.emptyLabel.textColor = UIColor.secondaryLabelColor;
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    [panel addSubview:self.emptyLabel];

    UILayoutGuide *safe = panel.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [closeButton.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:18.0],
        [closeButton.topAnchor constraintEqualToAnchor:safe.topAnchor constant:10.0],
        [closeButton.widthAnchor constraintEqualToConstant:34.0],
        [closeButton.heightAnchor constraintEqualToConstant:34.0],

        [titleLabel.topAnchor constraintEqualToAnchor:safe.topAnchor constant:13.0],
        [titleLabel.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-20.0],
        [titleLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:closeButton.trailingAnchor constant:12.0],

        [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:4.0],
        [subtitleLabel.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:20.0],
        [subtitleLabel.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-20.0],

        [self.tableView.topAnchor constraintEqualToAnchor:subtitleLabel.bottomAnchor constant:10.0],
        [self.tableView.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],

        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:panel.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:panel.centerYAnchor constant:34.0],
        [self.emptyLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:panel.leadingAnchor constant:24.0],
        [self.emptyLabel.trailingAnchor constraintLessThanOrEqualToAnchor:panel.trailingAnchor constant:-24.0]
    ]];
    [self refreshEmptyState];
}

- (void)refreshEmptyState {
    self.emptyLabel.hidden = self.bookmarks.count > 0;
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return self.bookmarks.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return @"المحفوظة";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kLSBookmarkSheetCellID forIndexPath:indexPath];
    cell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    LSBookmark *bookmark = self.bookmarks[(NSUInteger)indexPath.row];
    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.text = bookmark.name.length > 0 ? bookmark.name : @"موقع محفوظ";
    content.textProperties.font = [UIFont systemFontOfSize:19.0 weight:UIFontWeightBold];
    content.secondaryText = [NSString stringWithFormat:@"%.5f, %.5f", bookmark.coordinate.latitude, bookmark.coordinate.longitude];
    content.secondaryTextProperties.font = [UIFont monospacedDigitSystemFontOfSize:13.0 weight:UIFontWeightRegular];
    content.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    content.image = [UIImage systemImageNamed:@"bookmark.fill"];
    content.imageProperties.tintColor = [UIColor colorWithRed:0.74 green:0.47 blue:0.10 alpha:1.0];
    content.imageProperties.maximumSize = CGSizeMake(25.0, 25.0);
    cell.contentConfiguration = content;

    LSBookmarkApplyButton *applyButton = [LSBookmarkApplyButton buttonWithType:UIButtonTypeSystem];
    applyButton.rowIndex = indexPath.row;
    applyButton.frame = CGRectMake(0.0, 0.0, 76.0, 38.0);
    [applyButton setTitle:@"تطبيق" forState:UIControlStateNormal];
    [applyButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    applyButton.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightBold];
    applyButton.backgroundColor = UIColor.systemBlueColor;
    applyButton.layer.cornerRadius = 13.0;
    applyButton.layer.cornerCurve = kCACornerCurveContinuous;
    [applyButton addTarget:self action:@selector(applyTapped:) forControlEvents:UIControlEventTouchUpInside];
    cell.accessoryView = applyButton;
    return cell;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    __weak typeof(self) weakSelf = self;
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"حذف" handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^completionHandler)(BOOL)) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || indexPath.row >= (NSInteger)strongSelf.bookmarks.count) {
            completionHandler(NO);
            return;
        }
        [strongSelf.bookmarks removeObjectAtIndex:(NSUInteger)indexPath.row];
        if (strongSelf.onDeleteBookmarkAtIndex) {
            strongSelf.onDeleteBookmarkAtIndex((NSUInteger)indexPath.row);
        }
        [strongSelf.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        [strongSelf refreshEmptyState];
        completionHandler(YES);
    }];
    deleteAction.backgroundColor = UIColor.systemRedColor;

    UIContextualAction *renameAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"تعديل" handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^completionHandler)(BOOL)) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            [strongSelf showRenamePromptAtIndex:indexPath.row];
        }
        completionHandler(strongSelf != nil);
    }];
    renameAction.backgroundColor = UIColor.systemOrangeColor;
    return [UISwipeActionsConfiguration configurationWithActions:@[deleteAction, renameAction]];
}

- (void)showRenamePromptAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.bookmarks.count) return;
    LSBookmark *bookmark = self.bookmarks[(NSUInteger)index];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"تعديل اسم الموقع" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull field) {
        field.text = bookmark.name;
        field.placeholder = @"اسم الموقع";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"حفظ" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction * _Nonnull action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSString *name = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (name.length == 0) return;
        LSBookmark *saved = strongSelf.bookmarks[(NSUInteger)index];
        saved.name = name;
        if (strongSelf.onRenameBookmarkAtIndex) {
            strongSelf.onRenameBookmarkAtIndex((NSUInteger)index, name);
        }
        [strongSelf.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)applyTapped:(LSBookmarkApplyButton *)sender {
    if (sender.rowIndex < 0 || sender.rowIndex >= (NSInteger)self.bookmarks.count) return;
    LSBookmark *bookmark = self.bookmarks[(NSUInteger)sender.rowIndex];
    if (CLLocationCoordinate2DIsValid(bookmark.coordinate) && self.onApplyCoordinate) {
        self.onApplyCoordinate(bookmark.coordinate, bookmark.name);
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row < 0 || indexPath.row >= (NSInteger)self.bookmarks.count) return;
    LSBookmark *bookmark = self.bookmarks[(NSUInteger)indexPath.row];
    if (CLLocationCoordinate2DIsValid(bookmark.coordinate) && self.onPreviewCoordinate) {
        self.onPreviewCoordinate(bookmark.coordinate, bookmark.name);
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

@end
