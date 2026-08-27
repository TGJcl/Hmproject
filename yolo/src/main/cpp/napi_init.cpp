/*
 * YOLOv8n NDK C++ inference wrapper (MindSpore Lite)
 * 个人学习用途，非商用。模型：yolov8n.ms（COCO 80 类）
 */
#include <napi/native_api.h>
#include <hilog/log.h>
#include <rawfile/raw_file_manager.h>
#include <string>
#include <vector>
#include <cstring>
#include <cmath>
#include <algorithm>
#include <memory>
#include "api/model.h"
#include "api/context.h"
#include "api/types.h"
#include "api/status.h"

static constexpr char YoloNative_TAG[] = "YoloNative";
#define LOGI(...) OH_LOG_Print(LOG_APP, LOG_INFO, 0x0000, YoloNative_TAG, __VA_ARGS__)
#define LOGE(...) OH_LOG_Print(LOG_APP, LOG_ERROR, 0x0000, YoloNative_TAG, __VA_ARGS__)

namespace {
constexpr int kInputSize = 640;
constexpr int kNumClasses = 80;
constexpr int kNumAnchors = 8400;
constexpr float kConfThresh = 0.25f;
constexpr float kNmsThresh = 0.45f;
constexpr float kPadValue = 114.0f;

const char *kClassNames[kNumClasses] = {
    "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck", "boat",
    "traffic light", "fire hydrant", "stop sign", "parking meter", "bench", "bird", "cat",
    "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra", "giraffe", "backpack",
    "umbrella", "handbag", "tie", "suitcase", "frisbee", "skis", "snowboard", "sports ball",
    "kite", "baseball bat", "baseball glove", "skateboard", "surfboard", "tennis racket",
    "bottle", "wine glass", "cup", "fork", "knife", "spoon", "bowl", "banana", "apple",
    "sandwich", "orange", "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair",
    "couch", "potted plant", "bed", "dining table", "toilet", "tv", "laptop", "mouse",
    "remote", "keyboard", "cell phone", "microwave", "oven", "toaster", "sink", "refrigerator",
    "book", "clock", "vase", "scissors", "teddy bear", "hair drier", "toothbrush"
};

struct Detection {
    float x1;
    float y1;
    float x2;
    float y2;
    float score;
    int classId;
};

struct ModelHolder {
    mindspore::Model model;
    void *buffer = nullptr;
    size_t bufferSize = 0;
    bool built = false;
};
ModelHolder g_model;

napi_value ThrowError(napi_env env, const std::string &msg)
{
    napi_throw_error(env, nullptr, msg.c_str());
    return nullptr;
}
}  // namespace

static bool BuildModelFromMemory(napi_env env, const void *data, size_t size);

// ============ init(resourceManager, modelName)：从 rawfile 读取模型并构建 ============
static napi_value Init(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 2) {
        return ThrowError(env, "init: need resourceManager and modelName");
    }

    NativeResourceManager *resMgr = OH_ResourceManager_InitNativeResourceManager(env, args[0]);
    if (resMgr == nullptr) {
        return ThrowError(env, "init: failed to get resource manager");
    }
    char nameBuf[512];
    size_t nameLen = 0;
    if (napi_get_value_string_utf8(env, args[1], nameBuf, sizeof(nameBuf), &nameLen) != napi_ok) {
        return ThrowError(env, "init: invalid modelName");
    }
    std::string modelName(nameBuf, nameLen);

    RawFile *rawFile = OH_ResourceManager_OpenRawFile(resMgr, modelName.c_str());
    if (rawFile == nullptr) {
        OH_ResourceManager_ReleaseNativeResourceManager(resMgr);
        return ThrowError(env, "init: open rawfile model failed: " + modelName);
    }
    long fileSize = OH_ResourceManager_GetRawFileSize(rawFile);
    void *buffer = malloc(static_cast<size_t>(fileSize));
    int ret = OH_ResourceManager_ReadRawFile(rawFile, buffer, static_cast<size_t>(fileSize));
    OH_ResourceManager_CloseRawFile(rawFile);
    OH_ResourceManager_ReleaseNativeResourceManager(resMgr);
    if (ret == 0 || buffer == nullptr) {
        if (buffer != nullptr) {
            free(buffer);
        }
        return ThrowError(env, "init: read rawfile model failed");
    }

    if (!BuildModelFromMemory(env, buffer, static_cast<size_t>(fileSize))) {
        free(buffer);
        return ThrowError(env, "init: model build failed");
    }
    if (g_model.buffer != nullptr) {
        free(g_model.buffer);
    }
    g_model.buffer = buffer;
    g_model.bufferSize = static_cast<size_t>(fileSize);
    g_model.built = true;
    LOGI("model built, inputs=%zu", g_model.model.GetInputs().size());
    return nullptr;
}

