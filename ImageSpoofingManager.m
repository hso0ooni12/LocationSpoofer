#import "ImageSpoofingManager.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <AVFoundation/AVFoundation.h>

static NSString * const kLSImageToolSuiteName = @"com.xsgps.dylib";
static NSString * const kLSReferenceEnabledKey = @"LSReferenceImageEnabled";
static NSString * const kLSReferenceImageFileName = @"reference_image.jpg";
static const char *kLSSpoofedDataKey = "kLSSpoofedDataKey";
static void LSCameraSpoofCaptureOutput(id self, SEL _cmd, AVCapturePhotoOutput *output, AVCapturePhoto *photo, NSError *error) API_AVAILABLE(ios(11.0));
static void LSHookCaptureDelegateClass(Class cls);
static void LSHookPhotoCaptureDelegateIfNeeded(id delegate);

@interface ImageSpoofingManager ()
@property (nonatomic, strong) NSUserDefaults *defaults;

- (NSURL *)imageDirectoryURL;
- (NSURL *)imageFileURL;
- (void)persistSelectedImage:(UIImage *)image;
- (nullable UIImage *)loadImageFromDisk;
@end

@interface AVCapturePhotoOutput (LSSpoofCapture)
- (void)ls_capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate;
@end

@implementation ImageSpoofingManager

+ (instancetype)sharedManager {
    static ImageSpoofingManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ sharedInstance = [[self alloc] initPrivate]; });
    return sharedInstance;
}

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        _defaults = [[NSUserDefaults alloc] initWithSuiteName:kLSImageToolSuiteName] ?: NSUserDefaults.standardUserDefaults;
        _referenceEnabled = [_defaults objectForKey:kLSReferenceEnabledKey] ? [_defaults boolForKey:kLSReferenceEnabledKey] : NO;
        _selectedImage = [self loadImageFromDisk];
    }
    return self;
}

// تشغيل الحقن فور تحميل الأداة داخل التطبيق
+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [self hookCaptureDelegateMethods];
        
        // سويزل capturePhotoWithSettings حتى نلحق أي delegate يتم إنشاؤه بعد تحميل الأداة
        Class outputClass = objc_getClass("AVCapturePhotoOutput");
        if (outputClass) {
            Method originalCapture = class_getInstanceMethod(outputClass, @selector(capturePhotoWithSettings:delegate:));
            Method swizzledCapture = class_getInstanceMethod(outputClass, @selector(ls_capturePhotoWithSettings:delegate:));
            if (originalCapture && swizzledCapture) {
                method_exchangeImplementations(originalCapture, swizzledCapture);
            }
        }

        // عمل سويزلينج لدالة جلب بيانات الصورة الأصلية لتعيد صورتنا المزيفة
        Class photoClass = objc_getClass("AVCapturePhoto");
        if (photoClass) {
            Method origMethod = class_getInstanceMethod(photoClass, @selector(fileDataRepresentation));
            Method swizMethod = class_getInstanceMethod(photoClass, @selector(ls_fileDataRepresentation));
            if (origMethod && swizMethod) {
                method_exchangeImplementations(origMethod, swizMethod);
            }
        }
    });
}

+ (void)hookCaptureDelegateMethods {
    int numClasses = objc_getClassList(NULL, 0);
    if (numClasses <= 0) { return; }

    Class *classes = (__unsafe_unretained Class *)malloc(sizeof(Class) * (NSUInteger)numClasses);
    if (!classes) { return; }

    numClasses = objc_getClassList(classes, numClasses);
    for (int i = 0; i < numClasses; i++) {
        LSHookCaptureDelegateClass(classes[i]);
    }

    free(classes);
}

#pragma mark - Public Methods

- (void)openPhotoLibraryFromViewController:(UIViewController *)viewController {
    if (!viewController) return;
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.delegate = self;
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.allowsEditing = NO;
    [viewController presentViewController:picker animated:YES completion:nil];
}

- (void)enableReference { self.referenceEnabled = YES; }
- (void)disableReference { self.referenceEnabled = NO; }

- (nullable UIImage *)getSelectedImage {
    if (!self.selectedImage) self.selectedImage = [self loadImageFromDisk];
    return self.selectedImage;
}

- (void)clearSelectedImage {
    self.selectedImage = nil;
    self.referenceEnabled = NO;
    [[NSFileManager defaultManager] removeItemAtURL:[self imageFileURL] error:nil];
}

#pragma mark - Internal Core Tools

- (NSURL *)imageDirectoryURL {
    NSURL *base = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    if (!base) base = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
    NSURL *folder = [base URLByAppendingPathComponent:@"XsGpSReference" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil];
    return folder;
}

- (NSURL *)imageFileURL {
    return [[self imageDirectoryURL] URLByAppendingPathComponent:kLSReferenceImageFileName];
}

