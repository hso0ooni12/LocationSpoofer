#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LSScheduleEditorViewController : UIViewController
@property (nonatomic, assign) CLLocationCoordinate2D selectedCoordinate;
@property (nonatomic, assign) BOOL hasSelectedCoordinate;
@property (nonatomic, copy, nullable) void (^onSaved)(void);
@end

NS_ASSUME_NONNULL_END
