#import "LSScheduleEditorViewController.h"
#import "LSScheduleManager.h"
#import "PersistenceManager.h"
#import "LSFloatingPanel.h"

@interface LSScheduleEditorViewController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIDatePicker *startPicker;
@property (nonatomic, strong) UIDatePicker *endPicker;
@property (nonatomic, strong) UISegmentedControl *recurrenceControl;
@property (nonatomic, strong) UIStackView *daysStack;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, UIButton *> *dayButtons;
@property (nonatomic, strong) UILabel *coordinateLabel;
@end

@implementation LSScheduleEditorViewController

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.modalPresentationStyle = UIModalPresentationOverFullScreen;
        self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    }
    return self;
}


- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    self.view.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    self.dayButtons = [NSMutableDictionary dictionary];
    [self buildInterface];
}

- (UILabel *)label:(NSString *)text font:(UIFont *)font color:(UIColor *)color {
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = text;
    label.font = font;
    label.textColor = color;
    label.numberOfLines = 0;
    return label;
}

- (UIView *)card {
    UIView *view = [[UIView alloc] init];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    view.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    view.layer.cornerRadius = 22.0;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    view.layer.borderColor = UIColor.separatorColor.CGColor;
    return view;
}

- (UIButton *)textButton:(NSString *)title tint:(UIColor *)tint action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:tint forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightBold];
    button.backgroundColor = [tint colorWithAlphaComponent:0.12];
    button.layer.cornerRadius = 15.0;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [button.heightAnchor constraintEqualToConstant:46.0].active = YES;
    return button;
}