static bool BuildModelFromMemory(napi_env env, const void *data, size_t size)
{
    auto ctx = std::make_shared<mindspore::Context>();
    auto &deviceList = ctx->MutableDeviceInfo();
    auto cpuInfo = std::make_shared<mindspore::CPUDeviceInfo>();
    cpuInfo->SetEnableFP16(false);
    deviceList.push_back(cpuInfo);

    mindspore::Status st = g_model.model.Build(data, size, mindspore::kMindIR, ctx);
    return st == mindspore::kSuccess;
}

// ============ initFromBuffer(buffer)：从内存构建模型（供 Worker 线程使用） ============
static napi_value InitFromBuffer(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1) {
        return ThrowError(env, "initFromBuffer: need ArrayBuffer");
    }
    bool isBuffer = false;
    napi_is_arraybuffer(env, args[0], &isBuffer);
    if (!isBuffer) {
        return ThrowError(env, "initFromBuffer: need ArrayBuffer");
    }
    void *data = nullptr;
    size_t len = 0;
    napi_get_arraybuffer_info(env, args[0], &data, &len);
    if (data == nullptr || len == 0) {
        return ThrowError(env, "initFromBuffer: empty buffer");
    }
    void *copy = malloc(len);
    if (copy == nullptr) {
        return ThrowError(env, "initFromBuffer: out of memory");
    }
    memcpy(copy, data, len);
    if (!BuildModelFromMemory(env, copy, len)) {
        free(copy);
        return ThrowError(env, "initFromBuffer: model build failed");
    }
    if (g_model.buffer != nullptr) {
        free(g_model.buffer);
    }
    g_model.buffer = copy;
    g_model.bufferSize = len;
    g_model.built = true;
    LOGI("model built from buffer, size=%zu, inputs=%zu", len, g_model.model.GetInputs().size());
    return nullptr;
}

// ============ detect(imageData: ArrayBuffer, width, height): Promise ============
struct DetectJob {
    napi_env env = nullptr;
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::vector<uint8_t> rgba;
    int width = 0;
    int height = 0;
    std::string error;
    std::vector<Detection> dets;
};

static void DetectExecute(napi_env env, void *data)
{
    DetectJob *job = static_cast<DetectJob *>(data);
    if (!g_model.built) {
        job->error = "yolo model not initialized, call init() first";
        return;
    }

    const int target = kInputSize;
    float scale = std::min(static_cast<float>(target) / static_cast<float>(job->width),
                           static_cast<float>(target) / static_cast<float>(job->height));
    int newW = static_cast<int>(std::round(job->width * scale));
    int newH = static_cast<int>(std::round(job->height * scale));
    if (newW < 1) {
        newW = 1;
    }
    if (newH < 1) {
        newH = 1;
    }
    int padX = (target - newW) / 2;
    int padY = (target - newH) / 2;

    // letterbox + RGB 归一化（RGBA -> 1x3x640x640 float）
    std::vector<float> input(3 * target * target, kPadValue / 255.0f);
    for (int y = 0; y < newH; y++) {
        for (int x = 0; x < newW; x++) {
            size_t src = (static_cast<size_t>(y) * job->width + x) * 4;
            int dy = y + padY;
            int dx = x + padX;
            size_t plane = static_cast<size_t>(target) * target;
            input[0 * plane + dy * target + dx] = job->rgba[src] / 255.0f;
            input[1 * plane + dy * target + dx] = job->rgba[src + 1] / 255.0f;
            input[2 * plane + dy * target + dx] = job->rgba[src + 2] / 255.0f;
        }
    }

    auto inputs = g_model.model.GetInputs();
    if (inputs.empty()) {
        job->error = "model has no inputs";
        return;
    }
    if (inputs[0].DataSize() != input.size() * sizeof(float)) {
        job->error = "input size mismatch";
        return;
    }
    void *inputData = inputs[0].MutableData();
    if (inputData == nullptr) {
        job->error = "input MutableData failed";
        return;
    }
    memcpy(inputData, input.data(), input.size() * sizeof(float));

    std::vector<mindspore::MSTensor> outputs;
    mindspore::Status st = g_model.model.Predict(inputs, &outputs);
    if (st != mindspore::kSuccess) {
        job->error = "predict failed";
        return;
    }
    if (outputs.empty()) {
        job->error = "model has no outputs";
        return;
    }
    const float *out = reinterpret_cast<const float *>(outputs[0].Data().get());
    if (outputs[0].ElementNum() != static_cast<size_t>((4 + kNumClasses) * kNumAnchors)) {
        job->error = "unexpected output shape";
        return;
    }

    // 解码：每个 anchor 取最高类别分，过滤阈值
    std::vector<Detection> all;
    for (int a = 0; a < kNumAnchors; a++) {
        float best = 0.0f;
        int bestCls = -1;
        for (int c = 0; c < kNumClasses; c++) {
            float s = out[(4 + c) * kNumAnchors + a];
            if (s > best) {
                best = s;
                bestCls = c;
            }
        }
        if (bestCls < 0 || best < kConfThresh) {
            continue;
        }
        float cx = out[0 * kNumAnchors + a];
        float cy = out[1 * kNumAnchors + a];
        float w = out[2 * kNumAnchors + a];
        float h = out[3 * kNumAnchors + a];
        Detection d;
        d.x1 = (cx - w * 0.5f - padX) / scale;
        d.y1 = (cy - h * 0.5f - padY) / scale;
        d.x2 = (cx + w * 0.5f - padX) / scale;
        d.y2 = (cy + h * 0.5f - padY) / scale;
        d.score = best;
        d.classId = bestCls;
        all.push_back(d);
    }

    std::sort(all.begin(), all.end(),
              [](const Detection &a, const Detection &b) { return a.score > b.score; });
    std::vector<bool> removed(all.size(), false);
    for (size_t i = 0; i < all.size(); i++) {
        if (removed[i]) {
            continue;
        }
        job->dets.push_back(all[i]);
        for (size_t j = i + 1; j < all.size(); j++) {
            if (removed[j]) {
                continue;
            }
            float ix1 = std::max(all[i].x1, all[j].x1);
            float iy1 = std::max(all[i].y1, all[j].y1);
            float ix2 = std::min(all[i].x2, all[j].x2);
            float iy2 = std::min(all[i].y2, all[j].y2);
            float inter = std::max(0.0f, ix2 - ix1) * std::max(0.0f, iy2 - iy1);
            float areaI = (all[i].x2 - all[i].x1) * (all[i].y2 - all[i].y1);
            float areaJ = (all[j].x2 - all[j].x1) * (all[j].y2 - all[j].y1);
            float uni = areaI + areaJ - inter;
            if (uni <= 0.0f) {
                continue;
            }
            if (inter / uni > kNmsThresh) {
                removed[j] = true;
            }
        }
    }
    LOGI("detect done, boxes=%zu", job->dets.size());
}

