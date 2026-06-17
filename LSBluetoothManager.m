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

// 1️⃣ دالات C خارجية لتمثيل الـ Delegates (مخفية تماماً عن فحص المترجم الصارم)
static void dynamic_centralManagerDidUpdateState(id self, SEL _cmd, id central) {
    @try {
        // قراءة الحالة بأمان عبر KVC لتفادي أي كاستنج مجهول
        NSInteger state = [[central valueForKey:@"state"] integerValue];
        NSLog(@"[LSBluetoothManager] تحديث حالة الالتقاط المركزي ديناميكياً: %ld", (long)state);
    } @catch (NSException *exception) {
        NSLog(@"[LSBluetoothManager] تحذير في الاستدعاء المركزي: %@", exception.reason);
    }
}

static void dynamic_peripheralManagerDidUpdateState(id self, SEL _cmd, id peripheral) {
    @try {
        NSInteger state = [[peripheral valueForKey:@"state"] integerValue];
        NSLog(@"[LSBluetoothManager] تحديث حالة البث الفرعي ديناميكياً: %ld", (long)state);
    } @catch (NSException *exception) {
        NSLog(@"[LSBluetoothManager] تحذير في استدعاء البث: %@", exception.reason);
    }
}

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
        
        // 2️⃣ حقن الدالات ديناميكياً في الـ Class لتخطي حماية المترجم (Clang) بنسبة 100%
        Class cls = [self class];
        class_addMethod(cls, NSSelectorFromString(@"centralManagerDidUpdateState:"), (IMP)dynamic_centralManagerDidUpdateState, "v@:@");
        class_addMethod(cls, NSSelectorFromString(@"peripheralManagerDidUpdateState:"), (IMP)dynamic_peripheralManagerDidUpdateState, "v@:@");
        
        Class CBCentralManagerClass = NSClassFromString(@"CBCentralManager");
        Class CBPeripheralManagerClass = NSClassFromString(@"CBPeripheralManager");
        
        if (CBCentralManagerClass && CBPeripheralManagerClass) {
            // استدعاء محرك التخصيص عبر objc_msgSend الصافي والمتوافق كلياً مع ARC
            id (*sendInitWithDelegate)(id, SEL, id, id) = (id (*)(id, SEL, id, id))objc_msgSend;
            
            _centralManager = sendInitWithDelegate([CBCentralManagerClass alloc], NSSelectorFromString(@"initWithDelegate:queue:"), self, nil);
            _peripheralManager = sendInitWithDelegate([CBPeripheralManagerClass alloc], NSSelectorFromString(@"initWithDelegate:queue:"), self, nil);
        }
    }
    return self;
}

- (void)startScanning {
    if (!self.isScanning && self.centralManager) {
        SEL scanSelector = NSSelectorFromString(@"scanForPeripheralsWithServices:options:");
        if ([self.centralManager respondsToSelector:scanSelector]) {
            NSDictionary *options = @{@"CBCentralManagerScanOptionAllowDuplicatesKey": @YES};
            
            void (*sendScan)(id, SEL, id, id) = (void (*)(id, SEL, id, id))objc_msgSend;
            sendScan(self.centralManager, scanSelector, nil, options);
            
            self.isScanning = YES;
            NSLog(@"[LSBluetoothManager] بدأت عملية فحص البلوتوث بنجاح.");
        }
    }
}

- (void)stopScanning {
    if (self.isScanning && self.centralManager) {
        SEL stopSelector = NSSelectorFromString(@"stopScan");
        if ([self.centralManager respondsToSelector:stopSelector]) {
            void (*sendStop)(id, SEL) = (void (*)(id, SEL))objc_msgSend;
            sendStop(self.centralManager, stopSelector);
            
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
        void (*sendAdv)(id, SEL, id) = (void (*)(id, SEL, id))objc_msgSend;
        sendAdv(self.peripheralManager, advSelector, self.advertisingData);
        
        self.isAdvertising = YES;
        NSLog(@"[LSBluetoothManager] بدأ بث بيانات الموقع المزيفة.");
    }
}

- (void)stopAdvertising {
    if (self.isAdvertising && self.peripheralManager) {
        SEL stopSelector = NSSelectorFromString(@"stopAdvertising");
        if ([self.peripheralManager respondsToSelector:stopSelector]) {
            void (*sendStopAdv)(id, SEL) = (void (*)(id, SEL))objc_msgSend;
            sendStopAdv(self.peripheralManager, stopSelector);
            
            self.isAdvertising = NO;
            NSLog(@"[LSBluetoothManager] توقف بث البلوتوث.");
        }
    }
}

@end