- (void)buildInterface {
    UIView *panel = [self ls_xsgps_installFloatingPanelWithBackgroundColor:UIColor.systemGroupedBackgroundColor];
    [self ls_xsgps_addGrabberToFloatingPanel:panel color:[UIColor colorWithWhite:0.45 alpha:0.35]];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [close setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    close.tintColor = UIColor.tertiaryLabelColor;
    [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:close];

    UILabel *title = [self label:@"جدولة الموقع" font:[UIFont systemFontOfSize:25.0 weight:UIFontWeightBlack] color:UIColor.labelColor];
    [panel addSubview:title];
    UILabel *subtitle = [self label:@"حدد وقت التشغيل والإيقاف، ثم اختر التكرار والأيام." font:[UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium] color:UIColor.secondaryLabelColor];
    [panel addSubview:subtitle];

    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.showsVerticalScrollIndicator = NO;
    [panel addSubview:self.scrollView];

    self.contentView = [[UIView alloc] init];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.contentView];

    UIView *locationCard = [self card];
    [self.contentView addSubview:locationCard];
    UILabel *locTitle = [self label:@"الموقع للجدولة" font:[UIFont systemFontOfSize:16.0 weight:UIFontWeightBold] color:UIColor.labelColor];
    [locationCard addSubview:locTitle];
    NSString *coord = self.hasSelectedCoordinate ? [NSString stringWithFormat:@"%.5f, %.5f", self.selectedCoordinate.latitude, self.selectedCoordinate.longitude] : @"اختر موقعًا من الخريطة أولاً";
    self.coordinateLabel = [self label:coord font:[UIFont monospacedDigitSystemFontOfSize:13.0 weight:UIFontWeightMedium] color:self.hasSelectedCoordinate ? UIColor.secondaryLabelColor : UIColor.systemRedColor];
    [locationCard addSubview:self.coordinateLabel];

    UIView *timeCard = [self card];
    [self.contentView addSubview:timeCard];
    UILabel *timeTitle = [self label:@"وقت التشغيل والإيقاف" font:[UIFont systemFontOfSize:16.0 weight:UIFontWeightBold] color:UIColor.labelColor];
    [timeCard addSubview:timeTitle];
    self.startPicker = [[UIDatePicker alloc] init];
    self.startPicker.translatesAutoresizingMaskIntoConstraints = NO;
    self.startPicker.datePickerMode = UIDatePickerModeTime;
    self.startPicker.preferredDatePickerStyle = UIDatePickerStyleCompact;
    self.startPicker.date = [LSScheduleManager startDate];
    [timeCard addSubview:self.startPicker];
    self.endPicker = [[UIDatePicker alloc] init];
    self.endPicker.translatesAutoresizingMaskIntoConstraints = NO;
    self.endPicker.datePickerMode = UIDatePickerModeTime;
    self.endPicker.preferredDatePickerStyle = UIDatePickerStyleCompact;
    self.endPicker.date = [LSScheduleManager endDate];
    [timeCard addSubview:self.endPicker];
    UILabel *startText = [self label:@"وقت التشغيل" font:[UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold] color:UIColor.secondaryLabelColor];
    UILabel *endText = [self label:@"وقت الإيقاف" font:[UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold] color:UIColor.secondaryLabelColor];
    [timeCard addSubview:startText]; [timeCard addSubview:endText];

    UIView *modeCard = [self card];
    [self.contentView addSubview:modeCard];
    UILabel *modeTitle = [self label:@"التكرار" font:[UIFont systemFontOfSize:16.0 weight:UIFontWeightBold] color:UIColor.labelColor];
    [modeCard addSubview:modeTitle];
    self.recurrenceControl = [[UISegmentedControl alloc] initWithItems:@[@"مرة واحدة", @"يوميًا", @"أيام محددة"]];
    self.recurrenceControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.recurrenceControl.selectedSegmentIndex = [LSScheduleManager recurrence];
    [self.recurrenceControl addTarget:self action:@selector(recurrenceChanged:) forControlEvents:UIControlEventValueChanged];
    [modeCard addSubview:self.recurrenceControl];

    self.daysStack = [[UIStackView alloc] init];
    self.daysStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.daysStack.axis = UILayoutConstraintAxisVertical;
    self.daysStack.spacing = 7.0;
    [modeCard addSubview:self.daysStack];
    NSArray<NSString *> *names = @[@"الأحد", @"الاثنين", @"الثلاثاء", @"الأربعاء", @"الخميس", @"الجمعة", @"السبت"];
    NSSet<NSNumber *> *selected = [NSSet setWithArray:[LSScheduleManager weekdays]];
    for (NSInteger i = 0; i < names.count; i++) {
        NSNumber *day = @(i + 1);
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        button.tag = day.integerValue;
        [button setTitle:names[i] forState:UIControlStateNormal];
        button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
        button.titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
        [button addTarget:self action:@selector(dayTapped:) forControlEvents:UIControlEventTouchUpInside];
        [button.heightAnchor constraintEqualToConstant:38.0].active = YES;
        [self.daysStack addArrangedSubview:button];
        self.dayButtons[day] = button;
        [self updateDayButton:button selected:[selected containsObject:day]];
    }

    UIButton *save = [self textButton:@"حفظ الجدولة" tint:UIColor.systemBlueColor action:@selector(saveTapped)];
    [self.contentView addSubview:save];
    UIButton *clear = [self textButton:@"إلغاء الجدولة" tint:UIColor.systemRedColor action:@selector(clearTapped)];
    [self.contentView addSubview:clear];

    UILayoutGuide *safe = panel.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [close.topAnchor constraintEqualToAnchor:safe.topAnchor constant:10.0],
        [close.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:20.0],
        [close.widthAnchor constraintEqualToConstant:34.0], [close.heightAnchor constraintEqualToConstant:34.0],
        [title.topAnchor constraintEqualToAnchor:safe.topAnchor constant:14.0],
        [title.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-22.0],
        [title.leadingAnchor constraintGreaterThanOrEqualToAnchor:close.trailingAnchor constant:12.0],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4.0],
        [subtitle.trailingAnchor constraintEqualToAnchor:title.trailingAnchor], [subtitle.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:22.0],
        [self.scrollView.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:14.0],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor], [self.scrollView.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor], [self.scrollView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [self.contentView.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor], [self.contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor], [self.contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor], [self.contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor], [self.contentView.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor],
        [locationCard.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8.0], [locationCard.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20.0], [locationCard.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20.0],
        [locTitle.topAnchor constraintEqualToAnchor:locationCard.topAnchor constant:14.0], [locTitle.trailingAnchor constraintEqualToAnchor:locationCard.trailingAnchor constant:-16.0], [locTitle.leadingAnchor constraintEqualToAnchor:locationCard.leadingAnchor constant:16.0],
        [self.coordinateLabel.topAnchor constraintEqualToAnchor:locTitle.bottomAnchor constant:6.0], [self.coordinateLabel.leadingAnchor constraintEqualToAnchor:locationCard.leadingAnchor constant:16.0], [self.coordinateLabel.trailingAnchor constraintEqualToAnchor:locationCard.trailingAnchor constant:-16.0], [self.coordinateLabel.bottomAnchor constraintEqualToAnchor:locationCard.bottomAnchor constant:-14.0],
        [timeCard.topAnchor constraintEqualToAnchor:locationCard.bottomAnchor constant:12.0], [timeCard.leadingAnchor constraintEqualToAnchor:locationCard.leadingAnchor], [timeCard.trailingAnchor constraintEqualToAnchor:locationCard.trailingAnchor],
        [timeTitle.topAnchor constraintEqualToAnchor:timeCard.topAnchor constant:14.0], [timeTitle.trailingAnchor constraintEqualToAnchor:timeCard.trailingAnchor constant:-16.0],
        [startText.topAnchor constraintEqualToAnchor:timeTitle.bottomAnchor constant:12.0], [startText.trailingAnchor constraintEqualToAnchor:timeCard.trailingAnchor constant:-16.0],
        [self.startPicker.centerYAnchor constraintEqualToAnchor:startText.centerYAnchor], [self.startPicker.leadingAnchor constraintEqualToAnchor:timeCard.leadingAnchor constant:16.0],
        [endText.topAnchor constraintEqualToAnchor:startText.bottomAnchor constant:14.0], [endText.trailingAnchor constraintEqualToAnchor:timeCard.trailingAnchor constant:-16.0],
        [self.endPicker.centerYAnchor constraintEqualToAnchor:endText.centerYAnchor], [self.endPicker.leadingAnchor constraintEqualToAnchor:timeCard.leadingAnchor constant:16.0], [endText.bottomAnchor constraintEqualToAnchor:timeCard.bottomAnchor constant:-16.0],
        [modeCard.topAnchor constraintEqualToAnchor:timeCard.bottomAnchor constant:12.0], [modeCard.leadingAnchor constraintEqualToAnchor:locationCard.leadingAnchor], [modeCard.trailingAnchor constraintEqualToAnchor:locationCard.trailingAnchor],
        [modeTitle.topAnchor constraintEqualToAnchor:modeCard.topAnchor constant:14.0], [modeTitle.trailingAnchor constraintEqualToAnchor:modeCard.trailingAnchor constant:-16.0],
        [self.recurrenceControl.topAnchor constraintEqualToAnchor:modeTitle.bottomAnchor constant:12.0], [self.recurrenceControl.leadingAnchor constraintEqualToAnchor:modeCard.leadingAnchor constant:16.0], [self.recurrenceControl.trailingAnchor constraintEqualToAnchor:modeCard.trailingAnchor constant:-16.0],
        [self.daysStack.topAnchor constraintEqualToAnchor:self.recurrenceControl.bottomAnchor constant:10.0], [self.daysStack.leadingAnchor constraintEqualToAnchor:modeCard.leadingAnchor constant:16.0], [self.daysStack.trailingAnchor constraintEqualToAnchor:modeCard.trailingAnchor constant:-16.0], [self.daysStack.bottomAnchor constraintEqualToAnchor:modeCard.bottomAnchor constant:-14.0],
        [save.topAnchor constraintEqualToAnchor:modeCard.bottomAnchor constant:16.0], [save.leadingAnchor constraintEqualToAnchor:locationCard.leadingAnchor], [save.trailingAnchor constraintEqualToAnchor:locationCard.trailingAnchor],
        [clear.topAnchor constraintEqualToAnchor:save.bottomAnchor constant:10.0], [clear.leadingAnchor constraintEqualToAnchor:locationCard.leadingAnchor], [clear.trailingAnchor constraintEqualToAnchor:locationCard.trailingAnchor], [clear.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-26.0]
    ]];
    [self updateDaysVisibility];
}