- (void)persistSelectedImage:(UIImage *)image {
    if (!image) return;
    NSData *data = UIImageJPEGRepresentation(image, 0.92);
    if (data.length) [data writeToURL:[self imageFileURL] atomically:YES];
}

- (nullable UIImage *)loadImageFromDisk {
    return [UIImage imageWithContentsOfFile:[self imageFileURL].path];
}

- (void)setReferenceEnabled:(BOOL)referenceEnabled {
    _referenceEnabled = referenceEnabled;
    [self.defaults setBool:referenceEnabled forKey:kLSReferenceEnabledKey];
    [self.defaults synchronize];
}

#pragma mark - Tool UI Image Picker Delegate

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    if (image) {
        _selectedImage = image;
        [self persistSelectedImage:image];
        self.referenceEnabled = YES;
    }

    ImageCompletionHandler handler = self.completionHandler;
    [picker dismissViewControllerAnimated:YES completion:^{
        if (image && handler) handler(image);
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    self.completionHandler = nil;
    [picker dismissViewControllerAnimated:YES completion:nil];
}

@end

#pragma mark - Safe Camera Spoof Hooking (No Crash Zone)

static void LSHookCaptureDelegateClass(Class cls) {
    if (!cls) { return; }

    SEL originalSelector = @selector(captureOutput:didFinishProcessingPhoto:error:);
    SEL originalAliasSelector = NSSelectorFromString(@"ls_original_captureOutput:didFinishProcessingPhoto:error:");

    unsigned int methodCount = 0;
    Method *methodList = class_copyMethodList(cls, &methodCount);
    Method originalMethod = NULL;
    for (unsigned int methodIndex = 0; methodIndex < methodCount; methodIndex++) {
        Method candidate = methodList[methodIndex];
        if (method_getName(candidate) == originalSelector) {
            originalMethod = candidate;
            break;
        }
    }
    if (methodList) { free(methodList); }
    if (!originalMethod) { return; }

    IMP originalIMP = method_getImplementation(originalMethod);
    if (originalIMP == (IMP)LSCameraSpoofCaptureOutput) { return; }

    const char *typeEncoding = method_getTypeEncoding(originalMethod);
    Method aliasMethod = class_getInstanceMethod(cls, originalAliasSelector);
    if (!aliasMethod) {
        class_addMethod(cls, originalAliasSelector, originalIMP, typeEncoding);
    }
    if (!class_getInstanceMethod(cls, originalAliasSelector)) { return; }

    method_setImplementation(originalMethod, (IMP)LSCameraSpoofCaptureOutput);
}

static void LSHookPhotoCaptureDelegateIfNeeded(id delegate) {
    if (!delegate) { return; }
    for (Class cls = object_getClass(delegate); cls && cls != NSObject.class; cls = class_getSuperclass(cls)) {
        LSHookCaptureDelegateClass(cls);
    }
}

static void LSCameraSpoofCaptureOutput(id self, SEL _cmd, AVCapturePhotoOutput *output, AVCapturePhoto *photo, NSError *error) {
    ImageSpoofingManager *manager = [ImageSpoofingManager sharedManager];

    if (manager.referenceEnabled && [manager getSelectedImage] && photo) {
        UIImage *spoofedImage = [manager getSelectedImage];
        NSData *spoofedData = UIImageJPEGRepresentation(spoofedImage, 0.85);
        if (spoofedData) {
            objc_setAssociatedObject(photo, kLSSpoofedDataKey, spoofedData, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }

    SEL originalAliasSelector = NSSelectorFromString(@"ls_original_captureOutput:didFinishProcessingPhoto:error:");
    if ([self respondsToSelector:originalAliasSelector]) {
        ((void (*)(id, SEL, AVCapturePhotoOutput *, AVCapturePhoto *, NSError *))objc_msgSend)(self, originalAliasSelector, output, photo, error);
    }
}

#pragma mark - AVCapturePhoto Hooking

@interface AVCapturePhoto (LSSpoof)
@end

@implementation AVCapturePhoto (LSSpoof)

// 2. عندما يطلب تطبيق جودل بيانات الصورة، نقوم بإعطائه البيانات المزيفة المربوطة بالكائن
- (nullable NSData *)ls_fileDataRepresentation {
    NSData *spoofedData = objc_getAssociatedObject(self, kLSSpoofedDataKey);
    if (spoofedData) {
        return spoofedData; // تزييف البيانات المرجعة بنجاح!
    }
    return [self ls_fileDataRepresentation]; // إرجاع الصورة الأصلية إذا كان السويتش مغلقاً
}

@end

#pragma mark - AVCapturePhotoOutput Hooking

@implementation AVCapturePhotoOutput (LSSpoofCapture)

- (void)ls_capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
    LSHookPhotoCaptureDelegateIfNeeded(delegate);
    [self ls_capturePhotoWithSettings:settings delegate:delegate];
}

@end
