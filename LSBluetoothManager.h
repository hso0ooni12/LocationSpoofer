#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import <CoreLocation/CoreLocation.h>

@protocol LSBluetoothManagerDelegate <NSObject>
- (void)blueToothManagerDidUpdateDiscoveredDevices:(NSArray<NSDictionary *> *)devices;
@end

@interface LSBluetoothManager : NSObject

+ (instancetype)sharedManager;
@property (nonatomic, weak) id<LSBluetoothManagerDelegate> delegate;
@property (nonatomic, readonly) BOOL isAdvertising;
@property (nonatomic, readonly) BOOL isScanning;
@property (nonatomic, strong, readonly) NSMutableArray<NSDictionary *> *discoveredDevices;

// أساليب المسح (Scanning)
- (void)startScanning;
- (void)stopScanning;
- (void)clearDiscoveredDevices;

// أساليب التزييف (Spoofing)
- (void)startSpoofingBeaconWithUUID:(NSString *)uuidStr major:(uint16_t)major minor:(uint16_t)minor;
- (void)startSpoofingGenericBLEWithServiceUUID:(NSString *)serviceUUIDStr localName:(NSString *)name;
- (void)stopSpoofing;

@end
