/*
 * embedding x86_64 桩实现：MindSpore Lite 官方仅发布 ohos-aarch64 运行时，
 * 模拟器（x86_64）无法推理，init/embed 直接抛错，由 ArkTS 侧回退占位向量。
 */
#include <napi/native_api.h>
#include <string>

static napi_value NotSupported(napi_env env, const char *method)
{
    std::string msg = std::string("embedding.") + method + " is not supported on this ABI (x86_64 emulator)";
    napi_throw_error(env, nullptr, msg.c_str());
    return nullptr;
}

static napi_value Init(napi_env env, napi_callback_info info)
{
    return NotSupported(env, "init");
}

static napi_value Embed(napi_env env, napi_callback_info info)
{
    return NotSupported(env, "embed");
}

static napi_value InitAll(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        {"init", nullptr, Init, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"embed", nullptr, Embed, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}

static napi_module embeddingModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = InitAll,
    .nm_modname = "embedding",
    .nm_priv = reinterpret_cast<void *>(0),
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterEmbeddingModule(void)
{
    napi_module_register(&embeddingModule);
}
