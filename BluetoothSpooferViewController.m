#import <UIKit/UIKit.h>
#import "BluetoothSpooferManager.h"

@interface BluetoothSpooferViewController : UIViewController <BluetoothSpooferDelegate>

@property (nonatomic, strong) BluetoothSpooferManager *spooferManager;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *uuidLabel;
@property (nonatomic, strong) UIButton *scanButton;
@property (nonatomic, strong) UIButton *spoofButton;

@end

@implementation BluetoothSpooferViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = @"أداة البلوتوث";
    
    self.spooferManager = [[BluetoothSpooferManager alloc] init];
    self.spooferManager.delegate = self;
    
    [self setupUI];
    [self updateSavedUUIDLabel:self.spooferManager.savedUUIDString];
}

- (void)setupUI {
    // 1. شاشة عرض الحالة (Status Banner)
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 120, self.view.frame.size.width - 40, 80)];
    self.statusLabel.backgroundColor = [UIColor systemGrayColor];
    self.statusLabel.textColor = [UIColor whiteColor];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.layer.cornerRadius = 12;
    self.statusLabel.clipsToBounds = YES;
    self.statusLabel.text = @"جاهز للاستخدام";
    self.statusLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    [self.view addSubview:self.statusLabel];
    
    // 2. عرض الـ UUID المحفوظ
    self.uuidLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 220, self.view.frame.size.width - 40, 50)];
    self.uuidLabel.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.uuidLabel.textAlignment = NSTextAlignmentCenter;
    self.uuidLabel.font = [UIFont fontWithName:@"Courier" size:13];
    self.uuidLabel.layer.cornerRadius = 8;
    self.uuidLabel.clipsToBounds = YES;
    [self.view addSubview:self.uuidLabel];
    
    // 3. زر النسخ والحفظ
    self.scanButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.scanButton.frame = CGRectMake(20, self.view.frame.size.height - 180, self.view.frame.size.width - 40, 50)];
    self.scanButton.backgroundColor = [UIColor systemBlueColor];
    [self.scanButton setTitle:@"نسخ وحفظ إشارة البلوتوث" forState:UIControlStateNormal];
    [self.scanButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.scanButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    self.scanButton.layer.cornerRadius = 10;
    [self.scanButton addTarget:self action:@selector(scanButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.scanButton];
    
    // 4. زر التزييف والبث عن بعد
    self.spoofButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.spoofButton.frame = CGRectMake(20, self.view.frame.size.height - 110, self.view.frame.size.width - 40, 50)];
    self.spoofButton.backgroundColor = [UIColor systemGreenColor];
    [self.spoofButton setTitle:@"تفعيل التزييف (بث عن بُعد)" forState:UIControlStateNormal];
    [self.spoofButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.spoofButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    self.spoofButton.layer.cornerRadius = 10;
    [self.spoofButton addTarget:self action:@selector(spoofButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.spoofButton];
}

// MARK: - الأزرار وضغطاتها

- (void)scanButtonTapped {
    if (self.spooferManager.isScanning) {
        [self.spooferManager stopScanning];
    } else {
        [self.spooferManager startScanningAndCopying];
    }
}

- (void)spoofButtonTapped {
    if (self.spooferManager.isSpoofing) {
        [self.spooferManager stopSpoofing];
    } else {
        [self.spooferManager startSpoofing];
    }
}

// MARK: - Bluetooth Spoofer Delegate

- (void)didUpdateStatusMessage:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusLabel.text = message;
    });
}

- (void)didUpdateScanningState:(BOOL)isScanning {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (isScanning) {
            [self.scanButton setTitle:@"إيقاف النسخ" forState:UIControlStateNormal];
            self.scanButton.backgroundColor = [UIColor systemRedColor];
            self.statusLabel.backgroundColor = [UIColor systemOrangeColor];
        } else {
            [self.scanButton setTitle:@"نسخ وحفظ إشارة البلوتوث" forState:UIControlStateNormal];
            self.scanButton.backgroundColor = [UIColor systemBlueColor];
            self.statusLabel.backgroundColor = [UIColor systemGrayColor];
        }
    });
}

- (void)didUpdateSpoofingState:(BOOL)isSpoofing {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (isSpoofing) {
            [self.spoofButton setTitle:@"إيقاف التزييف" forState:UIControlStateNormal];
            self.spoofButton.backgroundColor = [UIColor systemRedColor];
            self.statusLabel.backgroundColor = [UIColor systemGreenColor];
        } else {
            [self.spoofButton setTitle:@"تفعيل التزييف (بث عن بُعد)" forState:UIControlStateNormal];
            self.spoofButton.backgroundColor = [UIColor systemGreenColor];
            self.statusLabel.backgroundColor = [UIColor systemGrayColor];
        }
    });
}

- (void)didUpdateSavedUUID:(NSString *)uuidString {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateSavedUUIDLabel:uuidString];
    });
}

- (void)updateSavedUUIDLabel:(NSString *)uuidString {
    if (uuidString) {
        self.uuidLabel.text = [NSString stringWithFormat:@"الإشارة: %@", uuidString];
        self.uuidLabel.textColor = [UIColor systemBlueColor];
        self.spoofButton.alpha = 1.0;
        self.spoofButton.userInteractionEnabled = YES;
    } else {
        self.uuidLabel.text = @"لا توجد إشارة محفوظة";
        self.uuidLabel.textColor = [UIColor systemGrayColor];
        self.spoofButton.alpha = 0.5;
        self.spoofButton.userInteractionEnabled = NO;
    }
}

@end
