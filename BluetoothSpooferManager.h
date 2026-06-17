#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>

@protocol BluetoothSpooferDelegate <NSObject>
- (void)didUpdateStatusMessage:(NSString *)message;
- (void)didUpdateScanningState:(BOOL)isScanning;
- (void)didUpdateSpoofingState:(BOOL)isSpoofing;
- (void)didUpdateSavedUUID:(NSString *)uuidString;
@end

@interface BluetoothSpooferManager : NSObject <CBCentralManagerDelegate, CBPeripheralManagerDelegate>

@property (nonatomic, weak) id<BluetoothSpooferDelegate> delegate;
@property (nonatomic, readonly) BOOL isScanning;
@property (nonatomic, readonly) BOOL isSpoofing;
@property (nonatomic, readonly, nullable) NSString *savedUUIDString;

- (void)startScanningAndCopying;
- (void)stopScanning;
- (void)startSpoofing;
- (void)stopSpoofing;

@end