- (void)updateDayButton:(UIButton *)button selected:(BOOL)selected {
    NSString *name = [button titleForState:UIControlStateNormal] ?: @"";
    [button setTitle:[NSString stringWithFormat:@"%@ %@", selected ? @"✓" : @"○", name] forState:UIControlStateNormal];
    [button setTitleColor:selected ? UIColor.systemBlueColor : UIColor.secondaryLabelColor forState:UIControlStateNormal];
}

- (void)recurrenceChanged:(UISegmentedControl *)sender { (void)sender; [self updateDaysVisibility]; }
- (void)updateDaysVisibility { self.daysStack.hidden = self.recurrenceControl.selectedSegmentIndex != LSScheduleRecurrenceWeekly; }

- (void)dayTapped:(UIButton *)sender {
    NSString *current = [sender titleForState:UIControlStateNormal] ?: @"";
    BOOL selected = [current hasPrefix:@"✓"];
    NSString *name = current.length > 2 ? [current substringFromIndex:2] : current;
    [sender setTitle:name forState:UIControlStateNormal];
    [self updateDayButton:sender selected:!selected];
}

- (NSArray<NSNumber *> *)selectedWeekdays {
    NSMutableArray<NSNumber *> *days = [NSMutableArray array];
    [self.dayButtons enumerateKeysAndObjectsUsingBlock:^(NSNumber *key, UIButton *button, BOOL *stop) {
        (void)stop;
        if ([[button titleForState:UIControlStateNormal] hasPrefix:@"✓"]) [days addObject:key];
    }];
    return [days sortedArrayUsingSelector:@selector(compare:)];
}

