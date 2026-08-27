#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LSUUIDResetManager : NSObject

+ (void)clearHostApplicationDataPreservingToolState;
+ (void)restartAfterApplyingUUID;

@end

NS_ASSUME_NONNULL_END
