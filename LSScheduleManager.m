#import "LSScheduleManager.h"

static NSString * const kLSSuiteName = @"com.xsgps.dylib";
static NSString * const kLSScheduleEnabledKey = @"LSScheduledLocationEnabled";
static NSString * const kLSStartDateKey = @"LSLocationScheduleStartDate";
static NSString * const kLSEndDateKey = @"LSLocationScheduleEndDate";
static NSString * const kLSRecurrenceKey = @"LSLocationScheduleRecurrence";
static NSString * const kLSWeekdaysKey = @"LSLocationScheduleWeekdays";

@implementation LSScheduleManager

+ (NSUserDefaults *)defaults {
    return [[NSUserDefaults alloc] initWithSuiteName:kLSSuiteName] ?: NSUserDefaults.standardUserDefaults;
}

+ (BOOL)isEnabled { return [[self defaults] boolForKey:kLSScheduleEnabledKey]; }
+ (void)setEnabled:(BOOL)enabled {
    [[self defaults] setBool:enabled forKey:kLSScheduleEnabledKey];
    [[self defaults] synchronize];
}

+ (NSDate *)fallbackDateWithHour:(NSInteger)hour minute:(NSInteger)minute {
    NSDateComponents *components = [[NSCalendar currentCalendar] components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay fromDate:NSDate.date];
    components.hour = hour;
    components.minute = minute;
    components.second = 0;
    return [[NSCalendar currentCalendar] dateFromComponents:components] ?: NSDate.date;
}

+ (NSDate *)startDate {
    NSDate *date = [[self defaults] objectForKey:kLSStartDateKey];
    return [date isKindOfClass:NSDate.class] ? date : [self fallbackDateWithHour:8 minute:0];
}

+ (NSDate *)endDate {
    NSDate *date = [[self defaults] objectForKey:kLSEndDateKey];
    return [date isKindOfClass:NSDate.class] ? date : [self fallbackDateWithHour:17 minute:0];
}

+ (LSScheduleRecurrence)recurrence {
    NSInteger value = [[self defaults] integerForKey:kLSRecurrenceKey];
    return value >= LSScheduleRecurrenceOnce && value <= LSScheduleRecurrenceWeekly ? (LSScheduleRecurrence)value : LSScheduleRecurrenceOnce;
}

+ (NSArray<NSNumber *> *)weekdays {
    NSArray *stored = [[self defaults] arrayForKey:kLSWeekdaysKey];
    if (![stored isKindOfClass:NSArray.class] || stored.count == 0) {
        return @[@2, @3, @4, @5, @6];
    }
    NSMutableArray<NSNumber *> *clean = [NSMutableArray array];
    for (id value in stored) {
        if ([value isKindOfClass:NSNumber.class] && [value integerValue] >= 1 && [value integerValue] <= 7) {
            [clean addObject:value];
        }
    }
    return clean.count > 0 ? clean : @[@2, @3, @4, @5, @6];
}

+ (void)saveWithStartDate:(NSDate *)startDate
                  endDate:(NSDate *)endDate
               recurrence:(LSScheduleRecurrence)recurrence
                 weekdays:(NSArray<NSNumber *> *)weekdays {
    NSUserDefaults *defaults = [self defaults];
    [defaults setObject:startDate ?: [self fallbackDateWithHour:8 minute:0] forKey:kLSStartDateKey];
    [defaults setObject:endDate ?: [self fallbackDateWithHour:17 minute:0] forKey:kLSEndDateKey];
    [defaults setInteger:recurrence forKey:kLSRecurrenceKey];
    [defaults setObject:weekdays ?: @[] forKey:kLSWeekdaysKey];
    [defaults setBool:YES forKey:kLSScheduleEnabledKey];
    [defaults synchronize];
}

+ (void)clearSchedule {
    NSUserDefaults *defaults = [self defaults];
    [defaults setBool:NO forKey:kLSScheduleEnabledKey];
    [defaults removeObjectForKey:kLSStartDateKey];
    [defaults removeObjectForKey:kLSEndDateKey];
    [defaults removeObjectForKey:kLSRecurrenceKey];
    [defaults removeObjectForKey:kLSWeekdaysKey];
    [defaults synchronize];
}

