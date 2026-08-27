#import "BluetoothSpooferManager.h"

static NSString *const kSavedBluetoothDataKey = @"SavedBluetoothData";
static NSString *const kLSBluetoothDefaultsSuiteName = @"com.xsgps.dylib";

static NSUserDefaults *LSBluetoothToolDefaults(void) {
    return [[NSUserDefaults alloc] initWithSuiteName:kLSBluetoothDefaultsSuiteName] ?: NSUserDefaults.standardUserDefaults;
}

@interface BluetoothSpooferManager ()

@property (nonatomic, strong) CBCentralManager *centralManager;
@property (nonatomic, strong) CBPeripheralManager *peripheralManager;
@property (nonatomic, assign) BOOL isScanning;
@property (nonatomic, assign) BOOL isSpoofing;
@property (nonatomic, copy, nullable) NSString *savedUUIDString;
@property (nonatomic, assign) BOOL pendingScanRequest;
@property (nonatomic, assign) BOOL pendingSpoofRequest;

@end

@implementation BluetoothSpooferManager

- (instancetype)init {
    self = [super init];
    if (self) {
        _centralManager = [[CBCentralManager alloc] initWithDelegate:self queue:nil];
        _peripheralManager = [[CBPeripheralManager alloc] initWithDelegate:self queue:nil];
        NSString *storedUUID = [LSBluetoothToolDefaults() stringForKey:kSavedBluetoothDataKey];
        if (storedUUID.length == 0) {
            storedUUID = [NSUserDefaults.standardUserDefaults stringForKey:kSavedBluetoothDataKey];
        }
        _savedUUIDString = [self normalizedUUIDString:storedUUID];
    }
    return self;
}

// MARK: - الوظائف الرئيسية لنسخ وبث الإشارة


- (nullable NSString *)normalizedUUIDString:(NSString *)value {
    if (![value isKindOfClass:NSString.class]) { return nil; }
    NSString *clean = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (clean.length == 0) { return nil; }
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:clean];
    if (uuid.UUIDString.length > 0) { return uuid.UUIDString; }
    @try {
        CBUUID *cbUUID = [CBUUID UUIDWithString:clean];
        if (cbUUID.UUIDString.length > 0) { return cbUUID.UUIDString; }
    } @catch (__unused NSException *exception) {
        return nil;
    }
    return nil;
}

- (void)notifyStatus:(NSString *)message {
    if (!message.length) { return; }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate didUpdateStatusMessage:message];
    });
}

- (void)notifyScanningState:(BOOL)isScanning {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate didUpdateScanningState:isScanning];
    });
}

- (void)notifySpoofingState:(BOOL)isSpoofing {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate didUpdateSpoofingState:isSpoofing];
    });
}

- (void)notifySavedUUID:(nullable NSString *)uuidString {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate didUpdateSavedUUID:uuidString];
    });
}

- (void)persistSavedUUID:(nullable NSString *)uuidString {
    NSUserDefaults *toolDefaults = LSBluetoothToolDefaults();
    if (uuidString.length > 0) {
        [toolDefaults setObject:uuidString forKey:kSavedBluetoothDataKey];
        [NSUserDefaults.standardUserDefaults setObject:uuidString forKey:kSavedBluetoothDataKey];
    } else {
        [toolDefaults removeObjectForKey:kSavedBluetoothDataKey];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:kSavedBluetoothDataKey];
    }
    [toolDefaults synchronize];
    [NSUserDefaults.standardUserDefaults synchronize];
}

- (void)ls_beginScanIfReady {
    if (self.centralManager.state != CBManagerStatePoweredOn) {
        return;
    }
    self.pendingScanRequest = NO;
    if (self.isScanning) {
        return;
    }
    self.isScanning = YES;
    [self notifyScanningState:YES];
    [self notifyStatus:@"جاري البحث عن إشارات البلوتوث القريبة..."];
    NSDictionary *options = @{ CBCentralManagerScanOptionAllowDuplicatesKey: @YES };
    [self.centralManager scanForPeripheralsWithServices:nil options:options];
}

- (void)startScanningAndCopying {
    CBManagerState state = self.centralManager.state;
    if (state == CBManagerStatePoweredOn) {
        [self ls_beginScanIfReady];
        return;
    }

    if (state == CBManagerStateUnknown || state == CBManagerStateResetting) {
        self.pendingScanRequest = YES;
        [self notifyStatus:@"جاري تجهيز البلوتوث... انتظر لحظة"];
        return;
    }

    if (state == CBManagerStateUnauthorized) {
        [self notifyStatus:@"اسمح للتطبيق باستخدام البلوتوث من الإعدادات"];
    } else if (state == CBManagerStateUnsupported) {
        [self notifyStatus:@"هذا الجهاز لا يدعم Bluetooth LE"];
    } else {
        [self notifyStatus:@"فعّل البلوتوث من مركز التحكم ثم حاول مرة أخرى"];
    }
}

- (void)stopScanning {
    [self.centralManager stopScan];
    self.isScanning = NO;
    [self notifyScanningState:NO];
}

- (void)ls_beginSpoofIfReady {
    if (!self.savedUUIDString) {
        [self notifyStatus:@"لا توجد إشارة محفوظة. انسخ إشارة أولاً."];
        return;
    }
    if (self.peripheralManager.state != CBManagerStatePoweredOn) {
        return;
    }
    self.pendingSpoofRequest = NO;
    if (self.isSpoofing) {
        return;
    }

    NSString *normalized = [self normalizedUUIDString:self.savedUUIDString];
    CBUUID *cbUUID = nil;
    if (normalized.length > 0) {
        @try { cbUUID = [CBUUID UUIDWithString:normalized]; } @catch (__unused NSException *exception) { cbUUID = nil; }
    }
    if (!cbUUID) {
        self.savedUUIDString = nil;
        [self persistSavedUUID:nil];
        [self notifySavedUUID:nil];
        [self notifyStatus:@"الإشارة المحفوظة غير صالحة، احذفها وانسخ من جديد"];
        return;
    }

    NSDictionary *advertisementData = @{
        CBAdvertisementDataLocalNameKey: @"XsGpS-BLE",
        CBAdvertisementDataServiceUUIDsKey: @[cbUUID]
    };

    [self.peripheralManager startAdvertising:advertisementData];
    [self notifyStatus:@"جاري تفعيل بث الإشارة المحفوظة..."];
}

