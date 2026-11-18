#import "session.h"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/string.hpp>
#include <cstring>
using namespace godot;

// Convert on Godot's main thread only. Capture queues use Foundation data, never Godot objects.
static Variant convert(id value) {
    if ([value isKindOfClass:NSString.class]) return String::utf8([value UTF8String]);
    if ([value isKindOfClass:NSNumber.class]) {
        if (CFGetTypeID((__bridge CFTypeRef)value)==CFBooleanGetTypeID()) return (bool)[value boolValue];
        if (strchr("fd",[value objCType][0])) return [value doubleValue];
        return (int64_t)[value longLongValue];
    }
    if ([value isKindOfClass:NSData.class]) {
        PackedByteArray bytes; bytes.resize([value length]);
        if ([value length]) memcpy(bytes.ptrw(),[value bytes],[value length]);
        return bytes;
    }
    if ([value isKindOfClass:NSArray.class]) {
        Array a; for (id entry in value) a.push_back(convert(entry)); return a;
    }
    if ([value isKindOfClass:NSDictionary.class]) {
        Dictionary d; for (NSString *key in value) d[convert(key)]=convert(value[key]); return d;
    }
    return Variant();
}
class EbonHawkNative : public RefCounted {
    GDCLASS(EbonHawkNative, RefCounted)
    EHSession *__strong session;
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("build_info"), &EbonHawkNative::build_info);
        ClassDB::bind_method(D_METHOD("permissions"), &EbonHawkNative::permissions);
        ClassDB::bind_method(D_METHOD("request_permissions"), &EbonHawkNative::request_permissions);
        ClassDB::bind_method(D_METHOD("refresh_windows"), &EbonHawkNative::refresh_windows);
        ClassDB::bind_method(D_METHOD("windows"), &EbonHawkNative::windows);
        ClassDB::bind_method(D_METHOD("select_window", "window_id"), &EbonHawkNative::select_window);
        ClassDB::bind_method(D_METHOD("status"), &EbonHawkNative::status);
        ClassDB::bind_method(D_METHOD("take_frame"), &EbonHawkNative::take_frame);
        ClassDB::bind_method(D_METHOD("begin_interaction", "native_window", "release_key"), &EbonHawkNative::begin_interaction);
        ClassDB::bind_method(D_METHOD("end_interaction"), &EbonHawkNative::end_interaction);
        ClassDB::bind_method(D_METHOD("poll_input"), &EbonHawkNative::poll_input);
        ClassDB::bind_method(D_METHOD("forward_event", "event_id", "target_point"), &EbonHawkNative::forward_event);
        ClassDB::bind_method(D_METHOD("stop"), &EbonHawkNative::stop);
    }
public:
    EbonHawkNative() { session=[EHSession new]; }
    ~EbonHawkNative() { [session stop]; session=nil; }
    String build_info() const {
        return String("M1 / macOS ") + String::utf8(NSProcessInfo.processInfo.operatingSystemVersionString.UTF8String) + " / arm64 / godot-cpp 4.5-stable";
    }
    Dictionary permissions() { return convert([session permissions]); }
    void request_permissions() { [session requestPermissions]; }
    void refresh_windows() { [session refreshWindows]; }
    Array windows() { return convert([session windows]); }
    bool select_window(int64_t id) { return [session selectWindow:(uint32_t)id]; }
    Dictionary status() { return convert([session status]); }
    Dictionary take_frame() { return convert([session takeFrame]); }
    bool begin_interaction(int64_t window, int64_t key) { return [session beginInteraction:window releaseKey:(unsigned)key]; }
    void end_interaction() { [session endInteraction]; }
    Array poll_input() { return convert([session pollInput]); }
    bool forward_event(int64_t event, Vector2 point) { return [session forwardEvent:event x:point.x y:point.y]; }
    void stop() { [session stop]; }
};
static void initialize(ModuleInitializationLevel level) {
    if (level==MODULE_INITIALIZATION_LEVEL_SCENE) ClassDB::register_class<EbonHawkNative>();
}
static void uninitialize(ModuleInitializationLevel) {}
extern "C" GDExtensionBool GDE_EXPORT ebon_hawk_library_init(GDExtensionInterfaceGetProcAddress get_proc_address,
        GDExtensionClassLibraryPtr library, GDExtensionInitialization *initialization) {
    GDExtensionBinding::InitObject init(get_proc_address,library,initialization);
    init.register_initializer(initialize); init.register_terminator(uninitialize);
    init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
