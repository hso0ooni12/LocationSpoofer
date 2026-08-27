#import "LSBluetoothLogManager.h"

static NSString * const kLSSuiteName = @"com.xsgps.dylib";
static NSString * const kLSBluetoothLogKey = @"LSBluetoothLogEntries";

@implementation LSBluetoothLogManager

+ (NSUserDefaults *)defaults { return [[NSUserDefaults alloc] initWithSuiteName:kLSSuiteName] ?: NSUserDefaults.standardUserDefaults; }
+ (NSArray<NSDictionary<NSString *,id> *> *)entries {
    NSArray *entries = [[self defaults] arrayForKey:kLSBluetoothLogKey];
    return [entries isKindOfClass:NSArray.class] ? entries : @[];
}
+ (void)recordName:(NSString *)name identifier:(NSString *)identifier rssi:(NSNumber *)rssi {
    if (!identifier.length) return;
    NSMutableArray<NSDictionary *> *entries = [[self entries] mutableCopy];
    NSMutableDictionary *newEntry = [@{
        @"name": name.length ? name : @"جهاز بدون اسم",
        @"identifier": identifier,
        @"rssi": rssi ?: @(0),
        @"timestamp": @([[NSDate date] timeIntervalSince1970])
    } mutableCopy];
    NSUInteger existingIndex = NSNotFound;
    for (NSUInteger i = 0; i < entries.count; i++) {
        if ([entries[i][@"identifier"] isEqualToString:identifier]) { existingIndex = i; break; }
    }
    if (existingIndex != NSNotFound) [entries removeObjectAtIndex:existingIndex];
    [entries insertObject:newEntry atIndex:0];
    if (entries.count > 100) [entries removeObjectsInRange:NSMakeRange(100, entries.count - 100)];
    [[self defaults] setObject:entries forKey:kLSBluetoothLogKey];
    [[self defaults] synchronize];
}
+ (void)clear { [[self defaults] removeObjectForKey:kLSBluetoothLogKey]; [[self defaults] synchronize]; }
+ (NSString *)exportText {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"ar_SA"];
    formatter.dateStyle = NSDateFormatterShortStyle;
    formatter.timeStyle = NSDateFormatterMediumStyle;
    NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithObject:@"XsGpS – Bluetooth Log"];
    for (NSDictionary *entry in [self entries]) {
        NSTimeInterval interval = [entry[@"timestamp"] doubleValue];
        NSString *date = [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:interval]];
        [lines addObject:[NSString stringWithFormat:@"%@ | %@ | %@ | RSSI %@", date ?: @"", entry[@"name"] ?: @"", entry[@"identifier"] ?: @"", entry[@"rssi"] ?: @0]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

@end
