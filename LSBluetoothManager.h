#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LSBluetoothManager : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) BOOL isScanning;
@property (nonatomic, readonly) BOOL isAdvertising;

- (void)startScanning;
- (void)stopScanning;
- (void)startAdvertisingBeaconWithUUID:(NSUUID *)uuid major:(uint16_t)major minor:(uint16_t)minor measuredPower:(nullable NSNumber *)power;
- (void)stopAdvertising;

@end

NS_ASSUME_NONNULL_END
