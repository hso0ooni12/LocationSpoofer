#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>

NS_ASSUME_NONNULL_BEGIN

@interface LSBluetoothManager : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) BOOL isScanning;
@property (nonatomic, readonly) BOOL isAdvertising;

// ميثودات التحكم في البحث والالتقاط (Central)
- (void)startScanning;
- (void)stopScanning;

// ميثودات التحكم في البث والتزوير (Peripheral)
- (void)startAdvertisingWithData:(NSDictionary *)data;
- (void)startAdvertisingBeaconWithUUID:(NSUUID *)uuid major:(uint16_t)major minor:(uint16_t)minor measuredPower:(nullable NSNumber *)power;
- (void)stopAdvertising;

@end

NS_ASSUME_NONNULL_END