- (void)saveTapped {
    if (!self.hasSelectedCoordinate || !CLLocationCoordinate2DIsValid(self.selectedCoordinate)) {
        [self showAlert:@"حدد موقعًا أولاً" message:@"اختر موقعًا من الخريطة ثم افتح إعداد الجدولة."];
        return;
    }
    if (self.recurrenceControl.selectedSegmentIndex == LSScheduleRecurrenceWeekly && self.selectedWeekdays.count == 0) {
        [self showAlert:@"حدد يومًا" message:@"اختر يومًا واحدًا على الأقل للجدولة الأسبوعية."];
        return;
    }
    NSDate *start = self.startPicker.date;
    NSDate *end = self.endPicker.date;
    if (self.recurrenceControl.selectedSegmentIndex == LSScheduleRecurrenceOnce && [end compare:start] != NSOrderedDescending) {
        end = [[NSCalendar currentCalendar] dateByAddingUnit:NSCalendarUnitDay value:1 toDate:end options:0] ?: end;
    }
    [[PersistenceManager shared] setSpoofCoordinate:self.selectedCoordinate enabled:NO];
    [LSScheduleManager saveWithStartDate:start endDate:end recurrence:(LSScheduleRecurrence)self.recurrenceControl.selectedSegmentIndex weekdays:self.selectedWeekdays];
    if (self.onSaved) self.onSaved();
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)clearTapped { [LSScheduleManager clearSchedule]; if (self.onSaved) self.onSaved(); [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)closeTapped { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)showAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"حسنًا" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
