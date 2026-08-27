#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void(^ImageCompletionHandler)(UIImage *image);

// مـدير تزييف الصور: يقوم بحفظ الصورة واعتراض كاميرا النظام (UIImagePickerController) داخل التطبيقات المستهدفة.
@interface ImageSpoofingManager : NSObject <UIImagePickerControllerDelegate, UINavigationControllerDelegate>

+ (instancetype)sharedManager;
@property (nonatomic, strong, nullable) UIImage *selectedImage;
@property (nonatomic, assign, getter=isReferenceEnabled) BOOL referenceEnabled;
@property (nonatomic, copy, nullable) ImageCompletionHandler completionHandler;

- (void)openPhotoLibraryFromViewController:(UIViewController *)viewController;
- (void)enableReference;
- (void)disableReference;
- (nullable UIImage *)getSelectedImage;
- (void)clearSelectedImage;

@end

NS_ASSUME_NONNULL_END
