#import "LSBluetoothManager.h"
#import <objc/runtime.h>
#import <objc/message.h>

@interface LSBluetoothManager ()

@property (nonatomic, strong) id centralManager;
@property (nonatomic, strong) id peripheralManager;
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
        _isScanning = NO;
        _isAdvertising = NO;
        
        Class CBCentralManagerClass = NSClassFromString(@"CBCentralManager");
        Class CBPeripheralManagerClass = NSClassFromString(@"CBPeripheralManager");
        
        if (CBCentralManagerClass && CBPeripheralManagerClass) {
            // استخدام صب دالة objc_msgSend لمنع كافة مشاكل مؤشرات الـ ARC
            id (*initFunc)(id, SEL, id, id) = (id (*)(id, SEL, id, id))objc_msgSend;
            
            _centralManager = initFunc([CBCentralManagerClass alloc], NSSelectorFromString(@"initWithDelegate:queue:"), self, nil);
            _peripheralManager = initFunc([CBPeripheralManagerClass alloc], NSSelectorFromString(@"initWithDelegate:queue:"), self, nil);
        }
    }
    return self;
}

- (void)startScanning {
    if (!self.isScanning && self.centralManager) {
        SEL scanSelector = NSSelectorFromString(@"scanForPeripheralsWithServices:options:");
        
        // المفاتيح النصية الفعلية للنظام لضمان التوافق التام دون استدعاء مكتبات خارجية
        NSDictionary *options = @{@"kCBScanOptionAllowDuplicates": @YES};
        
        void (*scanFunc)(id, SEL, id, id) = (void (*)(id, SEL, id, id))objc_msgSend;
        scanFunc(self.centralManager, scanSelector, nil, options);
        
        self.isScanning = YES;
        NSLog(@"[LSBluetoothManager] بدأت عملية الفحص بنجاح.");
    }
}

- (void)stopScanning {
    if (self.isScanning && self.centralManager) {
        SEL stopSelector = NSSelectorFromString(@"stopScan");
        void (*stopScanFunc)(id, SEL) = (void (*)(id, SEL))objc_msgSend;
        stopScanFunc(self.centralManager, stopSelector);
        
        self.isScanning = NO;
        NSLog(@"[LSBluetoothManager] توقف الفحص.");
    }
}

- (void)startAdvertisingBeaconWithUUID:(NSUUID *)uuid major:(uint16_t)major minor:(uint16_t)minor measuredPower:(nullable NSNumber *)power {
    if (!self.peripheralManager) return;

    uint16_t companyIdentifier = 0x004C; 
    uint8_t beaconType = 0x02;
    uint8_t beaconLength = 0x15;
    
    NSMutableData *beaconData = [NSMutableData data];
    [beaconData appendBytes:&companyIdentifier length:sizeof(companyIdentifier)];
    [beaconData appendBytes:&beaconType length:sizeof(beaconType)];
    [beaconData appendBytes:&beaconLength length:sizeof(beaconLength)];
    
    unsigned char uuidBytes[16];
    [uuid getUUIDBytes:uuidBytes];
    [beaconData appendBytes:uuidBytes length:sizeof(uuidBytes)];
    
    uint16_t majorBigEndian = __builtin_bswap16(major);
    [beaconData appendBytes:&majorBigEndian length:sizeof(majorBigEndian)];
    
    uint16_t minorBigEndian = __builtin_bswap16(minor);
    [beaconData appendBytes:&minorBigEndian length:sizeof(minorBigEndian)];
    
    int8_t measuredPowerByte = power ? [power charValue] : -59;
    [beaconData appendBytes:&measuredPowerByte length:sizeof(measuredPowerByte)];
    
    // kCBAdvDataManufacturerData هو المفتاح الداخلي الفعلي لبيانات البث
    self.advertisingData = @{@"kCBAdvDataManufacturerData": beaconData};
    
    SEL advSelector = NSSelectorFromString(@"startAdvertising:");
    void (*advFunc)(id, SEL, id) = (void (*)(id, SEL, id))objc_msgSend;
    advFunc(self.peripheralManager, advSelector, self.advertisingData);
    
    self.isAdvertising = YES;
    NSLog(@"[LSBluetoothManager] بدأ بث الإشارة التزويرية.");
}

- (void)stopAdvertising {
    if (self.isAdvertising && self.peripheralManager) {
        SEL stopSelector = NSSelectorFromString(@"stopAdvertising");
        void (*stopAdvFunc)(id, SEL) = (void (*)(id, SEL))objc_msgSend;
        stopAdvFunc(self.peripheralManager, stopSelector);
        
        self.isAdvertising = NO;
        NSLog(@"[LSBluetoothManager] توقف البث.");
    }
}

// الـ Delegates لتجنب أي تحذيرات أثناء التشغيل
- (void)centralManagerDidUpdateState:(id)central {}
- (void)peripheralManagerDidUpdateState:(id)peripheral {}

@end
