#import <AppKit/AppKit.h>

#include "../native/src/event_routing.hpp"

@interface EHFixtureWindow : NSWindow
@end

@implementation EHFixtureWindow
- (void)sendEvent:(NSEvent *)event {
    if (event.type == NSEventTypeLeftMouseDown && event.CGEvent) {
        CGEventRef raw = event.CGEvent;
        CGPoint quartz = CGEventGetLocation(raw);
        NSPoint screen = [self convertPointToScreen:event.locationInWindow];
        CGFloat primaryTop = NSMaxY(NSScreen.screens.firstObject.frame);
        BOOL forwarded = CGEventGetIntegerValueField(raw, kCGEventSourceUserData) == EH_EVENT_TAG;
        NSPoint live = [self mouseLocationOutsideOfEventStream];
        fprintf(stderr, "%s click window=%ld eventWindow=%ld local=(%.1f,%.1f) "
                "quartz=(%.1f,%.1f) appKitAsQuartz=(%.1f,%.1f) liveLocal=(%.1f,%.1f)\n",
                forwarded ? "tagged" : "untagged", (long)self.windowNumber,
                (long)event.windowNumber, event.locationInWindow.x, event.locationInWindow.y,
                quartz.x, quartz.y, screen.x, primaryTop - screen.y, live.x, live.y);
    }
    [super sendEvent:event];
}
@end

@class EHMouseFixtureView;

@interface EHFixtureTextView : NSTextView
@property(nonatomic,weak) EHMouseFixtureView *eventLog;
@end

@interface EHMouseFixtureView : NSView
@property(nonatomic) NSUInteger mouseDownCount;
@property(nonatomic) NSUInteger mouseUpCount;
@property(nonatomic) NSUInteger dragCount;
@property(nonatomic) NSUInteger rightClickCount;
@property(nonatomic) NSUInteger scrollCount;
@property(nonatomic) NSUInteger keyDownCount;
@property(nonatomic) NSUInteger firstMouseCheckCount;
@property(nonatomic) BOOL lastFirstMouseAccepted;
@property(nonatomic) NSUInteger buttonActionCount;
@property(nonatomic,strong) NSButton *button;
@property(nonatomic,weak) NSTextView *textView;
@property(nonatomic) NSUInteger textKeyDownCount;
@property(nonatomic) NSUInteger textFlagsChangedCount;
@property(nonatomic) NSUInteger commandCEquivalentCount;
@property(nonatomic) NSUInteger commandVEquivalentCount;
@property(nonatomic) NSUInteger commandCKeyDownCount;
@property(nonatomic) NSUInteger commandVKeyDownCount;
@property(nonatomic) NSUInteger copyActionCount;
@property(nonatomic) NSUInteger pasteActionCount;
@property(nonatomic) unsigned short lastTextKeyCode;
@property(nonatomic) BOOL lastTextCommandFlag;
@property(nonatomic) NSPoint lastPoint;
@property(nonatomic, copy) NSString *lastEvent;
- (void)recordTextEvent:(NSEvent *)event equivalent:(BOOL)equivalent;
- (void)recordTextFlagsChanged:(NSEvent *)event;
- (void)recordClipboardAction:(BOOL)copyAction;
@end

@implementation EHFixtureTextView
- (void)keyDown:(NSEvent *)event {
    [self.eventLog recordTextEvent:event equivalent:NO];
    [super keyDown:event];
}
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    [self.eventLog recordTextEvent:event equivalent:YES];
    return [super performKeyEquivalent:event];
}
- (void)flagsChanged:(NSEvent *)event {
    [self.eventLog recordTextFlagsChanged:event];
    [super flagsChanged:event];
}
- (void)copy:(id)sender {
    [self.eventLog recordClipboardAction:YES];
    [super copy:sender];
}
- (void)paste:(id)sender {
    [self.eventLog recordClipboardAction:NO];
    [super paste:sender];
}
@end

