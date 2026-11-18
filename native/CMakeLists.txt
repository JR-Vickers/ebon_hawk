cmake_minimum_required(VERSION 4.4.4)
project(ebon_hawk_native LANGUAGES CXX OBJCXX)
if(NOT APPLE OR NOT CMAKE_OSX_ARCHITECTURES STREQUAL "arm64")
    message(FATAL_ERROR "Prototype native build supports macOS arm64 only")
endif()

include(FetchContent)
# godot-4.5-stable, immutable commit; stock single-precision API.
FetchContent_Declare(godot_cpp
    GIT_REPOSITORY https://github.com/godotengine/godot-cpp.git
    GIT_TAG e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77
    GIT_SHALLOW FALSE
)
set(GODOTCPP_TARGET template_debug CACHE STRING "" FORCE)
set(GODOTCPP_PRECISION single CACHE STRING "" FORCE)
# Keep our warnings enabled without reporting unused parameters in dependency headers.
set(GODOTCPP_SYSTEM_HEADERS ON CACHE BOOL "" FORCE)
set(GODOTCPP_BUILD_PROFILE "${CMAKE_CURRENT_SOURCE_DIR}/build_profile.json" CACHE PATH "" FORCE)
FetchContent_MakeAvailable(godot_cpp)

add_library(ebon_hawk SHARED src/bridge.mm src/session.mm)
target_link_libraries(ebon_hawk PRIVATE godot::cpp "-framework Foundation" "-framework AppKit" "-framework ApplicationServices"
    "-framework ScreenCaptureKit" "-framework CoreMedia" "-framework CoreVideo")
target_compile_options(ebon_hawk PRIVATE -fobjc-arc -Wall -Wextra)
target_compile_features(ebon_hawk PRIVATE cxx_std_17)
set_target_properties(ebon_hawk PROPERTIES
    OBJCXX_STANDARD 17
    CXX_VISIBILITY_PRESET hidden
    OBJCXX_VISIBILITY_PRESET hidden
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/bin"
)
