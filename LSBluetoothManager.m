#import "LSBluetoothManager.h"

@interface LSBluetoothManager () <CBPeripheralManagerDelegate, CBCentralManagerDelegate>

@property (nonatomic, strong) CBPeripheralManager *peripheralManager;
@property (nonatomic, strong) CBCentralManager *centralManager;
@property (nonatomic, strong) NSDictionary *advertisingData;
@property (nonatomic, readwrite) BOOL isAdvertising;
@property (nonatomic, readwrite) BOOL isScanning;
@property (nonatomic, strong, readwrite) NSMutableArray<NSDictionary *> *discoveredDevices;

@end

@implementation LSBluetoothManager

+ (instancetype)sharedManager {
    static LSBluetoothManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[LSBluetoothManager alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _discoveredDevices = [[NSMutableArray alloc] init];
        _isAdvertising = NO;
        _isScanning = NO;
    }
    return self;
}

#pragma mark - Scanning Logic (البحث والنسخ)

- (void)startScanning {
    if (!self.centralManager) {
        self.centralManager = [[CBCentralManager alloc] initWithDelegate:self queue:nil options:nil];
    }
    self.isScanning = YES;
    [self.discoveredDevices removeAllObjects];
    if (self.centralManager.state == CBManagerStatePoweredOn) {
        // فحص كافة الأجهزة القريبة بدون فلترة لالتقاط كل شيء
        [self.centralManager scanForPeripheralsWithServices:nil options:@{CBCentralManagerScanOptionAllowDuplicatesKey: @NO}];
    }
}

- (void)stopScanning {
    if (self.centralManager) {
        [self.centralManager stopScan];
    }
    self.isScanning = NO;
}

- (void)clearDiscoveredDevices {
    [self.discoveredDevices removeAllObjects];
    if (self.delegate && [self.delegate respondsToSelector:@selector(blueToothManagerDidUpdateDiscoveredDevices:)]) {
        [self.delegate blueToothManagerDidUpdateDiscoveredDevices:self.discoveredDevices];
    }
}

#pragma mark - CBCentralManagerDelegate

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    if (central.state == CBManagerStatePoweredOn && self.isScanning) {
        [self.centralManager scanForPeripheralsWithServices:nil options:@{CBCentralManagerScanOptionAllowDuplicatesKey: @NO}];
    }
}

- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary<NSString *,id> *)advertisementData RSSI:(NSNumber *)RSSI {
    
    NSString *deviceName = advertisementData[CBAdvertisingDataLocalNameKey] ?: peripheral.name ?: @"جهاز غير معروف";
    NSString *type = @"BLE Generic";
    NSString *uuidString = @"";
    uint16_t major = 0;
    uint16_t minor = 0;
    
    // 💡 فك تشفير حزمة iBeacon إذا كان الجهاز عبارة عن بيكون (وهو المستخدم في البصمات الذكية)
    NSData *manufacturerData = advertisementData[CBAdvertisingDataManufacturerDataKey];
    if (manufacturerData && manufacturerData.length >= 25) {
        const uint8_t *bytes = manufacturerData.bytes;
        // التحقق من معرف شركة آبل وحزمة البيكون المعيارية (0x4C 0x00 0x02 0x15)
        if (bytes[0] == 0x4C && bytes[1] == 0x00 && bytes[2] == 0x02 && bytes[3] == 0x15) {
            type = @"iBeacon (بصمة ذكية)";
            
            // استخراج الـ UUID (16 بايت)
            NSUUID *beaconUUID = [[NSUUID alloc] initWithUUIDBytes:&bytes[4]];
            uuidString = beaconUUID.UUIDString;
            
            // استخراج الـ Major (2 بايت)
            major = (bytes[20] << 8) | bytes[21];
            
            // استخراج الـ Minor (2 بايت)
            minor = (bytes[22] << 8) | bytes[23];
        }
    }
    
    // إذا لم يكن iBeacon، نحاول استخراج الـ Service UUIDs العادية للـ BLE
    if ([uuidString isEqualToString:@""]) {
        NSArray *services = advertisementData[CBAdvertisingDataServiceUUIDsKey];
        if (services.count > 0) {
            CBUUID *firstService = services.firstObject;
            uuidString = firstService.UUIDString;
        } else {
            uuidString = peripheral.identifier.UUIDString; // كخيار بديل
        }
    }
    
    // التحقق من عدم تكرار الجهاز وتحديث بياناته
    BOOL exists = NO;
    for (NSMutableDictionary *device in self.discoveredDevices) {
        if ([device[@"identifier"] isEqualToString:peripheral.identifier.UUIDString]) {
            device[@"rssi"] = RSSI;
            exists = YES;
            break;
        }
    }
    
    if (!exists) {
        NSDictionary *deviceDict = @{
            @"name": deviceName,
            @"type": type,
            @"uuid": uuidString,
            @"major": @(major),
            @"minor": @(minor),
            @"rssi": RSSI,
            @"identifier": peripheral.identifier.UUIDString
        };
        [self.discoveredDevices addObject:deviceDict];
    }
    
    // إرسال البيانات للواجهة لتحديث الجدول فوراً
    if (self.delegate && [self.delegate respondsToSelector:@selector(blueToothManagerDidUpdateDiscoveredDevices:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate blueToothManagerDidUpdateDiscoveredDevices:self.discoveredDevices];
        });
    }
}

#pragma mark - Spoofing Logic (التزييف والبث)

- (void)startSpoofingBeaconWithUUID:(NSString *)uuidStr major:(uint16_t)major minor:(uint16_t)minor {
    [self stopSpoofing];
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:uuidStr];
    if (!uuid) return;
    
    CLBeaconRegion *beaconRegion = [[CLBeaconRegion alloc] initWithProximityUUID:uuid major:major minor:minor identifier:@"SpoofedBeacon"];
    self.advertisingData = [beaconRegion peripheralDataWithMeasuredPower:nil];
    [self initAndStartPeripheral];
}

- (void)startSpoofingGenericBLEWithServiceUUID:(NSString *)serviceUUIDStr localName:(NSString *)name {
    [self stopSpoofing];
    CBUUID *uuid = [CBUUID CBUUIDWithString:serviceUUIDStr];
    if (!uuid) return;
    
    self.advertisingData = @{
        CBAdvertisingDataServiceUUIDsKey: @[uuid],
        CBAdvertisingDataLocalNameKey: name ?: @"BLE Device"
    };
    [self initAndStartPeripheral];
}

- (void)initAndStartPeripheral {
    if (!self.peripheralManager) {
        self.peripheralManager = [[CBPeripheralManager alloc] initWithDelegate:self queue:nil options:nil];
    } else {
        [self peripheralManagerDidUpdateState:self.peripheralManager];
    }
}

- (void)stopSpoofing {
    if (self.peripheralManager && self.peripheralManager.isAdvertising) {
        [self.peripheralManager stopAdvertising];
    }
    self.isAdvertising = NO;
}

- (void)peripheralManagerDidUpdateState:(CBPeripheralManager *)peripheral {
    if (peripheral.state == CBPeripheralManagerStatePoweredOn) {
        if (self.advertisingData) {
            [self.peripheralManager startAdvertising:self.advertisingData];
            self.isAdvertising = YES;
        }
    } else {
        self.isAdvertising = NO;
    }
}

@end
