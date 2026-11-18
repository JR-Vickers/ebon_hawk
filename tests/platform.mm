#import "../native/src/session.h"
#include "../native/src/input_ledger.hpp"
#include <cassert>
#include <cstdio>
int main() {
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
