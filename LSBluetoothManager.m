#import "LSBluetoothManager.h"

// إعلان مسبق للفئات لتفادي تعارض الـ Signatures في المترجم الصارم دون استدعاء ملفات نظام
@class CBCentralManager;
@class CBPeripheralManager;

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
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            
            id allocatedCentral = [CBCentralManagerClass alloc];
            _centralManager = [allocatedCentral performSelector:NSSelectorFromString(@"initWithDelegate:queue:") withObject:self withObject:nil];
            
            id allocatedPeripheral = [CBPeripheralManagerClass alloc];
            _peripheralManager = [allocatedPeripheral performSelector:NSSelectorFromString(@"initWithDelegate:queue:") withObject:self withObject:nil];
            
            #pragma clang diagnostic pop
        }
    }
    return self;
}

- (void)startScanning {
    if (!self.isScanning && self.centralManager) {
        SEL scanSelector = NSSelectorFromString(@"scanForPeripheralsWithServices:options:");
        if ([self.centralManager respondsToSelector:scanSelector]) {
            NSDictionary *options = @{@"CBCentralManagerScanOptionAllowDuplicatesKey": @YES};
            
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [self.centralManager performSelector:scanSelector withObject:nil withObject:options];
            #pragma clang diagnostic pop
            
            self.isScanning = YES;
            NSLog(@"[LSBluetoothManager] بدأت عملية فحص البلوتوث بنجاح.");
        }
    }
}

- (void)stopScanning {
    if (self.isScanning && self.centralManager) {
        SEL stopSelector = NSSelectorFromString(@"stopScan");
        if ([self.centralManager respondsToSelector:stopSelector]) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [self.centralManager performSelector:stopSelector];
            #pragma clang diagnostic pop
            
            self.isScanning = NO;
            NSLog(@"[LSBluetoothManager] توقف الفحص.");
        }
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
    
    self.advertisingData = @{@"kCBAdvDataManufacturerData": beaconData};
    
    SEL advSelector = NSSelectorFromString(@"startAdvertising:");
    if ([self.peripheralManager respondsToSelector:advSelector]) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [self.peripheralManager performSelector:advSelector withObject:self.advertisingData];
        #pragma clang diagnostic pop
        
        self.isAdvertising = YES;
        NSLog(@"[LSBluetoothManager] بدأ بث بيانات الموقع المزيفة.");
    }
}

- (void)stopAdvertising {
    if (self.isAdvertising && self.peripheralManager) {
        SEL stopSelector = NSSelectorFromString(@"stopAdvertising");
        if ([self.peripheralManager respondsToSelector:stopSelector]) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [self.peripheralManager performSelector:stopSelector];
            #pragma clang diagnostic pop
            
            self.isAdvertising = NO;
            NSLog(@"[LSBluetoothManager] توقف بث البلوتوث.");
        }
    }
}

#pragma mark - Delegate Callbacks (مطابقة تامة لمنع أخطاء المترجم الصارم)

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    @try {
        // تحويل الكائن برمجياً إلى id لتخطي الحماية وقراءة الحالة بأمان عبر KVC
        NSInteger state = [[(id)central valueForKey:@"state"] integerValue];
        NSLog(@"[LSBluetoothManager] تحديث حالة الالتقاط المركزي: %ld", (long)state);
    } @catch (NSException *exception) {
        NSLog(@"[LSBluetoothManager] تحذير أثناء جلب الحالة: %@", exception.reason);
    }
}

- (void)peripheralManagerDidUpdateState:(CBPeripheralManager *)peripheral {
    @try {
        NSInteger state = [[(id)peripheral valueForKey:@"state"] integerValue];
        NSLog(@"[LSBluetoothManager] تحديث حالة البث الفرعي: %ld", (long)state);
    } @catch (NSException *exception) {
        NSLog(@"[LSBluetoothManager] تحذير أثناء جلب الحالة: %@", exception.reason);
    }
}

@end
