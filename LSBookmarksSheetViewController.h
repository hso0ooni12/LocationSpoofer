#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>
#import "BookmarksManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface LSBookmarksSheetViewController : UIViewController

- (instancetype)initWithBookmarks:(NSArray<LSBookmark *> *)bookmarks;

@property (nonatomic, copy, nullable) void (^onPreviewCoordinate)(CLLocationCoordinate2D coordinate, NSString * _Nullable name);
@property (nonatomic, copy, nullable) void (^onApplyCoordinate)(CLLocationCoordinate2D coordinate, NSString * _Nullable name);
@property (nonatomic, copy, nullable) void (^onDeleteBookmarkAtIndex)(NSUInteger index);
@property (nonatomic, copy, nullable) void (^onRenameBookmarkAtIndex)(NSUInteger index, NSString *newName);

@end

NS_ASSUME_NONNULL_END
