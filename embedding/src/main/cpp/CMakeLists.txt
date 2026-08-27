# the minimum version of CMake.
cmake_minimum_required(VERSION 3.5.0)
project(embedding)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

include_directories(${NATIVERENDER_ROOT_PATH}
                    ${NATIVERENDER_ROOT_PATH}/include)

if (OHOS_ARCH STREQUAL "arm64-v8a")
    # arm64 真机：完整 MindSpore Lite 推理
    add_library(embedding SHARED napi_init.cpp)
    add_library(mindspore_lite SHARED IMPORTED)
    set_target_properties(mindspore_lite PROPERTIES
        IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/../../../libs/arm64-v8a/libmindspore-lite.so)
    target_link_libraries(embedding PUBLIC mindspore_lite)
else()
    # x86_64 模拟器：桩实现（官方无 ohos x86_64 运行时）
    add_library(embedding SHARED stub.cpp)
endif()

target_link_libraries(embedding PUBLIC hilog_ndk.z)
target_link_libraries(embedding PUBLIC ace_napi.z)