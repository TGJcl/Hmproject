# the minimum version of CMake.
cmake_minimum_required(VERSION 3.5.0)
project(yolo)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

include_directories(${NATIVERENDER_ROOT_PATH}
                    ${NATIVERENDER_ROOT_PATH}/include)

add_library(yolo SHARED napi_init.cpp)

add_library(mindspore_lite SHARED IMPORTED)
set_target_properties(mindspore_lite PROPERTIES
    IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/../../../libs/arm64-v8a/libmindspore-lite.so)

target_link_libraries(yolo PUBLIC mindspore_lite)
target_link_libraries(yolo PUBLIC hilog_ndk.z)
target_link_libraries(yolo PUBLIC rawfile.z)
target_link_libraries(yolo PUBLIC ace_napi.z)
