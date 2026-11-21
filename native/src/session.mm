#import "session.h"
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#include "input_ledger.hpp"
#include "key_repeat.hpp"
#include "event_routing.hpp"
#include "window_identity.hpp"
#include <atomic>
#include <mutex>
#include <thread>
#include <cmath>
#include <vector>

// Optional WindowServer SPI. A normal CGDisplayHideCursor request loses
// effect when the captured application becomes frontmost.
extern "C" {
int _CGSDefaultConnection(void) __attribute__((weak_import));
CGError CGSCopyConnectionProperty(int, int, CFStringRef, CFTypeRef *) __attribute__((weak_import));
CGError CGSSetConnectionProperty(int, int, CFStringRef, CFTypeRef) __attribute__((weak_import));
AXError _AXUIElementGetWindow(AXUIElementRef, CGWindowID *) __attribute__((weak_import));
}
static CFStringRef backgroundCursorKey() { return CFSTR("SetsCursorInBackground"); }

static double now() { return NSProcessInfo.processInfo.systemUptime; }
static NSArray *rectArray(CGRect r) { return @[@(r.origin.x), @(r.origin.y), @(r.size.width), @(r.size.height)]; }
static bool nearRect(CGRect a, CGRect b) {
    return fabs(a.origin.x-b.origin.x)<2 && fabs(a.origin.y-b.origin.y)<2 &&
        fabs(a.size.width-b.size.width)<2 && fabs(a.size.height-b.size.height)<2;
}
static id axCopy(AXUIElementRef element, CFStringRef attribute) {
    CFTypeRef value = nullptr;
    if (AXUIElementCopyAttributeValue(element, attribute, &value) != kAXErrorSuccess) return nil;
    return CFBridgingRelease(value);
}
static bool axRect(AXUIElementRef element, CGRect &rect) {
    id pos = axCopy(element, kAXPositionAttribute), size = axCopy(element, kAXSizeAttribute);
    CGPoint p; CGSize s;
    if (!pos || !size || CFGetTypeID((__bridge CFTypeRef)pos)!=AXValueGetTypeID() ||
        CFGetTypeID((__bridge CFTypeRef)size)!=AXValueGetTypeID() ||
        !AXValueGetValue((__bridge AXValueRef)pos, (AXValueType)kAXValueCGPointType, &p) ||
        !AXValueGetValue((__bridge AXValueRef)size, (AXValueType)kAXValueCGSizeType, &s)) return false;
    rect = {p,s}; return true;
}

@interface EHEvent : NSObject
@property CGEventRef event;
@property uint64_t token;
@property uint64_t repeatPress;
@end
@implementation EHEvent
- (void)dealloc { if (_event) CFRelease(_event); }
@end

@interface EHSession () <SCStreamOutput, SCStreamDelegate> {
    SCStream *_stream;
    NSArray<SCWindow *> *_windows;
    SCWindow *_selected;
    AXUIElementRef _axApp, _axWindow;
    NSDictionary *_frame;
    NSString *_state, *_message;
    NSString *_releaseReason;
    std::atomic<NSUInteger> _generation;
    BOOL _refreshing;
    double _lastRefresh, _lastSample, _focusDeadline;
    std::atomic<bool> _active;
    std::atomic<double> _heartbeat;
    std::mutex _inputMutex;
    EHInputLedger _held;
    EHKeyRepeat _keyRepeat;
    double _repeatDelay, _repeatInterval;
    uint64_t _repeatGenerated, _repeatFallbackPosted, _repeatNativePosted;
    NSMutableArray<EHEvent *> *_queued;
    NSMutableDictionary<NSNumber *, EHEvent *> *_pending;
    uint64_t _token;
    uint64_t _pointerPosted, _pointerRejected, _pointerDirect;
    CGPoint _lastTarget;
    CGPoint _entryCursor;
    bool _restoreEntryCursor, _desktopCursorHidden;
    int _cursorConnection;
    bool _restoreCursorProperty;
    id _previousCursorProperty;
    CGSize _capturedSize;
    size_t _captureWidth, _captureHeight;
    double _captureScale, _captureContentScale;
    BOOL _focusMatch;
    std::atomic<bool> _interactionPending;
    double _interactionDeadline, _nextInteractionAttempt;
    NSWindow *_godotWindow;
    NSWindowLevel _previousLevel;
    BOOL _previousHides;
    NSWindowCollectionBehavior _previousBehavior;
    CFMachPortRef _tap, _clickObserver;
    NSString *_clickTrace[2];
    CGEventTimestamp _clickTime[2];
    bool _clickSeen[2];
    CFRunLoopRef _tapLoop;
    std::thread _tapThread;
    unsigned _releaseKey, _qualityWidth, _qualityFPS;
    pid_t _targetPID;
}
- (void)observeClick:(CGEventType)type event:(CGEventRef)event;
- (void)releaseInput:(NSString *)reason;
- (CGEventRef)handleType:(CGEventType)type event:(CGEventRef)event;
@end

static CGEventRef tapCallback(CGEventTapProxy, CGEventType type, CGEventRef event, void *context) {
    @autoreleasepool { return [(__bridge EHSession *)context handleType:type event:event]; }
}
static CGEventRef observeCallback(CGEventTapProxy, CGEventType type, CGEventRef event, void *context) {
    @autoreleasepool { [(__bridge EHSession *)context observeClick:type event:event]; }
    return event;
}
static void watchdog(CFRunLoopTimerRef, void *context) {
    EHSession *session = (__bridge EHSession *)context;
    // status heartbeat is checked in callback as well; timer drives it without input.
    [session handleType:kCGEventNull event:nullptr];
}

