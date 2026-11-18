#pragma once
#include <set>
#include <vector>

// Actual forwarded downs only. Draining is atomic under the session input mutex.
struct EHInputLedger {
    std::set<unsigned> keys, buttons;
    void key(unsigned code, bool down) { if (down) keys.insert(code); else keys.erase(code); }
    void button(unsigned code, bool down) { if (down) buttons.insert(code); else buttons.erase(code); }
    struct Releases { std::vector<unsigned> keys, buttons; };
    Releases drain() {
        Releases result{{keys.begin(), keys.end()}, {buttons.begin(), buttons.end()}};
        keys.clear(); buttons.clear();
        return result;
    }
};