+ (BOOL)isNowBetweenStart:(NSDate *)start end:(NSDate *)end date:(NSDate *)now {
    NSCalendar *calendar = NSCalendar.currentCalendar;
    NSDateComponents *nowTime = [calendar components:NSCalendarUnitHour|NSCalendarUnitMinute|NSCalendarUnitSecond fromDate:now];
    NSDateComponents *startTime = [calendar components:NSCalendarUnitHour|NSCalendarUnitMinute|NSCalendarUnitSecond fromDate:start];
    NSDateComponents *endTime = [calendar components:NSCalendarUnitHour|NSCalendarUnitMinute|NSCalendarUnitSecond fromDate:end];

    NSDateComponents *day = [calendar components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay fromDate:now];
    NSDateComponents *startToday = day.copy;
    startToday.hour = startTime.hour; startToday.minute = startTime.minute; startToday.second = 0;
    NSDateComponents *endToday = day.copy;
    endToday.hour = endTime.hour; endToday.minute = endTime.minute; endToday.second = 0;
    NSDate *startAt = [calendar dateFromComponents:startToday];
    NSDate *endAt = [calendar dateFromComponents:endToday];
    if (!startAt || !endAt) return NO;

    if ([endAt compare:startAt] != NSOrderedDescending) {
        if ([now compare:endAt] == NSOrderedAscending) {
            startAt = [calendar dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:startAt options:0];
        } else {
            endAt = [calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:endAt options:0];
        }
    }
    (void)nowTime;
    return [now compare:startAt] != NSOrderedAscending && [now compare:endAt] != NSOrderedDescending;
}

+ (BOOL)isCurrentTimeWithinSchedule {
    if (![self isEnabled]) return YES;
    NSDate *now = NSDate.date;
    NSDate *start = [self startDate];
    NSDate *end = [self endDate];
    LSScheduleRecurrence recurrence = [self recurrence];

    if (recurrence == LSScheduleRecurrenceOnce) {
        return [now compare:start] != NSOrderedAscending && [now compare:end] != NSOrderedDescending;
    }

    NSCalendar *calendar = NSCalendar.currentCalendar;
    NSInteger weekday = [calendar component:NSCalendarUnitWeekday fromDate:now];
    if (recurrence == LSScheduleRecurrenceWeekly && ![[self weekdays] containsObject:@(weekday)]) {
        // For schedules spanning midnight, let the previous selected day continue until the end time.
        NSDate *yesterday = [calendar dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:now options:0];
        NSInteger yesterdayWeekday = [calendar component:NSCalendarUnitWeekday fromDate:yesterday];
        NSDateComponents *startTime = [calendar components:NSCalendarUnitHour|NSCalendarUnitMinute fromDate:start];
        NSDateComponents *endTime = [calendar components:NSCalendarUnitHour|NSCalendarUnitMinute fromDate:end];
        BOOL spansMidnight = (endTime.hour * 60 + endTime.minute) <= (startTime.hour * 60 + startTime.minute);
        if (!(spansMidnight && [[self weekdays] containsObject:@(yesterdayWeekday)])) return NO;
    }
    return [self isNowBetweenStart:start end:end date:now];
}

+ (NSString *)summaryText {
    if (![self isEnabled]) return @"غير مفعل";
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"ar_SA"];
    formatter.dateFormat = @"HH:mm";
    NSString *start = [formatter stringFromDate:[self startDate]];
    NSString *end = [formatter stringFromDate:[self endDate]];
    NSString *mode = @"مرة واحدة";
    if ([self recurrence] == LSScheduleRecurrenceDaily) mode = @"يوميًا";
    if ([self recurrence] == LSScheduleRecurrenceWeekly) mode = @"أيام محددة";
    return [NSString stringWithFormat:@"%@ – %@ · %@", start, end, mode];
}

@end