@implementation EHSession
- (instancetype)init {
    if ((self=[super init])) {
        _qualityWidth=1920; _qualityFPS=30; _windows=@[]; _state=@"unassigned"; _message=@"Choose a window with P near the console.";
        _releaseReason=@"";
        _queued=[NSMutableArray new]; _pending=[NSMutableDictionary new];
    }
    return self;
}
- (void)observeClick:(CGEventType)type event:(CGEventRef)event {
    if (type!=kCGEventLeftMouseDown && type!=kCGEventLeftMouseUp) return;
    if (!event || CGEventGetIntegerValueField(event,kCGEventSourceUserData)!=EH_EVENT_TAG) return;
    int phase=type==kCGEventLeftMouseUp;
    @synchronized(self) {
        if (_clickTime[phase] && CGEventGetTimestamp(event)==_clickTime[phase])
            _clickSeen[phase]=true;
    }
}
- (NSDictionary *)permissions {
    return @{@"capture": @(CGPreflightScreenCaptureAccess()), @"accessibility": @(AXIsProcessTrusted()),
             @"listen": @(CGPreflightListenEventAccess())};
}
- (void)requestPermissions {
    CGRequestScreenCaptureAccess();
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge NSString *)kAXTrustedCheckOptionPrompt:@YES});
    CGRequestListenEventAccess();
}
- (void)refreshWindows {
    if (_refreshing || !CGPreflightScreenCaptureAccess()) return;
    _refreshing=YES; _lastRefresh=now();
    NSUInteger generation=_generation;
    __weak EHSession *weakSelf=self;
    [SCShareableContent getShareableContentExcludingDesktopWindows:YES onScreenWindowsOnly:NO
        completionHandler:^(SCShareableContent *content, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            EHSession *s=weakSelf; if (!s) return;
            if (generation!=s->_generation) return;
            s->_refreshing=NO;
            if (error) { [s releaseInput:@"Window discovery failed"]; @synchronized(s) { s->_state=@"error"; s->_message=error.localizedDescription; } return; }
            NSMutableArray *eligible=[NSMutableArray new];
            SCWindow *current=nil;
            for (SCWindow *w in content.windows) {
                if (w.windowID==s->_selected.windowID) current=w;
                if (w.owningApplication && w.owningApplication.processID!=getpid() && w.frame.size.width>1 && w.frame.size.height>1)
                    [eligible addObject:w];
            }
            s->_windows=eligible;
            if (!s->_selected) return;
            if (s->_axWindow && [axCopy(s->_axWindow,kAXMinimizedAttribute) boolValue]) {
                [s releaseInput:@"Source minimized; restore it in macOS, then press E."];
                @synchronized(s) { s->_state=@"minimized"; s->_frame=nil; }
                return;
            }
            if (!current) {
                BOOL terminated=[NSRunningApplication runningApplicationWithProcessIdentifier:s->_targetPID]==nil;
                [s releaseInput:terminated ? @"Source application closed; reassign it." : @"Window unavailable: closed or not currently shared. Restore it or reassign it."];
                @synchronized(s) { s->_state=terminated ? @"closed" : @"unavailable"; s->_frame=nil; }
                return;
            }
            BOOL resized = fabs(current.frame.size.width-s->_selected.frame.size.width)>1 || fabs(current.frame.size.height-s->_selected.frame.size.height)>1;
            s->_selected=current;
            if (resized) {
                [s releaseInput:@"Source resized; waiting for a matching new frame. Press E to resume."];
                @synchronized(s) { s->_state=@"resizing"; s->_frame=nil; }
                SCStream *stream=s->_stream;
                [stream updateConfiguration:[s configuration:current] completionHandler:^(NSError *e) {
                    if (e) [s captureError:e stream:stream];
                }];
            }
        });
    }];
}
- (NSArray *)windows {
    NSMutableArray *result=[NSMutableArray new];
    for (SCWindow *w in _windows) {
        NSRunningApplication *app=[NSRunningApplication runningApplicationWithProcessIdentifier:w.owningApplication.processID];
        BOOL regular=app && app.activationPolicy==NSApplicationActivationPolicyRegular;
        NSString *title=[w.title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        // Off-Space windows are frequently reported off-screen in fullscreen mode.
        // Keep named windows from ordinary apps, including across Spaces.
        BOOL pickerEligible=regular && w.windowLayer==0 && w.frame.size.width>40 && w.frame.size.height>40 && (w.isOnScreen || title.length>0);
        [result addObject:@{@"id":@(w.windowID), @"pid":@(w.owningApplication.processID),
            @"app":w.owningApplication.applicationName ?: @"Application", @"bundle_id":w.owningApplication.bundleIdentifier ?: @"", @"title":w.title ?: @"Untitled",
            @"on_screen":@(w.isOnScreen), @"picker_eligible":@(pickerEligible)}];
    }
    return result;
}
- (NSData *)applicationIcon:(int)pid {
    NSRunningApplication *app=[NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    NSImage *icon=app.icon;
    if (!icon) return nil;
    NSBitmapImageRep *bitmap=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr
        pixelsWide:64 pixelsHigh:64 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
        isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    if (!bitmap) return nil;
    NSGraphicsContext *context=[NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    if (!context) return nil;
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:context];
    context.imageInterpolation=NSImageInterpolationHigh;
    [icon drawInRect:NSMakeRect(0,0,64,64) fromRect:NSZeroRect
        operation:NSCompositingOperationSourceOver fraction:1.0];
    [NSGraphicsContext restoreGraphicsState];
    return [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}
- (SCStreamConfiguration *)configuration:(SCWindow *)window {
    SCContentFilter *filter=[[SCContentFilter alloc] initWithDesktopIndependentWindow:window];
    // Choose source display scale, then cap width; metadata describes any downscale.
    double scale=filter.pointPixelScale;
    double width=window.frame.size.width*scale, height=window.frame.size.height*scale;
    double shrink=fmin(1.0,(double)_qualityWidth/fmax(width,height));
    SCStreamConfiguration *c=[SCStreamConfiguration new];
    c.width=MAX(2,lrint(width*shrink)); c.height=MAX(2,lrint(height*shrink));
    c.pixelFormat=kCVPixelFormatType_32BGRA; c.minimumFrameInterval=CMTimeMake(1,_qualityFPS);
    c.queueDepth=3; c.showsCursor=NO; c.capturesAudio=NO;
    c.ignoreShadowsSingleWindow=YES; c.scalesToFit=YES; c.preservesAspectRatio=YES;
    return c;
}
- (void)setQuality:(unsigned)width fps:(unsigned)fps {
    width=MAX(320u,MIN(width,1920u)); fps=MAX(1u,MIN(fps,30u));
    if (_qualityWidth==width && _qualityFPS==fps) return;
    _qualityWidth=width; _qualityFPS=fps;
    if (_stream && _selected) {
        SCStream *stream=_stream;
        [stream updateConfiguration:[self configuration:_selected] completionHandler:^(NSError *error) {
            if (error) [self captureError:error stream:stream];
        }];
    }
}
- (BOOL)selectWindow:(uint32_t)windowID {
    [self stop];
    for (SCWindow *w in _windows) if (w.windowID==windowID) { _selected=w; break; }
    if (!_selected || !CGPreflightScreenCaptureAccess()) return NO;
    _targetPID=_selected.owningApplication.processID;
    NSUInteger generation=++_generation;
    @synchronized(self) { _state=@"starting"; _message=@"Starting single-window capture…"; }
    SCContentFilter *filter=[[SCContentFilter alloc] initWithDesktopIndependentWindow:_selected];
    @synchronized(self) { _stream=[[SCStream alloc] initWithFilter:filter configuration:[self configuration:_selected] delegate:self]; }
    NSError *error=nil;
    if (![_stream addStreamOutput:self type:SCStreamOutputTypeScreen sampleHandlerQueue:dispatch_queue_create("ebon.capture",DISPATCH_QUEUE_SERIAL) error:&error]) {
        [self captureError:error stream:_stream]; return NO;
    }
    SCStream *stream=_stream;
    __weak EHSession *weakSelf=self;
    [_stream startCaptureWithCompletionHandler:^(NSError *e) {
        EHSession *s=weakSelf; if (!s) return;
        if (e && generation==s->_generation) [s captureError:e stream:stream];
    }];
    return YES;
}
- (void)captureError:(NSError *)error stream:(SCStream *)stream {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self captureError:error stream:stream]; });
        return;
    }
    @synchronized(self) {
        if (stream!=_stream) return;
        _state=@"error"; _message=error.localizedDescription ?: @"Capture failed"; _frame=nil;
    }
    [self releaseInput:@"Capture failed; input released."];
}
- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error { [self captureError:error stream:stream]; }
- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sample ofType:(SCStreamOutputType)type {
    @autoreleasepool {
        if (type!=SCStreamOutputTypeScreen || !CMSampleBufferIsValid(sample)) return;
        NSArray *attachments=(__bridge NSArray *)CMSampleBufferGetSampleAttachmentsArray(sample,false);
        NSDictionary *info=attachments.firstObject;
        if (!info) return;
        SCFrameStatus status=(SCFrameStatus)[info[SCStreamFrameInfoStatus] integerValue];
        if (status!=SCFrameStatusComplete) {
            @synchronized(self) {
                if (stream!=_stream) return;
                if (status==SCFrameStatusIdle) { _lastSample=now(); return; }
                _state=(status==SCFrameStatusSuspended || status==SCFrameStatusBlank) ? @"paused" : @"waiting";
                _interactionPending=false;
            }
            dispatch_async(dispatch_get_main_queue(), ^{ if (stream==self->_stream) [self releaseInput:@"Capture is paused or unavailable; input released. Restore or reselect the source."]; }); return;
        }
        CVPixelBufferRef buffer=CMSampleBufferGetImageBuffer(sample);
        if (!buffer) return;
        size_t width=CVPixelBufferGetWidth(buffer), height=CVPixelBufferGetHeight(buffer);
        CGRect content=CGRectZero;
        id rect=info[SCStreamFrameInfoContentRect];
        if (![rect isKindOfClass:NSDictionary.class] || !CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)rect,&content)) return;
        double scale=[info[SCStreamFrameInfoScaleFactor] doubleValue], contentScale=[info[SCStreamFrameInfoContentScale] doubleValue];
        // The SDK specifies contentRect in points in surface; convert once to pixels.
        CGRect pixels=CGRectMake(content.origin.x*scale,content.origin.y*scale,content.size.width*scale,content.size.height*scale);
        if (scale<=0 || contentScale<=0 || pixels.size.width<=0 || pixels.size.height<=0 ||
            pixels.origin.x<0 || pixels.origin.y<0 || CGRectGetMaxX(pixels)>width+1 || CGRectGetMaxY(pixels)>height+1) {
            @synchronized(self) { if (stream!=_stream) return; _state=@"invalid_metadata"; _frame=nil; _interactionPending=false; }
            dispatch_async(dispatch_get_main_queue(), ^{ if (stream==self->_stream) [self releaseInput:@"Invalid capture metadata; input disabled. Reselect the source."]; }); return;
        }
        if (CVPixelBufferLockBaseAddress(buffer,kCVPixelBufferLock_ReadOnly)!=kCVReturnSuccess) return;
        NSMutableData *rgba=[NSMutableData dataWithLength:width*height*4];
        const uint8_t *src=(const uint8_t *)CVPixelBufferGetBaseAddress(buffer);
        uint8_t *dst=(uint8_t *)rgba.mutableBytes; size_t stride=CVPixelBufferGetBytesPerRow(buffer);
        for (size_t y=0;y<height;++y) for (size_t x=0;x<width;++x) {
            const uint8_t *p=src+y*stride+x*4; uint8_t *q=dst+(y*width+x)*4;
            q[0]=p[2]; q[1]=p[1]; q[2]=p[0]; q[3]=255;
        }
        CVPixelBufferUnlockBaseAddress(buffer,kCVPixelBufferLock_ReadOnly);
        @synchronized(self) {
            if (stream!=_stream) return;
            _lastSample=now(); _state=@"live";
            if ([_message isEqualToString:@"Starting single-window capture…"]) _message=@"Capture live.";
            _capturedSize=CGSizeMake(content.size.width/contentScale,content.size.height/contentScale);
            _captureWidth=width; _captureHeight=height; _captureScale=scale; _captureContentScale=contentScale;
            _frame=@{@"width":@(width), @"height":@(height), @"rgba":rgba,
                @"content_pixels":rectArray(pixels), @"scale_factor":@(scale), @"content_scale":@(contentScale),
                @"timestamp":@(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample)))};
        }
    }
}
- (NSDictionary *)takeFrame { @synchronized(self) { NSDictionary *f=_frame; _frame=nil; return f ?: @{}; } }
- (BOOL)matchAXWindow {
    if (_axWindow) { CFRelease(_axWindow); _axWindow=nullptr; }
    if (_axApp) CFRelease(_axApp);
    _axApp=AXUIElementCreateApplication(_targetPID);
    AXUIElementSetMessagingTimeout(_axApp,0.15);
    NSMutableArray *windows=[NSMutableArray new];
    std::vector<CFTypeRef> identities;
    AXError errors[4]; NSUInteger counts[4]={0,0,0,0};
    CFStringRef attributes[]={kAXWindowsAttribute,kAXMainWindowAttribute,kAXFocusedWindowAttribute,kAXChildrenAttribute};
    for (int i=0;i<4;++i) {
        CFTypeRef value=nullptr;
        errors[i]=AXUIElementCopyAttributeValue(_axApp,attributes[i],&value);
        id raw=CFBridgingRelease(value);
        NSArray *items=[raw isKindOfClass:NSArray.class] ? raw : (raw ? @[raw] : @[]);
        for (id item in items) {
            if (CFGetTypeID((__bridge CFTypeRef)item)!=AXUIElementGetTypeID()) continue;
            if (i==3 && ![axCopy((__bridge AXUIElementRef)item,kAXRoleAttribute) isEqualToString:(__bridge NSString *)kAXWindowRole]) continue;
            ++counts[i];
            CFTypeRef identity=(__bridge CFTypeRef)item;
            if (!ehContainsIdentity(identities,identity,[](CFTypeRef a, CFTypeRef b) { return CFEqual(a,b); })) {
                [windows addObject:item]; identities.push_back(identity);
            }
        }
    }
    NSMutableArray *idMatches=[NSMutableArray new], *geometryMatches=[NSMutableArray new];
    NSUInteger readableIDs=0, readableBounds=0;
    for (id item in windows) {
        if (CFGetTypeID((__bridge CFTypeRef)item)!=AXUIElementGetTypeID()) continue;
        AXUIElementRef w=(__bridge AXUIElementRef)item;
        CGWindowID windowID=0;
        if (_AXUIElementGetWindow && _AXUIElementGetWindow(w,&windowID)==kAXErrorSuccess && windowID) {
            ++readableIDs;
            if (windowID==_selected.windowID) [idMatches addObject:item];
            continue;
        }
        CGRect bounds;
        if (axRect(w,bounds)) {
            ++readableBounds;
            if (_selected.title.length && nearRect(bounds,_selected.frame) &&
                [axCopy(w,kAXTitleAttribute) isEqualToString:_selected.title])
                [geometryMatches addObject:item];
        }
    }
    // A successful window ID is definitive; never substitute a different ID
    // even if it happens to share the captured window's title and geometry.
    EHWindowChoice choice=ehWindowChoice(idMatches.count,geometryMatches.count);
    NSArray *matches=choice==EHWindowChoice::exact_id ? idMatches : geometryMatches;
    NSLog(@"Ebon Hawk AX discovery: errors=%d,%d,%d,%d counts=%lu,%lu,%lu,%lu unique=%lu readable_ids=%lu readable_bounds=%lu id_matches=%lu fallback_matches=%lu",
        (int)errors[0],(int)errors[1],(int)errors[2],(int)errors[3],
        (unsigned long)counts[0],(unsigned long)counts[1],(unsigned long)counts[2],(unsigned long)counts[3],
        (unsigned long)windows.count,(unsigned long)readableIDs,(unsigned long)readableBounds,
        (unsigned long)idMatches.count,(unsigned long)geometryMatches.count);
    if (choice==EHWindowChoice::none) {
        return NO;
    }
    _axWindow=(AXUIElementRef)CFRetain((__bridge CFTypeRef)matches.firstObject);
    return YES;
}
- (BOOL)targetFocused {
    if (!_axWindow || !AXIsProcessTrusted() || NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier!=_targetPID) { _focusMatch=NO; return NO; }
    id focused=axCopy(_axApp,kAXFocusedWindowAttribute);
    _focusMatch=focused && CFEqual((__bridge CFTypeRef)focused,_axWindow) && ![axCopy(_axWindow,kAXMinimizedAttribute) boolValue];
    return _focusMatch;
}
- (BOOL)beginInteraction:(uint64_t)nativeWindow releaseKey:(unsigned)key {
    [self endInteraction];
    NSDictionary *p=[self permissions];
    if (![p[@"capture"] boolValue] || ![p[@"accessibility"] boolValue] || ![p[@"listen"] boolValue]) {
        @synchronized(self) { _message=@"Grant Screen Recording, Accessibility, and Input Monitoring to Godot, then restart it."; } return NO;
    }
    @synchronized(self) { if (![_state isEqual:@"live"]) { _message=@"Wait for a live frame before interacting."; return NO; } }
    _godotWindow=(__bridge NSWindow *)(void *)nativeWindow;
    if (!_godotWindow || ![NSApp.windows containsObject:_godotWindow]) { _godotWindow=nil; @synchronized(self) { _message=@"No standalone Godot NSWindow. Launch with tools/dev.py run (not embedded editor play)."; } return NO; }
    _releaseKey=(key==111 ? 111 : 62);
    _pointerPosted=0; _pointerRejected=0; _pointerDirect=0;
    _previousLevel=_godotWindow.level; _previousHides=_godotWindow.hidesOnDeactivate;
    _previousBehavior=_godotWindow.collectionBehavior;
    _godotWindow.collectionBehavior=(_previousBehavior & ~NSWindowCollectionBehaviorMoveToActiveSpace) |
        NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    _godotWindow.level=NSFloatingWindowLevel; _godotWindow.hidesOnDeactivate=NO;
    [_godotWindow orderFrontRegardless];
    _interactionPending=YES; _interactionDeadline=now()+4.0; _nextInteractionAttempt=now()+0.2;
    [self matchAXWindow]; // Record the pre-activation discovery for comparison.
    [[NSRunningApplication runningApplicationWithProcessIdentifier:_targetPID] activateWithOptions:0];
    @synchronized(self) { _message=@"Finding and focusing the selected window…"; }
    return YES;
}
- (void)advanceInteraction {
    if (!_interactionPending) return;
    BOOL live; @synchronized(self) { live=[_state isEqual:@"live"]; }
    if (!live || !CGPreflightScreenCaptureAccess() || !CGPreflightListenEventAccess() || !AXIsProcessTrusted()) {
        @synchronized(self) { _message=@"Capture or required permission became unavailable. Restore the source and permissions, then retry."; }
        [self endInteraction]; return;
    }
    if (now()>=_interactionDeadline) {
        @synchronized(self) { _message=@"Could not find and focus the selected window. Restore it, check Accessibility permission, and retry."; }
        [self endInteraction]; return;
    }
    if (now()<_nextInteractionAttempt) return;
    _nextInteractionAttempt=now()+0.2;
    if (![self matchAXWindow]) return;
    AXUIElementPerformAction(_axWindow,kAXRaiseAction);
    AXUIElementSetAttributeValue(_axWindow,kAXMainAttribute,kCFBooleanTrue);
    AXUIElementSetAttributeValue(_axApp,kAXFocusedWindowAttribute,_axWindow);
    if (![self targetFocused] || !_interactionPending) return;
    [self acquireInput];
}
- (BOOL)acquireInput {
    _heartbeat=now(); _focusDeadline=now()+1.5;
    CGEventMask mask=CGEventMaskBit(kCGEventKeyDown)|CGEventMaskBit(kCGEventKeyUp)|CGEventMaskBit(kCGEventFlagsChanged)|
        CGEventMaskBit(kCGEventLeftMouseDown)|CGEventMaskBit(kCGEventLeftMouseUp)|CGEventMaskBit(kCGEventRightMouseDown)|CGEventMaskBit(kCGEventRightMouseUp)|
        CGEventMaskBit(kCGEventOtherMouseDown)|CGEventMaskBit(kCGEventOtherMouseUp)|CGEventMaskBit(kCGEventMouseMoved)|
        CGEventMaskBit(kCGEventLeftMouseDragged)|CGEventMaskBit(kCGEventRightMouseDragged)|CGEventMaskBit(kCGEventOtherMouseDragged)|CGEventMaskBit(kCGEventScrollWheel);
    _tap=CGEventTapCreate(kCGSessionEventTap,kCGHeadInsertEventTap,kCGEventTapOptionDefault,mask,tapCallback,(__bridge void *)self);
    if (!_tap) { @synchronized(self) { _message=@"Cannot create input event tap. Check Accessibility/Input Monitoring, restart Godot, and retry."; } [self endInteraction]; return NO; }
    // Start the desktop cursor at the console's initial aim point once.
    // Subsequent events already carry target-space Quartz coordinates.
    CGEventRef cursor=CGEventCreate(nullptr);
    if (cursor) {
        _entryCursor=CGEventGetLocation(cursor);
        CFRelease(cursor);
        CGRect bounds=_selected.frame;
        _restoreEntryCursor=CGWarpMouseCursorPosition(CGPointMake(CGRectGetMidX(bounds),
            CGRectGetMidY(bounds)))==kCGErrorSuccess;
    }
    if (_CGSDefaultConnection && CGSCopyConnectionProperty && CGSSetConnectionProperty) {
        _cursorConnection=_CGSDefaultConnection();
        CFTypeRef previous=nullptr;
        CGSCopyConnectionProperty(_cursorConnection,_cursorConnection,backgroundCursorKey(),&previous);
        _previousCursorProperty=CFBridgingRelease(previous);
        _restoreCursorProperty=CGSSetConnectionProperty(_cursorConnection,_cursorConnection,
            backgroundCursorKey(),kCFBooleanTrue)==kCGErrorSuccess;
    }
    _desktopCursorHidden=CGDisplayHideCursor(CGMainDisplayID())==kCGErrorSuccess;
    for (int i=0;i<2;++i) { _clickTrace[i]=nil; _clickSeen[i]=false; }
    CGEventMask clicks=CGEventMaskBit(kCGEventLeftMouseDown)|CGEventMaskBit(kCGEventLeftMouseUp);
    _clickObserver=CGEventTapCreate(kCGAnnotatedSessionEventTap,kCGTailAppendEventTap,
        kCGEventTapOptionListenOnly,clicks,observeCallback,(__bridge void *)self);
    _repeatGenerated=_repeatFallbackPosted=_repeatNativePosted=0;
    _repeatDelay=NSEvent.keyRepeatDelay;
    _repeatInterval=NSEvent.keyRepeatInterval;
    BOOL activate;
    @synchronized(self) {
        activate=_interactionPending && [_state isEqual:@"live"] && CGPreflightScreenCaptureAccess() && CGPreflightListenEventAccess() && AXIsProcessTrusted();
        _interactionPending=NO;
        if (activate) _active=true;
    }
    if (!activate) { [self endInteraction]; return NO; }
    _tapThread=std::thread([self] {
        @autoreleasepool {
            CFRunLoopRef loop=CFRunLoopGetCurrent(); CFRetain(loop);
            { std::lock_guard<std::mutex> lock(_inputMutex); _tapLoop=loop; }
            CFRunLoopSourceRef source=CFMachPortCreateRunLoopSource(kCFAllocatorDefault,_tap,0);
            CFRunLoopAddSource(loop,source,kCFRunLoopCommonModes);
            CFRunLoopSourceRef observerSource=_clickObserver ?
                CFMachPortCreateRunLoopSource(kCFAllocatorDefault,_clickObserver,0) : nullptr;
            if (observerSource) CFRunLoopAddSource(loop,observerSource,kCFRunLoopCommonModes);
            CFRunLoopTimerContext context={0,(__bridge void *)self,nullptr,nullptr,nullptr};
            CFRunLoopTimerRef timer=CFRunLoopTimerCreate(nullptr,CFAbsoluteTimeGetCurrent()+0.25,0.25,0,0,watchdog,&context);
            CFRunLoopAddTimer(loop,timer,kCFRunLoopCommonModes);
            if (_active) CFRunLoopRun();
            CFRunLoopTimerInvalidate(timer); CFRelease(timer);
            if (observerSource) { CFRunLoopSourceInvalidate(observerSource); CFRelease(observerSource); }
            CFRunLoopSourceInvalidate(source); CFRelease(source);
            { std::lock_guard<std::mutex> lock(_inputMutex); _tapLoop=nullptr; }
            CFRelease(loop);
        }
    });
    @synchronized(self) { _message=@"Input prototype active. Right Control / Escape releases; Cmd+Q quits Godot."; }
    return YES;
}
- (void)releaseInput:(NSString *)reason {
    _interactionPending=false;
    _active=false;
    std::lock_guard<std::mutex> lock(_inputMutex);
    if (_restoreEntryCursor) {
        CGWarpMouseCursorPosition(_entryCursor);
        _restoreEntryCursor=false;
    }
    if (_desktopCursorHidden) {
        CGDisplayShowCursor(CGMainDisplayID());
        _desktopCursorHidden=false;
    }
    if (_restoreCursorProperty) {
        CFTypeRef previous=_previousCursorProperty ? (__bridge CFTypeRef)_previousCursorProperty : kCFBooleanFalse;
        CGSSetConnectionProperty(_cursorConnection,_cursorConnection,backgroundCursorKey(),previous);
        _restoreCursorProperty=false;
    }
    _previousCursorProperty=nil;
    _keyRepeat.clear();
    auto releases=_held.drain();
    for (unsigned key:releases.keys) {
        CGEventRef e=CGEventCreateKeyboardEvent(nullptr,(CGKeyCode)key,false);
        if (key==54 || key==55 || key==56 || key==60 || key==58 || key==61 || key==59 || key==62 || key==63)
            CGEventSetType(e,kCGEventFlagsChanged);
        CGEventSetFlags(e,0); ehMarkTargetProcess(e,_targetPID);
        CGEventPostToPid(_targetPID,e); CFRelease(e);
    }
    for (unsigned button:releases.buttons) {
        CGEventType type=button==0?kCGEventLeftMouseUp:(button==1?kCGEventRightMouseUp:kCGEventOtherMouseUp);
        CGEventRef e=CGEventCreateMouseEvent(nullptr,type,_lastTarget,(CGMouseButton)button);
        CGEventSetFlags(e,0); ehMarkTargetProcess(e,_targetPID);
        CGEventPostToPid(_targetPID,e); CFRelease(e);
    }
    [_queued removeAllObjects]; [_pending removeAllObjects];
    @synchronized(self) { _message=reason; _releaseReason=reason ?: @""; }
}
- (void)endInteraction {
    _interactionPending=NO;
    NSString *reason;
    @synchronized(self) { reason=_active ? @"Input released. E to interact; P to change source." : _message; }
    [self releaseInput:reason];
    CFRunLoopRef loop=nullptr;
    { std::lock_guard<std::mutex> lock(_inputMutex); if (_tapLoop) { loop=_tapLoop; CFRetain(loop); } }
    if (loop) {
        // Scheduling, rather than stopping before CFRunLoopRun starts, avoids a startup/join race.
        CFRunLoopPerformBlock(loop,kCFRunLoopCommonModes,^{ CFRunLoopStop(loop); });
        CFRunLoopWakeUp(loop); CFRelease(loop);
    }
    if (_tapThread.joinable()) _tapThread.join();
    if (_clickObserver) { CFMachPortInvalidate(_clickObserver); CFRelease(_clickObserver); _clickObserver=nullptr; }
    if (_tap) { CFMachPortInvalidate(_tap); CFRelease(_tap); _tap=nullptr; }
    if (_godotWindow) {
        _godotWindow.level=_previousLevel; _godotWindow.hidesOnDeactivate=_previousHides;
        _godotWindow.collectionBehavior=_previousBehavior;
        _godotWindow=nil;
        [NSApp activateIgnoringOtherApps:YES];
    }
}
- (CGEventRef)handleType:(CGEventType)type event:(CGEventRef)event {
    if (event && CGEventGetIntegerValueField(event,kCGEventSourceUserData)==EH_EVENT_TAG) return event;
    if (!_active) return event;
    if (type==kCGEventTapDisabledByTimeout || type==kCGEventTapDisabledByUserInput || now()-_heartbeat.load()>1.5) {
        [self releaseInput:@"Input tap disabled or Godot stalled; held input released."]; return event;
    }
    if (!event) return event;
    unsigned code=(unsigned)CGEventGetIntegerValueField(event,kCGKeyboardEventKeycode);
    BOOL keyboard=type==kCGEventKeyDown || type==kCGEventKeyUp || type==kCGEventFlagsChanged;
    // Own the complete Escape gesture before returning focus to Godot.
    // Otherwise macOS can deliver the remainder of the press to navigation.
    if (keyboard && code==53) {
        if (type==kCGEventKeyUp) [self releaseInput:@"Escape released; input released."];
        return nullptr;
    }
    if (keyboard && code==_releaseKey) {
        [self releaseInput:@"Reserved release key; input released."]; return nullptr;
    }
    if (keyboard && (CGEventGetFlags(event)&kCGEventFlagMaskCommand) && (code==48 || code==12)) {
        [self releaseInput:code==12?@"quit requested":@"Application switch; input released."];
        return code==12?nullptr:event;
    }
    std::lock_guard<std::mutex> lock(_inputMutex);
    if (!_active) return event;
    if (_queued.count>=256) { // Do not run cleanup under this mutex.
        _heartbeat=0; return nullptr;
    }
    EHEvent *item=[EHEvent new]; item.event=CGEventCreateCopy(event); item.token=++_token;
    _keyRepeat.observe(type,event,item.token,now(),_repeatDelay);
    [_queued addObject:item];
    return nullptr;
}
- (NSArray *)pollInput {
    NSMutableArray *result=[NSMutableArray new];
    std::lock_guard<std::mutex> lock(_inputMutex);
    [_pending removeAllObjects];
    double time=now();
    CGEventRef repeat=_keyRepeat.copyDue(time,_repeatInterval,(CGEventTimestamp)(time*1e9));
    if (repeat) {
        ++_repeatGenerated;
        EHEvent *item=[EHEvent new];
        item.event=repeat; item.token=++_token; item.repeatPress=_keyRepeat.pressToken();
        [_queued addObject:item];
    }
    for (EHEvent *item in _queued) {
        CGEventType type=CGEventGetType(item.event);
        BOOL key=type==kCGEventKeyDown || type==kCGEventKeyUp || type==kCGEventFlagsChanged;
        CGPoint point=CGEventGetLocation(item.event);
        [_pending setObject:item forKey:@(item.token)];
        [result addObject:@{@"id":@(item.token),@"key":@(key),@"x":@(point.x),@"y":@(point.y)}];
    }
    [_queued removeAllObjects];
    return result;
}
- (BOOL)forwardEvent:(uint64_t)eventID x:(double)x y:(double)y {
    if (!_active || ![self targetFocused]) { [self releaseInput:@"Target focus changed or permission lost; input refused."]; return NO; }
    CGRect bounds;
    if (!axRect(_axWindow,bounds) || !nearRect(bounds,_selected.frame)) { [self releaseInput:@"Window geometry changed; wait for capture refresh and press E."]; return NO; }
    BOOL matchingFrame;
    @synchronized(self) { matchingFrame=fabs(_capturedSize.width-bounds.size.width)<2 && fabs(_capturedSize.height-bounds.size.height)<2 && [_state isEqual:@"live"]; }
    if (!matchingFrame) { [self releaseInput:@"Capture and target geometry disagree; wait for a new frame and retry."]; return NO; }
    std::lock_guard<std::mutex> lock(_inputMutex);
    EHEvent *item=_pending[@(eventID)]; [_pending removeObjectForKey:@(eventID)];
    if (!_active || !item) return NO;
    // A physical release or a new press can arrive between poll and forward.
    if (item.repeatPress && item.repeatPress!=_keyRepeat.pressToken()) return NO;
    CGEventRef e=item.event; CGEventType type=CGEventGetType(e);
    bool keyboard=type==kCGEventKeyDown || type==kCGEventKeyUp || type==kCGEventFlagsChanged;
    bool pidDelivery=keyboard;
    bool repeating=type==kCGEventKeyDown && CGEventGetIntegerValueField(e,kCGKeyboardEventAutorepeat);
    if (!keyboard) {
        unsigned button=(unsigned)CGEventGetIntegerValueField(e,kCGMouseEventButtonNumber);
        bool up=type==kCGEventLeftMouseUp || type==kCGEventRightMouseUp || type==kCGEventOtherMouseUp;
        bool drag=type==kCGEventLeftMouseDragged || type==kCGEventRightMouseDragged || type==kCGEventOtherMouseDragged;
        bool held=_held.buttons.count(button)!=0;
        bool inside=std::isfinite(x) && std::isfinite(y) && CGRectContainsPoint(bounds,CGPointMake(x,y));
        bool unmatched=(up || drag) && !held;
        if (unmatched || (!inside && !(up && held))) {
            ++_pointerRejected;
            if (type==kCGEventLeftMouseDown || type==kCGEventLeftMouseUp) {
                @synchronized(self) {
                    if (!up) _clickTrace[1]=nil;
                    _clickTime[up]=0;
                    _clickSeen[up]=false;
                    _clickTrace[up]=[NSString stringWithFormat:@"%@ #%llu rejected (%@)",
                        up ? @"Up" : @"Down",eventID,unmatched ? @"no held button" : @"outside content"];
                }
            }
            return NO;
        }
        CGPoint destination=inside ? CGPointMake(x,y) : _lastTarget;
        NSPoint screenPoint=NSMakePoint(destination.x,CGDisplayBounds(CGMainDisplayID()).size.height-destination.y);
        NSInteger hit=[NSWindow windowNumberAtPoint:screenPoint belowWindowWithWindowNumber:0];
        bool overlayHit=hit==_godotWindow.windowNumber;
        if (overlayHit) {
            // The frontmost hit can still name our floating overlay. Only
            // look beneath it when this session owns mouse passthrough.
            if (_godotWindow.ignoresMouseEvents)
                hit=[NSWindow windowNumberAtPoint:screenPoint belowWindowWithWindowNumber:_godotWindow.windowNumber];
        }
        if (!inside || hit!=_selected.windowID) {
            // Desktop routing could hit another window. Deliver the mapped
            // event directly to the already verified target process instead.
            pidDelivery=true;
            ++_pointerDirect;
        }
        if (type==kCGEventLeftMouseDown || type==kCGEventLeftMouseUp) {
            NSString *owner=hit==0 ? @"none" : @"unknown";
            if (hit==_godotWindow.windowNumber) owner=@"Godot";
            else for (SCWindow *window in _windows) {
                if (window.windowID==hit) { owner=window.owningApplication.applicationName ?: owner; break; }
            }
            @synchronized(self) {
                if (!up) _clickTrace[1]=nil;
                _clickTime[up]=CGEventGetTimestamp(e);
                _clickSeen[up]=false;
                _clickTrace[up]=[NSString stringWithFormat:@"%@ #%llu %@ | %@ %ld (%@), selected %u | (%.0f, %.0f)",
                    up ? @"Up" : @"Down",eventID,pidDelivery ? @"direct" : @"session",
                    overlayHit ? @"beneath Godot" : @"hit",(long)hit,owner,_selected.windowID,destination.x,destination.y];
            }
        }
        _lastTarget=destination;
        if (!inside) CGEventSetLocation(e,_lastTarget);
        // The original physical event pointed at Godot; never retain its hit-window IDs.
        CGEventSetIntegerValueField(e,kCGMouseEventWindowUnderMousePointer,_selected.windowID);
        CGEventSetIntegerValueField(e,kCGMouseEventWindowUnderMousePointerThatCanHandleThisEvent,_selected.windowID);
        if (type==kCGEventLeftMouseDown || type==kCGEventRightMouseDown || type==kCGEventOtherMouseDown) _held.button(button,true);
        if (type==kCGEventLeftMouseUp || type==kCGEventRightMouseUp || type==kCGEventOtherMouseUp) _held.button(button,false);
    } else {
        unsigned code=(unsigned)CGEventGetIntegerValueField(e,kCGKeyboardEventKeycode);
        if ((type==kCGEventKeyUp || repeating) && !_held.keys.count(code)) return NO;
        if (type!=kCGEventFlagsChanged) _held.key(code,type==kCGEventKeyDown);
        else if (code!=57) _held.key(code,CGEventSourceKeyState(kCGEventSourceStateHIDSystemState,(CGKeyCode)code));
    }
    // Snapshot modifier flags too: a modifier may already be held at entry.
    CGEventFlags flags=CGEventGetFlags(e);
    for (auto pair : {std::pair<unsigned,CGEventFlags>{55,kCGEventFlagMaskCommand}, {56,kCGEventFlagMaskShift},
                     {58,kCGEventFlagMaskAlternate}, {59,kCGEventFlagMaskControl}, {63,kCGEventFlagMaskSecondaryFn}})
        _held.key(pair.first,(flags & pair.second)!=0);
    ehMarkTargetProcess(e,_targetPID);
    if (!keyboard) ++_pointerPosted;
    if (repeating) {
        unsigned code=(unsigned)CGEventGetIntegerValueField(e,kCGKeyboardEventKeycode);
        if (EHKeyRepeat::isEditingKey(code,flags)) {
            CGEventRef up=EHKeyRepeat::prepareEditingRepeat(e);
            if (up) {
                CGEventPostToPid(_targetPID,up);
                CFRelease(up);
            }
        }
        if (item.repeatPress) ++_repeatFallbackPosted;
        else ++_repeatNativePosted;
    }
    if (pidDelivery) {
        CGEventPostToPid(_targetPID,e);
    } else {
        CGEventPost(kCGSessionEventTap,e);
    }
    return YES;
}
- (NSDictionary *)status {
    _heartbeat=now();
    [self advanceInteraction];
    if (_selected && now()-_lastRefresh>1.0) [self refreshWindows];
    if (_active && now()>_focusDeadline && ![self targetFocused]) [self releaseInput:@"Focus changed; input released. Press P and choose a task window from this app, or retry E."];
    if (_active && !CGPreflightScreenCaptureAccess()) [self releaseInput:@"Screen Recording permission revoked."];
    @synchronized(self) {
        if (_selected && _lastSample>0 && now()-_lastSample>3 && [_state isEqual:@"live"]) {
            _state=@"unavailable"; // Release outside synchronized block to preserve lock order.
        }
    }
    BOOL unavailable; @synchronized(self) { unavailable=[_state isEqual:@"unavailable"] && _lastSample>0 && now()-_lastSample>3; }
    if (unavailable && _active) [self releaseInput:@"No recent capture; input released. Restore/reselect source."];
    @synchronized(self) {
        NSMutableArray *trace=[NSMutableArray new];
        for (int i=0;i<2;++i) {
            if (!_clickTrace[i]) continue;
            if (!_clickTime[i]) { [trace addObject:_clickTrace[i]]; continue; }
            NSString *observation=_clickSeen[i] ? @"seen" :
                (_clickObserver && CGEventTapIsEnabled(_clickObserver) ? @"unseen" : @"unavailable");
            [trace addObject:[NSString stringWithFormat:@"%@ | downstream %@",_clickTrace[i],observation]];
        }
        return @{@"click_trace":[trace componentsJoinedByString:@"\n"],@"state":_state,@"message":_message,@"interacting":@(_active.load()),@"interaction_pending":@(_interactionPending.load()),
            @"repeat_delay":@(_repeatDelay),@"repeat_interval":@(_repeatInterval),
            @"repeat_generated":@(_repeatGenerated),@"repeat_fallback_posted":@(_repeatFallbackPosted),
            @"repeat_native_posted":@(_repeatNativePosted),
            @"window_id":@(_selected.windowID),@"window_pid":@(_selected.owningApplication.processID),
            @"label":_selected ? [NSString stringWithFormat:@"%@ — %@",_selected.owningApplication.applicationName,_selected.title ?: @"Untitled"] : @"No source",
            @"window_rect":rectArray(_selected.frame),@"sample_age":@(_lastSample>0?now()-_lastSample:-1),
            @"focus_match":@(_focusMatch),@"capture_width":@(_captureWidth),@"capture_height":@(_captureHeight),
            @"capture_scale":@(_captureScale),@"capture_content_scale":@(_captureContentScale),@"release_reason":_releaseReason ?: @"",
            @"pointer_direct":@(_pointerDirect),@"pointer_posted":@(_pointerPosted),@"pointer_rejected":@(_pointerRejected)};
    }
}
- (void)stop {
    [self endInteraction]; ++_generation;
    _refreshing=NO;
    SCStream *stream; @synchronized(self) { stream=_stream; _stream=nil; _frame=nil; _state=@"unassigned"; _lastSample=0; _capturedSize=CGSizeZero; _captureWidth=0; _captureHeight=0; _captureScale=0; _captureContentScale=0; _focusMatch=NO; }
    [stream stopCaptureWithCompletionHandler:^(NSError *) {}];
    if (_axWindow) { CFRelease(_axWindow); _axWindow=nullptr; }
    if (_axApp) { CFRelease(_axApp); _axApp=nullptr; }
    _selected=nil;
}
- (void)dealloc {
    // Bridge destructor calls stop on the main thread before releasing this object.
    if (_axWindow) CFRelease(_axWindow);
    if (_axApp) CFRelease(_axApp);
}
@end