- (void)startSpoofing {
    if (!self.savedUUIDString) {
        [self notifyStatus:@"لا توجد إشارة محفوظة. انسخ إشارة أولاً."];
        return;
    }
    CBManagerState state = self.peripheralManager.state;
    if (state == CBManagerStatePoweredOn) {
        [self ls_beginSpoofIfReady];
        return;
    }
    if (state == CBManagerStateUnknown || state == CBManagerStateResetting) {
        self.pendingSpoofRequest = YES;
        [self notifyStatus:@"جاري تجهيز بث البلوتوث... انتظر لحظة"];
        return;
    }
    if (state == CBManagerStateUnauthorized) {
        [self notifyStatus:@"اسمح للتطبيق باستخدام البلوتوث من الإعدادات"];
    } else if (state == CBManagerStateUnsupported) {
        [self notifyStatus:@"هذا الجهاز لا يدعم بث Bluetooth LE"];
    } else {
        [self notifyStatus:@"فعّل البلوتوث ثم حاول مرة أخرى"];
    }
}

- (void)stopSpoofing {
    [self.peripheralManager stopAdvertising];
    self.isSpoofing = NO;
    [self notifySpoofingState:NO];
    [self notifyStatus:@"تم إيقاف بث إشارة البلوتوث"];
}

- (void)clearSavedSignal {
    [self stopScanning];
    if (self.isSpoofing) {
        [self stopSpoofing];
    }
    self.savedUUIDString = nil;
    [self persistSavedUUID:nil];
    [self notifySavedUUID:nil];
    [self notifyStatus:@"تم حذف الإشارة المحفوظة"];
}

// MARK: - Central Manager Delegate (النسخ)

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    (void)central;
    if (self.centralManager.state == CBManagerStatePoweredOn) {
        if (self.pendingScanRequest) {
            [self ls_beginScanIfReady];
        } else {
            [self notifyStatus:@"البلوتوث جاهز للبحث والنسخ"];
        }
    } else if (self.centralManager.state == CBManagerStateUnauthorized) {
        self.pendingScanRequest = NO;
        [self notifyStatus:@"اسمح للتطبيق باستخدام البلوتوث من الإعدادات"];
    } else if (self.centralManager.state == CBManagerStatePoweredOff) {
        self.pendingScanRequest = NO;
        [self notifyStatus:@"فعّل البلوتوث من مركز التحكم"];
    }
}

- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary<NSString *,id> *)advertisementData RSSI:(NSNumber *)RSSI {
    (void)central;
    (void)RSSI;
    NSString *uuidStr = peripheral.identifier.UUIDString;
    if (uuidStr.length == 0) {
        NSArray<CBUUID *> *serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey];
        CBUUID *firstUUID = serviceUUIDs.firstObject;
        uuidStr = firstUUID.UUIDString;
    }
    if (uuidStr.length == 0) {
        return;
    }

    NSString *deviceName = peripheral.name;
    NSString *localName = advertisementData[CBAdvertisementDataLocalNameKey];
    if (deviceName.length == 0 && [localName isKindOfClass:NSString.class]) {
        deviceName = localName;
    }
    if (deviceName.length == 0) {
        deviceName = @"جهاز قريب";
    }

    NSString *normalizedUUID = [self normalizedUUIDString:uuidStr] ?: uuidStr;
    [self persistSavedUUID:normalizedUUID];

    self.savedUUIDString = normalizedUUID;
    [self notifySavedUUID:normalizedUUID];
    [self stopScanning];

    NSString *successMsg = [NSString stringWithFormat:@"تم نسخ وحفظ إشارة: %@", deviceName];
    [self notifyStatus:successMsg];
}

// MARK: - Peripheral Manager Delegate (التزييف)

- (void)peripheralManagerDidUpdateState:(CBPeripheralManager *)peripheral {
    (void)peripheral;
    if (self.peripheralManager.state == CBManagerStatePoweredOn) {
        if (self.pendingSpoofRequest) {
            [self ls_beginSpoofIfReady];
        }
    } else if (self.peripheralManager.state == CBManagerStateUnauthorized) {
        self.pendingSpoofRequest = NO;
        [self notifyStatus:@"اسمح للتطبيق باستخدام البلوتوث من الإعدادات"];
    } else if (self.peripheralManager.state == CBManagerStatePoweredOff) {
        self.pendingSpoofRequest = NO;
        if (self.isSpoofing) {
            [self stopSpoofing];
        }
        [self notifyStatus:@"فعّل البلوتوث من مركز التحكم"];
    }
}

- (void)peripheralManagerDidStartAdvertising:(CBPeripheralManager *)peripheral error:(NSError *)error {
    (void)peripheral;
    if (error) {
        self.isSpoofing = NO;
        [self notifySpoofingState:NO];
        [self notifyStatus:[NSString stringWithFormat:@"فشل بث البلوتوث: %@", error.localizedDescription ?: @"خطأ غير معروف"]];
        return;
    }

    self.isSpoofing = YES;
    [self notifySpoofingState:YES];
    [self notifyStatus:@"تم تفعيل بث الإشارة المحفوظة"];
}

@end
