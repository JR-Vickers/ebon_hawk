#pragma once

#include <ApplicationServices/ApplicationServices.h>
#include <cstdint>

static constexpr int64_t EH_EVENT_TAG = 0x45424f4e4841574b;

static inline void ehMarkTargetProcess(CGEventRef event, pid_t pid) {
    CGEventSetIntegerValueField(event, kCGEventTargetUnixProcessID, pid);
    CGEventSetIntegerValueField(event, kCGEventSourceUserData, EH_EVENT_TAG);
}