@implementation EHMouseFixtureView
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self=[super initWithFrame:frame])) {
        _button=[[NSButton alloc] initWithFrame:NSMakeRect(570,55,210,54)];
        _button.title=@"Click test button";
        _button.bezelStyle=NSBezelStyleRounded;
        _button.target=self;
        _button.action=@selector(fixtureButtonPressed:);
        [self addSubview:_button];

        NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(500,125,280,155)];
        scroll.hasVerticalScroller=YES;
        scroll.borderType=NSBezelBorder;
        EHFixtureTextView *textView=[[EHFixtureTextView alloc] initWithFrame:scroll.contentView.bounds];
        textView.eventLog=self;
        self.textView=textView;
        textView.minSize=NSMakeSize(0,0);
        textView.maxSize=NSMakeSize(CGFLOAT_MAX,CGFLOAT_MAX);
        textView.verticallyResizable=YES;
        textView.horizontallyResizable=NO;
        textView.autoresizingMask=NSViewWidthSizable;
        textView.editable=YES;
        textView.selectable=YES;
        textView.string=@"Select and copy this fixture text.\nTry clicking to move the caret, then drag-select.";
        scroll.documentView=textView;
        [self addSubview:scroll];
    }
    return self;
}
- (void)fixtureButtonPressed:(id)sender {
    (void)sender;
    ++_buttonActionCount;
    _button.title=[NSString stringWithFormat:@"Button clicked: %lu",(unsigned long)_buttonActionCount];
}
- (void)recordTextEvent:(NSEvent *)event equivalent:(BOOL)equivalent {
    unsigned short code=event.keyCode;
    BOOL command=(event.modifierFlags & NSEventModifierFlagCommand)!=0;
    _lastTextKeyCode=code;
    _lastTextCommandFlag=command;
    if (equivalent) {
        if (command && code==8) ++_commandCEquivalentCount;
        if (command && code==9) ++_commandVEquivalentCount;
    } else {
        ++_textKeyDownCount;
        if (command && code==8) ++_commandCKeyDownCount;
        if (command && code==9) ++_commandVKeyDownCount;
    }
    [self setNeedsDisplay:YES];
}
- (void)recordTextFlagsChanged:(NSEvent *)event {
    ++_textFlagsChangedCount;
    _lastTextCommandFlag=(event.modifierFlags & NSEventModifierFlagCommand)!=0;
    [self setNeedsDisplay:YES];
}
- (void)recordClipboardAction:(BOOL)copyAction {
    if (copyAction) ++_copyActionCount;
    else ++_pasteActionCount;
    [self setNeedsDisplay:YES];
}
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    BOOL accepted=[super acceptsFirstMouse:event];
    ++_firstMouseCheckCount;
    _lastFirstMouseAccepted=accepted;
    _lastEvent=accepted ? @"first mouse accepted by AppKit default" : @"first mouse rejected by AppKit default";
    [self setNeedsDisplay:YES];
    return accepted;
}
- (void)record:(NSString *)name event:(NSEvent *)event {
    _lastEvent=name;
    _lastPoint=[self convertPoint:event.locationInWindow fromView:nil];
    [self setNeedsDisplay:YES];
}
- (void)mouseDown:(NSEvent *)event { ++_mouseDownCount; [self record:@"left down" event:event]; }
- (void)mouseUp:(NSEvent *)event { ++_mouseUpCount; [self record:@"left up" event:event]; }
- (void)mouseDragged:(NSEvent *)event { ++_dragCount; [self record:@"left drag" event:event]; }
- (void)rightMouseDown:(NSEvent *)event { ++_rightClickCount; [self record:@"right down" event:event]; }
- (void)scrollWheel:(NSEvent *)event { ++_scrollCount; [self record:@"scroll" event:event]; }
- (void)keyDown:(NSEvent *)event {
    ++_keyDownCount;
    _lastEvent=@"key down (characters not recorded)";
    [self setNeedsDisplay:YES];
    (void)event;
}
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [[NSColor colorWithCalibratedRed:0.08 green:0.12 blue:0.18 alpha:1] setFill];
    NSRectFill(self.bounds);
    NSDictionary *titleAttrs=@{NSFontAttributeName:[NSFont boldSystemFontOfSize:28], NSForegroundColorAttributeName:NSColor.whiteColor};
    NSDictionary *bodyAttrs=@{NSFontAttributeName:[NSFont monospacedSystemFontOfSize:18 weight:NSFontWeightRegular], NSForegroundColorAttributeName:NSColor.whiteColor};
    [@"EBON HAWK POINTER EVENT FIXTURE" drawAtPoint:NSMakePoint(32,self.bounds.size.height-64) withAttributes:titleAttrs];
    NSString *instructions=@"Select this window in the console, press E, then try the button and text area at right.\nThese counters update only when AppKit receives the corresponding event.\nKey count is included as a comparison. No key text is stored.";
    [instructions drawAtPoint:NSMakePoint(32,self.bounds.size.height-132) withAttributes:bodyAttrs];
    NSString *counts=[NSString stringWithFormat:
        @"mouseDown: %lu\nmouseUp: %lu\nmouseDragged: %lu\nrightMouseDown: %lu\nscrollWheel: %lu\nkeyDown: %lu\nfirstMouse checks: %lu (last: %@)\napp active: %@ | window key: %@ | window main: %@\nbutton actions: %lu\ntext keyDown/flags: %lu / %lu\nCmd+C equivalents/keyDown: %lu / %lu\nCmd+V equivalents/keyDown: %lu / %lu\ncopy/paste actions: %lu / %lu\nlast text key: %u | Command flag: %@\ntext length/selection: %lu / %lu\nlast event: %@\nlast view point: %.1f, %.1f",
        (unsigned long)_mouseDownCount,(unsigned long)_mouseUpCount,(unsigned long)_dragCount,
        (unsigned long)_rightClickCount,(unsigned long)_scrollCount,(unsigned long)_keyDownCount,
        (unsigned long)_firstMouseCheckCount,_lastFirstMouseAccepted ? @"yes" : @"no",
        NSApp.isActive ? @"yes" : @"no",self.window.isKeyWindow ? @"yes" : @"no",
        self.window.isMainWindow ? @"yes" : @"no",(unsigned long)_buttonActionCount,
        (unsigned long)_textKeyDownCount,(unsigned long)_textFlagsChangedCount,
        (unsigned long)_commandCEquivalentCount,(unsigned long)_commandCKeyDownCount,
        (unsigned long)_commandVEquivalentCount,(unsigned long)_commandVKeyDownCount,
        (unsigned long)_copyActionCount,(unsigned long)_pasteActionCount,
        _lastTextKeyCode,_lastTextCommandFlag ? @"yes" : @"no",
        (unsigned long)_textView.string.length,(unsigned long)_textView.selectedRange.length,
        _lastEvent ?: @"none",_lastPoint.x,_lastPoint.y];
    [counts drawAtPoint:NSMakePoint(32,self.bounds.size.height-360) withAttributes:bodyAttrs];
    if (_mouseDownCount || _mouseUpCount || _dragCount || _rightClickCount) {
        [NSColor.systemOrangeColor setStroke];
        NSBezierPath *marker=[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(_lastPoint.x-12,_lastPoint.y-12,24,24)];
        marker.lineWidth=3;
        [marker moveToPoint:NSMakePoint(_lastPoint.x-20,_lastPoint.y)];
        [marker lineToPoint:NSMakePoint(_lastPoint.x+20,_lastPoint.y)];
        [marker moveToPoint:NSMakePoint(_lastPoint.x,_lastPoint.y-20)];
        [marker lineToPoint:NSMakePoint(_lastPoint.x,_lastPoint.y+20)];
        [marker stroke];
    }
}
@end

