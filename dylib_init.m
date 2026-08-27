#import "XsGpS.h"
#import "PersistenceManager.h"
#import "OverlayWindow.h"
#import "LSActivationManager.h"

__attribute__((constructor(101)))
static void LSDylibInit(void) {
    [PersistenceManager loadEarly];
    [LSActivationManager loadEarly];
    [XsGpS installHooks];

    dispatch_async(dispatch_get_main_queue(), ^{
        [LSOverlayManager install];
    });
}
