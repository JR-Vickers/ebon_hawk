// Independent compiler/SDK check. Does not exercise the Godot native bridge.
#import <Foundation/Foundation.h>
#include <cstdio>

int main() {
    @autoreleasepool {
        std::puts([[[NSProcessInfo processInfo] operatingSystemVersionString] UTF8String]);
    }
    return 0;
}
