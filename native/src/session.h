#import <Foundation/Foundation.h>

// All public methods called from Godot's main thread. No Godot objects on native queues.
@interface EHSession : NSObject
- (NSDictionary *)permissions;
- (void)requestPermissions;
- (void)refreshWindows;
- (NSArray *)windows;
- (BOOL)selectWindow:(uint32_t)windowID;
- (NSDictionary *)status;
- (NSDictionary *)takeFrame;
- (BOOL)beginInteraction:(uint64_t)nativeWindow releaseKey:(unsigned)key;
- (void)endInteraction;
- (NSArray *)pollInput;
- (BOOL)forwardEvent:(uint64_t)eventID x:(double)x y:(double)y;
- (void)stop;
@end