static void DetectComplete(napi_env env, napi_status status, void *data)
{
    DetectJob *job = static_cast<DetectJob *>(data);
    if (status == napi_ok && job->error.empty()) {
        napi_value arr;
        napi_create_array_with_length(env, job->dets.size(), &arr);
        for (size_t i = 0; i < job->dets.size(); i++) {
            const Detection &d = job->dets[i];
            napi_value obj;
            napi_create_object(env, &obj);
            napi_value v;
            napi_create_string_utf8(env, kClassNames[d.classId], NAPI_AUTO_LENGTH, &v);
            napi_set_named_property(env, obj, "label", v);
            napi_create_double(env, d.score, &v);
            napi_set_named_property(env, obj, "score", v);
            napi_create_double(env, d.x1, &v);
            napi_set_named_property(env, obj, "x", v);
            napi_create_double(env, d.y1, &v);
            napi_set_named_property(env, obj, "y", v);
            napi_create_double(env, d.x2 - d.x1, &v);
            napi_set_named_property(env, obj, "width", v);
            napi_create_double(env, d.y2 - d.y1, &v);
            napi_set_named_property(env, obj, "height", v);
            napi_set_element(env, arr, i, obj);
        }
        napi_resolve_deferred(env, job->deferred, arr);
    } else {
        napi_value err;
        napi_create_string_utf8(env, job->error.c_str(), NAPI_AUTO_LENGTH, &err);
        napi_reject_deferred(env, job->deferred, err);
    }
    napi_delete_async_work(env, job->work);
    delete job;
}

static napi_value Detect(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 3) {
        return ThrowError(env, "detect: need imageData, width, height");
    }
    bool isArrayBuffer = false;
    napi_is_arraybuffer(env, args[0], &isArrayBuffer);
    if (!isArrayBuffer) {
        return ThrowError(env, "detect: imageData must be ArrayBuffer");
    }
    void *data = nullptr;
    size_t len = 0;
    napi_get_arraybuffer_info(env, args[0], &data, &len);
    int32_t w = 0;
    int32_t h = 0;
    napi_get_value_int32(env, args[1], &w);
    napi_get_value_int32(env, args[2], &h);

    DetectJob *job = new DetectJob();
    job->env = env;
    job->width = w;
    job->height = h;
    job->rgba.assign(static_cast<uint8_t *>(data), static_cast<uint8_t *>(data) + len);

    napi_value promise;
    napi_create_promise(env, &job->deferred, &promise);
    napi_value resourceName;
    napi_create_string_utf8(env, "YoloDetect", NAPI_AUTO_LENGTH, &resourceName);
    napi_create_async_work(env, nullptr, resourceName, DetectExecute, DetectComplete, job, &job->work);
    napi_queue_async_work(env, job->work);
    return promise;
}

// ============ 模块注册 ============
static napi_value InitAll(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        {"init", nullptr, Init, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"initFromBuffer", nullptr, InitFromBuffer, nullptr, nullptr, nullptr, napi_default, nullptr},
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
