#import "BluetoothSpooferManager.h"

static NSString *const kSavedBluetoothDataKey = @"SavedBluetoothData";

@interface BluetoothSpooferManager ()

@property (nonatomic, strong) CBCentralManager *centralManager;
@property (nonatomic, strong) CBPeripheralManager *peripheralManager;
@property (nonatomic, assign) BOOL isScanning;
@property (nonatomic, assign) BOOL isSpoofing;
@property (nonatomic, copy, nullable) NSString *savedUUIDString;

@end

@implementation BluetoothSpooferManager

- (instancetype)init {
    self = [super init];
    if (self) {
        _centralManager = [[CBCentralManager alloc] initWithDelegate:self queue:nil];
        _peripheralManager = [[CBPeripheralManager alloc] initWithDelegate:self queue:nil];
        _savedUUIDString = [[NSUserDefaults standardUserDefaults] stringForKey:kSavedBluetoothDataKey];
    }
    return self;
}

// MARK: - الوظائف الرئيسية لنسخ وبث الإشارة

- (void)startScanningAndCopying {
    if (self.centralManager.state != CBManagerStatePoweredOn) {
        [self.delegate didUpdateStatusMessage:@"تأكد من تفعيل البلوتوث في الآيفون"];
        return
    }
    self.isScanning = YES;
    [self.delegate didUpdateScanningState:YES];
    [self.delegate didUpdateStatusMessage:@"جاري البحث عن إشارات البلوتوث القريبة..."];
    [self.centralManager scanForPeripheralsWithServices:nil options:nil];
}

- (void)stopScanning {
    [self.centralManager stopScan];
    self.isScanning = NO;
    [self.delegate didUpdateScanningState:NO];
}

- (void)startSpoofing {
    if (!self.savedUUIDString) {
        [self.delegate didUpdateStatusMessage:@"لا توجد إشارة محفوظة لتقليدها! قم بالنسخ أولاً."];
        return;
    }
    if (self.peripheralManager.state != CBManagerStatePoweredOn) {
        [self.delegate didUpdateStatusMessage:@"تأكد من تفعيل البلوتوث للبث"];
        return;
    }
    
    self.isSpoofing = YES;
    [self.delegate didUpdateSpoofingState:YES];
    [self.delegate didUpdateStatusMessage:@"جاري محاكاة وبث الإشارة المحفوظة بنجاح..."];
    
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:self.savedUUIDString];
    CBUUID *cbUUID = [CBUUID UUIDWithNSUUID:uuid];
    
    // بناء حزمة بيانات التزييف للبث المباشر
    NSDictionary *advertisementData = @{
        CBAdvertisementDataLocalNameKey: @"Spoofed-Device",
        CBAdvertisementDataServiceUUIDsKey: @[cbUUID]
    };
    
    [self.peripheralManager startAdvertising:advertisementData];
}

- (void)stopSpoofing {
    [self.peripheralManager stopAdvertising];
    self.isSpoofing = NO;
    [self.delegate didUpdateSpoofingState:NO];
    [self.delegate didUpdateStatusMessage:@"تم إيقاف تزييف البلوتوث"];
}

// MARK: - Central Manager Delegate (النسخ)

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {}

- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary<NSString *,id> *)advertisementData RSSI:(NSNumber *)RSSI {
    if (peripheral.name.length > 0) {
        NSString *uuidStr = peripheral.identifier.UUIDString;
        
        // حفظ الإشارة في ذاكرة الجهاز
        [[NSUserDefaults standardUserDefaults] setObject:uuidStr forKey:kSavedBluetoothDataKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
        
        self.savedUUIDString = uuidStr;
        [self.delegate didUpdateSavedUUID:uuidStr];
        
        [self stopScanning];
        NSString *successMsg = [NSString stringWithFormat:@"تم نسخ وحفظ إشارة الجهاز: %@", peripheral.name];
        [self.delegate didUpdateStatusMessage:successMsg];
    }
}

// MARK: - Peripheral Manager Delegate (التزييف)

- (void)peripheralManagerDidUpdateState:(CBPeripheralManager *)peripheral {}

@end
