/*
 * yolo x86_64 桩实现：MindSpore Lite 官方仅发布 ohos-aarch64 运行时，
 * 模拟器（x86_64）无法推理，init/detect 直接抛错，由 ArkTS 侧捕获。
 */
#include <napi/native_api.h>
#include <string>

static napi_value NotSupported(napi_env env, const char *method)
{
    std::string msg = std::string("yolo.") + method + " is not supported on this ABI (x86_64 emulator)";
    napi_throw_error(env, nullptr, msg.c_str());
    return nullptr;
}

static napi_value Init(napi_env env, napi_callback_info info)
{
    return NotSupported(env, "init");
}

static napi_value Detect(napi_env env, napi_callback_info info)
{
    return NotSupported(env, "detect");
}

static napi_value InitAll(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        {"init", nullptr, Init, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"detect", nullptr, Detect, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}

static napi_module yoloModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = InitAll,
    .nm_modname = "yolo",
    .nm_priv = reinterpret_cast<void *>(0),
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterYoloModule(void)
{
    napi_module_register(&yoloModule);
}
