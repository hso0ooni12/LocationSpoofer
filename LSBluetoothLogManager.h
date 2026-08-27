#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LSBluetoothLogManager : NSObject
+ (NSArray<NSDictionary<NSString *, id> *> *)entries;
+ (void)recordName:(nullable NSString *)name identifier:(NSString *)identifier rssi:(NSNumber *)rssi;
+ (void)clear;
+ (NSString *)exportText;
@end

NS_ASSUME_NONNULL_END
