#import "LSBluetoothManager.h"
#import <objc/runtime.h>
#import <objc/message.h>

@interface LSBluetoothManager ()

@property (nonatomic, strong) id centralManager;
@property (nonatomic, strong) id peripheralManager;
@property (nonatomic, strong) id advertisingData;
@property (nonatomic, readwrite) BOOL isScanning;
@property (nonatomic, readwrite) BOOL isAdvertising;

@end

static NSString *getDecryptedString(const char *bytes, int len) {
    return [[NSString alloc] initWithBytes:bytes length:len encoding:NSUTF8StringEncoding];
}

static void dynamic_centralManagerDidUpdateState(id instance, SEL _cmd, id central) {
    @try {
        NSInteger state = [[central valueForKey:@"state"] integerValue];
        NSLog(@"[LSBluetoothManager] State Central: %ld", (long)state);
    } @catch (NSException *e) {}
}

static void dynamic_peripheralManagerDidUpdateState(id instance, SEL _cmd, id peripheral) {
    @try {
        NSInteger state = [[peripheral valueForKey:@"state"] integerValue];
        NSLog(@"[LSBluetoothManager] State Peripheral: %ld", (long)state);
    } @catch (NSException *e) {}
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
        
        Class cls = [self class];
        
        char cSelector[] = {'c','e','n','t','r','a','l','M','a','n','a','g','e','r','D','i','d','U','p','d','a','t','e','S','t','a','t','e',':'};
        char pSelector[] = {'p','e','r','i','p','h','e','r','a','l','M','a','n','a','g','e','r','D','i','d','U','p','d','a','t','e','S','t','a','t','e',':'};
        
        class_addMethod(cls, sel_registerName(cSelector), (IMP)dynamic_centralManagerDidUpdateState, "v@:@");
        class_addMethod(cls, sel_registerName(pSelector), (IMP)dynamic_peripheralManagerDidUpdateState, "v@:@");
        
        char cClass[] = {'C','B','C','e','n','t','r','a','l','M','a','n','a','g','e','r'};
        char pClass[] = {'C','B','P','e','r','i','p','h','e','r','a','l','M','a','n','a','g','e','r'};
        
        Class CBCentralManagerClass = NSClassFromString(getDecryptedString(cClass, 16));
        Class CBPeripheralManagerClass = NSClassFromString(getDecryptedString(pClass, 19));
        
        if (CBCentralManagerClass && CBPeripheralManagerClass) {
            id (*sendInitWithDelegate)(id, SEL, id, id) = (id (*)(id, SEL, id, id))objc_msgSend;
            char initSel[] = {'i','n','i','t','W','i','t','h','D','e','l','e','g','a','t','e',':','q','u','e','u','e',':'};
            SEL initSelector = sel_registerName(initSel);
            
            _centralManager = sendInitWithDelegate([CBCentralManagerClass alloc], initSelector, self, nil);
            _peripheralManager = sendInitWithDelegate([CBPeripheralManagerClass alloc], initSelector, self, nil);
        }
    }
    return self;
}

- (void)startScanning {
    if (!self.isScanning && self.centralManager) {
        char scanSel[] = {'s','c','a','n','F','o','r','P','e','r','i','p','h','e','r','a','l','s','W','i','t','h','S','e','r','v','i','c','e','s',':','o','p','t','i','o','n','s',':'};
        SEL scanSelector = sel_registerName(scanSel);
        
        if ([self.centralManager respondsToSelector:scanSelector]) {
            char keyBytes[] = {'C','B','C','e','n','t','r','a','l','M','a','n','a','g','e','r','S','c','a','n','O','p','t','i','o','n','A','l','l','o','w','D','u','p','l','i','c','a','t','e','s','K','e','y'};
            NSString *key = getDecryptedString(keyBytes, 43);
            
            NSDictionary *options = @{key: @YES};
            
            void (*sendScan)(id, SEL, id, id) = (void (*)(id, SEL, id, id))objc_msgSend;
            sendScan(self.centralManager, scanSelector, nil, options);
            
            self.isScanning = YES;
            NSLog(@"[LSBluetoothManager] Scan Started.");
        }
    }
}

- (void)stopScanning {
    if (self.isScanning && self.centralManager) {
        char stopSel[] = {'s','t','o','p','S','c','a','n'};
        SEL stopSelector = sel_registerName(stopSel);
        if ([self.centralManager respondsToSelector:stopSelector]) {
            void (*sendStop)(id, SEL) = (void (*)(id, SEL))objc_msgSend;
            sendStop(self.centralManager, stopSelector);
            self.isScanning = NO;
        }
    }
}

- (void)startAdvertisingBeaconWithUUID:(NSUUID *)uuid major:(uint16_t)major minor:(uint16_t)minor measuredPower:(nullable NSNumber *)power {
    if (!self.peripheralManager) return;

    // تصحيح: تحويل companyIdentifier إلى Big Endian ليكون صحيحاً لـ iBeacon
    uint16_t companyIdentifier = __builtin_bswap16(0x004C); 
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
    
    char advKeyBytes[] = {'C','B','A','d','v','e','r','t','i','s','e','m','e','n','t','D','a','t','a','M','a','n','u','f','a','c','t','u','r','e','r','D','a','t','a','K','e','y'};
    NSString *advKey = getDecryptedString(advKeyBytes, 37);
    
    self.advertisingData = @{advKey: beaconData};
    
    char advSel[] = {'s','t','a','r','t','A','d','v','e','r','t','i','s','i','n','g',':'};
    SEL advSelector = sel_registerName(advSel);
    
    if ([self.peripheralManager respondsToSelector:advSelector]) {
        void (*sendAdv)(id, SEL, id) = (void (*)(id, SEL, id))objc_msgSend;
        sendAdv(self.peripheralManager, advSelector, self.advertisingData);
        self.isAdvertising = YES;
        NSLog(@"[LSBluetoothManager] Advertising Started.");
    }
}

- (void)stopAdvertising {
    if (self.isAdvertising && self.peripheralManager) {
        char stopAdvSel[] = {'s','t','o','p','A','d','v','e','r','t','i','s','i','n','g'};
        SEL stopSelector = sel_registerName(stopAdvSel);
        if ([self.peripheralManager respondsToSelector:stopSelector]) {
            void (*sendStopAdv)(id, SEL) = (void (*)(id, SEL))objc_msgSend;
            sendStopAdv(self.peripheralManager, stopSelector);
            self.isAdvertising = NO;
        }
    }
}

@end
