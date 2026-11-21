#import "../native/src/session.h"
#include "../native/src/event_routing.hpp"
#include "../native/src/input_ledger.hpp"
#include "../native/src/key_repeat.hpp"
#include "../native/src/window_identity.hpp"
#include <cassert>
#include <cstdio>
#include <vector>
int main() {
    std::vector<int> candidates{10, 20};
    assert(ehContainsIdentity(candidates, 10, [](int a, int b) { return a==b; }));
    assert(!ehContainsIdentity(candidates, 30, [](int a, int b) { return a==b; }));
    assert(ehWindowChoice(1, 0)==EHWindowChoice::exact_id);
    assert(ehWindowChoice(1, 2)==EHWindowChoice::exact_id);
    assert(ehWindowChoice(0, 1)==EHWindowChoice::fallback);
    assert(ehWindowChoice(0, 0)==EHWindowChoice::none);
    assert(ehWindowChoice(0, 2)==EHWindowChoice::none);
    assert(ehWindowChoice(2, 1)==EHWindowChoice::none);
    CGEventRef routed = CGEventCreate(nullptr);
    assert(routed);
    ehMarkTargetProcess(routed, 4242);
    assert(CGEventGetIntegerValueField(routed, kCGEventTargetUnixProcessID) == 4242);
    CFRelease(routed);
    for (CGKeyCode code : {38, 51}) { // J and Backspace
        EHKeyRepeat repeat;
        CGEventRef down=CGEventCreateKeyboardEvent(nullptr,code,true);
        CGEventSetFlags(down,0);
        repeat.observe(kCGEventKeyDown,down,1,1.0,0.5);
        assert(!repeat.copyDue(1.4,0.1,10));
        CGEventRef echo=repeat.copyDue(1.5,0.1,11);
        assert(echo && CGEventGetIntegerValueField(echo,kCGKeyboardEventAutorepeat)==1);
        assert(CGEventGetIntegerValueField(echo,kCGKeyboardEventKeycode)==code);
        assert(!repeat.copyDue(1.51,0.1,12));
        repeat.observe(kCGEventKeyDown,echo,2,1.6,0.5);
        assert(!repeat.copyDue(2.0,0.1,13));
        repeat.observe(kCGEventKeyDown,down,3,2.0,0.5);
        repeat.observe(kCGEventKeyUp,down,4,2.1,0.5);
        assert(!repeat.pressToken() && !repeat.copyDue(3.0,0.1,14));
        repeat.observe(kCGEventKeyDown,down,5,4.0,0.0);
        assert(!repeat.copyDue(4.49,0.0,15));
        CGEventRef first=repeat.copyDue(4.5,0.0,16);
        assert(first && !repeat.copyDue(4.51,0.0,17));
        CGEventRef second=repeat.copyDue(4.54,0.0,18);
        assert(second);
        CFRelease(first); CFRelease(second);
        repeat.clear();
        assert(!repeat.copyDue(5.0,0.0,19));
        CGEventSetFlags(down,kCGEventFlagMaskCommand);
        repeat.observe(kCGEventKeyDown,down,5,3.0,0.5);
        assert(!repeat.copyDue(4.0,0.1,15));
        CGEventRef up=EHKeyRepeat::prepareEditingRepeat(echo);
        assert(up && CGEventGetType(up)==kCGEventKeyUp && CGEventGetType(echo)==kCGEventKeyDown);
        assert(CGEventGetIntegerValueField(up,kCGKeyboardEventKeycode)==code);
        assert(!CGEventGetIntegerValueField(up,kCGKeyboardEventAutorepeat));
        assert(!CGEventGetIntegerValueField(echo,kCGKeyboardEventAutorepeat));
        CFRelease(up); CFRelease(echo); CFRelease(down);
    }
    EHInputLedger state;
    state.key(56,true); state.key(0,true); state.key(0,true);
    state.button(0,true); state.button(1,true); state.button(1,false);
    auto releases=state.drain();
    assert(releases.keys.size()==2 && releases.buttons.size()==1 && releases.buttons[0]==0);
    assert(state.drain().keys.empty() && state.drain().buttons.empty());
    state.key(59,true); state.key(59,false); state.button(0,false);
    assert(state.drain().keys.empty() && state.drain().buttons.empty());
    @autoreleasepool {
        EHSession *session=[EHSession new];
        NSDictionary *permissions=[session permissions]; // Read-only; no permission requests.
        printf("Permission preflight (no prompt): capture=%d accessibility=%d listen=%d\n",
            [permissions[@"capture"] boolValue], [permissions[@"accessibility"] boolValue], [permissions[@"listen"] boolValue]);
        assert([session.status[@"state"] isEqual:@"unassigned"]);
        [session endInteraction]; [session endInteraction]; [session stop];
        assert(![session.status[@"interacting"] boolValue]);
    }
    std::puts("Platform link/session lifecycle and forwarded-input ledger: PASS");
}
