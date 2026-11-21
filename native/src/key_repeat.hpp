#pragma once

#include <ApplicationServices/ApplicationServices.h>
#include <cmath>

// Called under the input mutex. Keep the original key-down for its layout,
// Unicode payload and flags. Yield to native repeat when the tap supplies it.
class EHKeyRepeat {
    CGEventRef press = nullptr;
    unsigned key = 0;
    double next = 0;
    uint64_t token = 0;

public:
    EHKeyRepeat() = default;
    EHKeyRepeat(const EHKeyRepeat &) = delete;
    EHKeyRepeat &operator=(const EHKeyRepeat &) = delete;
    ~EHKeyRepeat() { clear(); }

    void clear() {
        if (press) CFRelease(press);
        press = nullptr;
        token = 0;
    }

    static bool isEditingKey(unsigned code, CGEventFlags flags) {
        if (flags & (kCGEventFlagMaskCommand | kCGEventFlagMaskControl)) return false;
        return code <= 51 || (code >= 65 && code <= 92) || code == 117 || (code >= 123 && code <= 126);
    }

    // Close the previous press and turn the repeat into the next press.
    // The real key-up (or cleanup) will release that final press.
    static CGEventRef prepareEditingRepeat(CGEventRef down) {
        CGEventRef up = CGEventCreateCopy(down);
        if (!up) return nullptr;
        CGEventSetType(up, kCGEventKeyUp);
        CGEventSetIntegerValueField(up, kCGKeyboardEventAutorepeat, 0);
        CGEventSetIntegerValueField(down, kCGKeyboardEventAutorepeat, 0);
        return up;
    }

    void observe(CGEventType type, CGEventRef event, uint64_t id, double time, double delay) {
        if (type != kCGEventKeyDown && type != kCGEventKeyUp && type != kCGEventFlagsChanged) return;
        unsigned code = (unsigned)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
        if (type == kCGEventKeyUp && code != key) return;
        clear();
        if (type != kCGEventKeyDown || CGEventGetIntegerValueField(event, kCGKeyboardEventAutorepeat)) return;
        if (!isEditingKey(code, CGEventGetFlags(event))) return;
        // AppKit can return zero when it cannot supply timing values.
        if (delay == 0) delay = 0.5;
        if (delay < 0 || !std::isfinite(delay)) return;
        press = CGEventCreateCopy(event);
        key = code;
        token = id;
        next = time + delay;
    }

    uint64_t pressToken() const { return token; }

    CGEventRef copyDue(double time, double interval, CGEventTimestamp timestamp) {
        if (interval == 0) interval = 1.0 / 30.0;
        if (!press || time < next || interval < 0 || !std::isfinite(interval)) return nullptr;
        next = time + interval;
        CGEventRef event = CGEventCreateCopy(press);
        if (event) {
            CGEventSetTimestamp(event, timestamp);
            CGEventSetIntegerValueField(event, kCGKeyboardEventAutorepeat, 1);
        }
        return event;
    }
};
