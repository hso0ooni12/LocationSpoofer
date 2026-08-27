#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, LSScheduleRecurrence) {
    LSScheduleRecurrenceOnce = 0,
    LSScheduleRecurrenceDaily = 1,
    LSScheduleRecurrenceWeekly = 2,
};

@interface LSScheduleManager : NSObject
+ (BOOL)isEnabled;
+ (void)setEnabled:(BOOL)enabled;
+ (NSDate *)startDate;
+ (NSDate *)endDate;
+ (LSScheduleRecurrence)recurrence;
+ (NSArray<NSNumber *> *)weekdays;
+ (void)saveWithStartDate:(NSDate *)startDate
                  endDate:(NSDate *)endDate
               recurrence:(LSScheduleRecurrence)recurrence
                 weekdays:(NSArray<NSNumber *> *)weekdays;
+ (void)clearSchedule;
+ (BOOL)isCurrentTimeWithinSchedule;
+ (NSString *)summaryText;
@end

NS_ASSUME_NONNULL_END
