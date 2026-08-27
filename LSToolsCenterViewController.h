#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LSToolsCenterViewController : UIViewController
@property (nonatomic, assign) CLLocationCoordinate2D selectedCoordinate;
@property (nonatomic, assign) BOOL hasSelectedCoordinate;
@property (nonatomic, copy, nullable) void (^onStatusChanged)(void);
@property (nonatomic, copy, nullable) void (^onHideRequested)(void);
@end

NS_ASSUME_NONNULL_END