@interface EHMouseFixtureDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property(nonatomic,strong) NSWindow *window;
@property(nonatomic,strong) NSTimer *refreshTimer;
@end

@implementation EHMouseFixtureDelegate
- (void)installMenus {
    NSMenu *mainMenu=[[NSMenu alloc] initWithTitle:@"Main"];
    NSMenuItem *appItem=[[NSMenuItem alloc] initWithTitle:@"Ebon Hawk Mouse Fixture" action:nil keyEquivalent:@""];
    NSMenu *appMenu=[[NSMenu alloc] initWithTitle:@"Ebon Hawk Mouse Fixture"];
    [appMenu addItemWithTitle:@"Quit Ebon Hawk Mouse Fixture" action:@selector(terminate:) keyEquivalent:@"q"];
    [mainMenu addItem:appItem];
    [mainMenu setSubmenu:appMenu forItem:appItem];

    NSMenuItem *editItem=[[NSMenuItem alloc] initWithTitle:@"Edit" action:nil keyEquivalent:@""];
    NSMenu *editMenu=[[NSMenu alloc] initWithTitle:@"Edit"];
    for (NSArray *entry in @[
        @[@"Cut", NSStringFromSelector(@selector(cut:)), @"x"],
        @[@"Copy", NSStringFromSelector(@selector(copy:)), @"c"],
        @[@"Paste", NSStringFromSelector(@selector(paste:)), @"v"],
        @[@"Select All", NSStringFromSelector(@selector(selectAll:)), @"a"]
    ]) {
        NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:entry[0] action:NSSelectorFromString(entry[1]) keyEquivalent:entry[2]];
        item.keyEquivalentModifierMask=NSEventModifierFlagCommand;
        [editMenu addItem:item];
    }
    [mainMenu addItem:editItem];
    [mainMenu setSubmenu:editMenu forItem:editItem];
    NSApp.mainMenu=mainMenu;
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    [self installMenus];
    NSRect frame=NSMakeRect(240,180,820,520);
    self.window=[[EHFixtureWindow alloc] initWithContentRect:frame
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    self.window.title=@"Ebon Hawk Mouse Fixture";
    self.window.delegate=self;
    EHMouseFixtureView *view=[[EHMouseFixtureView alloc] initWithFrame:NSMakeRect(0,0,820,520)];
    self.window.contentView=view;
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    self.refreshTimer=[NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) {
        (void)timer;
        [view setNeedsDisplay:YES];
    }];
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return YES;
}
@end

int main() {
    @autoreleasepool {
        NSApplication *app=NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        EHMouseFixtureDelegate *delegate=[EHMouseFixtureDelegate new];
        app.delegate=delegate;
        [app run];
    }
    return 0;
}
