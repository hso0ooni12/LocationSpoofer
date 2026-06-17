#import "LSBluetoothManager.h"

@interface LSBluetoothManager () <CBCentralManagerDelegate, CBPeripheralManagerDelegate>

// المدير المسؤول عن البحث والتقاط الأجهزة المحيطة (Central)
@property (nonatomic, strong) CBCentralManager *centralManager;

// المدير المسؤول عن إعادة بث الإشارات المزيفة (Peripheral)
@property (nonatomic, strong) CBPeripheralManager *peripheralManager;

@property (nonatomic, strong) NSDictionary *advertisingData;
@property (nonatomic, readwrite) BOOL isScanning;
@property (nonatomic, readwrite) BOOL isAdvertising;

@end

@implementation LSBluetoothManager

+ (instancetype)shared {
    static LSBluetoothManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // تهيئة كلا المديرين للعمل بالتوازي (الالتقاط والبث)
        _centralManager = [[CBCentralManager alloc] initWithDelegate:self queue:nil];
        _peripheralManager = [[CBPeripheralManager alloc] initWithDelegate:self queue:nil];
        _isScanning = NO;
        _isAdvertising = NO;
    }
    return self;
}

#pragma mark - Scanning Logic (Central)

- (void)startScanning {
    if (self.centralManager.state == CBManagerStatePoweredOn && !self.isScanning) {
        // البحث عن جميع أجهزة BLE المحيطة والسماح بالتكرار لالتقاط تحديثات الـ RSSI المستمرة
        [self.centralManager scanForPeripheralsWithServices:nil options:@{CBCentralManagerScanOptionAllowDuplicatesKey: @YES}];
        self.isScanning = YES;
        NSLog(@"[LSBluetoothManager] بدأت عملية فحص والتقاط إشارات BLE المحيطة...");
    }
}

- (void)stopScanning {
    if (self.isScanning) {
        [self.centralManager stopScan];
        self.isScanning = NO;
        NSLog(@"[LSBluetoothManager] توقفت عملية الفحص.");
    }
}

#pragma mark - Advertising Logic (Peripheral)

- (void)startAdvertisingWithData:(NSDictionary *)data {
    self.advertisingData = data;
    if (self.peripheralManager.state == CBManagerStatePoweredOn) {
        [self.peripheralManager startAdvertising:self.advertisingData];
        self.isAdvertising = YES;
        NSLog(@"[LSBluetoothManager] بدأ بث بيانات البلوتوث المخصصة...");
    }
}

// بناء حزمة بيانات iBeacon برمجياً لإعادة بثها وتزويرها (Spoofing)
- (void)startAdvertisingBeaconWithUUID:(NSUUID *)uuid major:(uint16_t)major minor:(uint16_t)minor measuredPower:(nullable NSNumber *)power {
    
    uint16_t companyIdentifier = 0x004C; // معرف شركة Apple لانتحال بروتوكول iBeacon
    uint8_t beaconType = 0x02;
    uint8_t beaconLength = 0x15;
    
    NSMutableData *beaconData = [NSMutableData data];
    
    // تركيب الهيكل البنائي الافتراضي لحزمة الـ Beacon
    [beaconData appendBytes:&companyIdentifier length:sizeof(companyIdentifier)];
    [beaconData appendBytes:&beaconType length:sizeof(beaconType)];
    [beaconData appendBytes:&beaconLength length:sizeof(beaconLength)];
    
    // استخدام مصفوفة بايت صريحة لتجنب خطأ التجميع uuid_t في بيئة الثيوس
    unsigned char uuidBytes[16];
    [uuid getUUIDBytes:uuidBytes];
    [beaconData appendBytes:uuidBytes length:sizeof(uuidBytes)];
    
    // تحويل الـ Major والـ Minor إلى Big Endian ليتوافق مع بث الشبكات
    uint16_t majorBigEndian = CFSwapInt16HostToBig(major);
    [beaconData appendBytes:&majorBigEndian length:sizeof(majorBigEndian)];
    
    uint16_t minorBigEndian = CFSwapInt16HostToBig(minor);
    [beaconData appendBytes:&minorBigEndian length:sizeof(minorBigEndian)];
    
    // تحديد قوة الإشارة المقاسة (Measured Power) عند مسافة 1 متر
    int8_t measuredPowerByte = power ? [power charValue] : -59;
    [beaconData appendBytes:&measuredPowerByte length:sizeof(measuredPowerByte)];
    
    NSDictionary *advertisementDict = @{
        CBAdvertisementDataManufacturerDataKey: beaconData
    };
    
    [self startAdvertisingWithData:advertisementDict];
}

- (void)stopAdvertising {
    if (self.isAdvertising) {
        [self.peripheralManager stopAdvertising];
        self.isAdvertising = NO;
        NSLog(@"[LSBluetoothManager] توقف بث الإشارات المزيفة.");
    }
}

#pragma mark - CBCentralManagerDelegate (التقاط وتحليل الإشارات)

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    if (central.state == CBManagerStatePoweredOn) {
        NSLog(@"[LSBluetoothManager] نظام الالتقاط (Central) جاهز ومفعل.");
        if (self.isScanning) {
            [self.centralManager scanForPeripheralsWithServices:nil options:nil];
        }
    } else {
        self.isScanning = NO;
        NSLog(@"[LSBluetoothManager] نظام الالتقاط غير متاح حالياً: %ld", (long)central.state);
    }
}

- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary<NSString *,id> *)advertisementData RSSI:(NSNumber *)RSSI {
    
    // استخراج بيانات الشركة المصنعة لفحص ما إذا كانت إشارة iBeacon ليتم حفظها وتزويرها
    NSData *manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey];
    if (manufacturerData && manufacturerData.length >= 25) {
        NSLog(@"[LSBluetoothManager] تم التقاط جهاز يبث حزمة Manufacturer Data: %@", manufacturerData);
    }
}

#pragma mark - CBPeripheralManagerDelegate (حالة البث والتزوير)

- (void)peripheralManagerDidUpdateState:(CBPeripheralManager *)peripheral {
    if (peripheral.state == CBManagerStatePoweredOn) {
        NSLog(@"[LSBluetoothManager] نظام البث والتزوير (Peripheral) جاهز ومفعل.");
        if (self.advertisingData) {
            [self.peripheralManager startAdvertising:self.advertisingData];
            self.isAdvertising = YES;
        }
    } else {
        self.isAdvertising = NO;
        NSLog(@"[LSBluetoothManager] نظام البث غير متاح: %ld", (long)peripheral.state);
    }
}

- (void)peripheralManagerDidStartAdvertising:(CBPeripheralManager *)peripheral error:(nullable NSError *)error {
    if (error) {
        NSLog(@"[LSBluetoothManager] فشل بدء بث الإشارة المزيفة: %@", error.localizedDescription);
        self.isAdvertising = NO;
    } else {
        NSLog(@"[LSBluetoothManager] يتم الآن بث الإشارة التزويرية بنجاح على نطاق الجوار.");
    }
}

@end
