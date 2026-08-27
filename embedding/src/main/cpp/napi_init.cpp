/*
 * jina-embeddings-v2-base-zh NDK C++ inference wrapper (MindSpore Lite)
 * 个人学习用途，非商用。包含：BPE 分词（tokenizer.json）→ 推理 → 均值池化 → L2 归一化
 */
#include <napi/native_api.h>
#include <hilog/log.h>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <unordered_map>
#include <cstring>
#include <cmath>
#include <cstdint>
#include <climits>
#include <memory>
#include "api/model.h"
#include "api/context.h"
#include "api/types.h"
#include "api/status.h"
#include "nlohmann/json.hpp"

static constexpr char EmbeddingNative_TAG[] = "EmbeddingNative";
#define LOGI(...) OH_LOG_Print(LOG_APP, LOG_INFO, 0x0000, EmbeddingNative_TAG, __VA_ARGS__)
#define LOGE(...) OH_LOG_Print(LOG_APP, LOG_ERROR, 0x0000, EmbeddingNative_TAG, __VA_ARGS__)

namespace {
constexpr int kSeqLen = 256;
constexpr int kHidden = 768;
constexpr int kIdCls = 0;
constexpr int kIdPad = 1;
constexpr int kIdSep = 2;
constexpr int kIdUnk = 3;

struct ModelHolder {
    mindspore::Model model;
    std::vector<uint8_t> buffer;
    bool built = false;
};
ModelHolder g_model;

struct Tokenizer {
    std::unordered_map<std::string, int32_t> vocab;
    std::unordered_map<std::string, int> merges;
    bool loaded = false;
};
Tokenizer g_tok;

napi_value ThrowError(napi_env env, const std::string &msg)
{
    napi_throw_error(env, nullptr, msg.c_str());
    return nullptr;
}

bool ReadFile(const std::string &path, std::vector<uint8_t> &out)
{
    std::ifstream in(path, std::ios::binary | std::ios::ate);
    if (!in) {
        return false;
    }
    std::streamsize size = in.tellg();
    if (size <= 0) {
        return false;
    }
    in.seekg(0, std::ios::beg);
    out.resize(static_cast<size_t>(size));
    in.read(reinterpret_cast<char *>(out.data()), size);
    return !in.fail();
}

// ---------- 分词器（近似实现：ASCII 小写 + 空白切分 + 字符级 BPE） ----------
std::string ToLowerAscii(const std::string &s)
{
    std::string r = s;
    for (size_t i = 0; i < r.size(); i++) {
        if (r[i] >= 'A' && r[i] <= 'Z') {
            r[i] = static_cast<char>(r[i] + 32);
        }
    }
    return r;
}

std::vector<std::string> Utf8Chars(const std::string &s)
{
    std::vector<std::string> chars;
    for (size_t i = 0; i < s.size();) {
        unsigned char c = static_cast<unsigned char>(s[i]);
        size_t n = 1;
        if ((c & 0xE0) == 0xC0) {
            n = 2;
        } else if ((c & 0xF0) == 0xE0) {
            n = 3;
        } else if ((c & 0xF8) == 0xF0) {
            n = 4;
        }
        chars.push_back(s.substr(i, n));
        i += n;
    }
    return chars;
}

std::vector<std::string> SplitWhitespace(const std::string &s)
{
    std::vector<std::string> words;
    std::string cur;
    for (char c : s) {
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
            if (!cur.empty()) {
                words.push_back(cur);
                cur.clear();
            }
        } else {
            cur.push_back(c);
        }
    }
    if (!cur.empty()) {
        words.push_back(cur);
    }
    return words;
}

std::vector<int32_t> BpeEncodeWord(const std::string &word)
{
    std::vector<std::string> parts = Utf8Chars(word);
    while (parts.size() > 1) {
        int bestRank = INT_MAX;
        int bestPos = -1;
        for (size_t i = 0; i + 1 < parts.size(); i++) {
            std::string pair = parts[i] + parts[i + 1];
            auto it = g_tok.merges.find(pair);
            if (it != g_tok.merges.end() && it->second < bestRank) {
                bestRank = it->second;
                bestPos = static_cast<int>(i);
            }
        }
        if (bestPos < 0) {
            break;
        }
        parts[bestPos] += parts[bestPos + 1];
        parts.erase(parts.begin() + bestPos + 1);
    }
    std::vector<int32_t> ids;
    for (const auto &p : parts) {
        auto it = g_tok.vocab.find(p);
        ids.push_back(it != g_tok.vocab.end() ? it->second : kIdUnk);
    }
    return ids;
}

std::vector<int32_t> EncodeText(const std::string &text)
{
    std::string norm = ToLowerAscii(text);
    std::vector<int32_t> ids;
    ids.push_back(kIdCls);
    for (const auto &word : SplitWhitespace(norm)) {
        std::vector<int32_t> wid = BpeEncodeWord(word);
        ids.insert(ids.end(), wid.begin(), wid.end());
    }
    if (ids.size() > kSeqLen - 1) {
        ids.resize(kSeqLen - 1);
    }
    ids.push_back(kIdSep);
    return ids;
}

bool LoadTokenizer(const std::string &path)
{
    std::ifstream in(path, std::ios::binary);
    if (!in) {
        return false;
    }
    nlohmann::json root;
    try {
        in >> root;
    } catch (...) {
        return false;
    }
    const auto &model = root["model"];
    for (auto it = model["vocab"].begin(); it != model["vocab"].end(); ++it) {
        g_tok.vocab[it.key()] = it.value().get<int32_t>();
    }
    int rank = 0;
    for (const auto &m : model["merges"]) {
        g_tok.merges[m.get<std::string>()] = rank++;
    }
    g_tok.loaded = true;
    LOGI("tokenizer loaded, vocab=%zu merges=%zu", g_tok.vocab.size(), g_tok.merges.size());
    return true;
}
}  // namespace

// ============ init(modelPath, tokenizerPath) ============
static napi_value Init(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 2) {
        return ThrowError(env, "init: need modelPath and tokenizerPath");
    }
    char modelBuf[1024];
    size_t modelLen = 0;
    char tokBuf[1024];
    size_t tokLen = 0;
    if (napi_get_value_string_utf8(env, args[0], modelBuf, sizeof(modelBuf), &modelLen) != napi_ok ||
        napi_get_value_string_utf8(env, args[1], tokBuf, sizeof(tokBuf), &tokLen) != napi_ok) {
        return ThrowError(env, "init: invalid paths");
    }
    std::string modelPath(modelBuf, modelLen);
    std::string tokenizerPath(tokBuf, tokLen);

    if (!LoadTokenizer(tokenizerPath)) {
        return ThrowError(env, "init: load tokenizer failed: " + tokenizerPath);
    }
    if (!ReadFile(modelPath, g_model.buffer)) {
        return ThrowError(env, "init: read model failed: " + modelPath);
    }

    auto ctx = std::make_shared<mindspore::Context>();
    auto &deviceList = ctx->MutableDeviceInfo();
    auto cpuInfo = std::make_shared<mindspore::CPUDeviceInfo>();
    cpuInfo->SetEnableFP16(false);
    deviceList.push_back(cpuInfo);

    mindspore::Status st = g_model.model.Build(g_model.buffer.data(), g_model.buffer.size(),
                                               mindspore::kMindIR, ctx);
    if (st != mindspore::kSuccess) {
        return ThrowError(env, "init: model build failed");
    }
    g_model.built = true;
    LOGI("embedding model built, modelSize=%zu, inputs=%zu", g_model.buffer.size(),
         g_model.model.GetInputs().size());
    return nullptr;
}

// ============ embed(text): Promise<Array<number>> ============
struct EmbedJob {
    napi_env env = nullptr;
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::string text;
    std::string error;
    std::vector<float> embedding;
};

static void EmbedExecute(napi_env env, void *data)
{
    EmbedJob *job = static_cast<EmbedJob *>(data);
    if (!g_model.built || !g_tok.loaded) {
        job->error = "embedding not initialized, call init() first";
        return;
    }

    std::vector<int32_t> ids = EncodeText(job->text);
    std::vector<int64_t> inputIds(kSeqLen, kIdPad);
    std::vector<int64_t> mask(kSeqLen, 0);
    for (int i = 0; i < kSeqLen && i < static_cast<int>(ids.size()); i++) {
        inputIds[i] = ids[i];
        mask[i] = 1;
    }

    auto inputs = g_model.model.GetInputs();
    if (inputs.size() < 2) {
        job->error = "model inputs count mismatch";
        return;
    }
    void *idsData = inputs[0].MutableData();
    void *maskData = inputs[1].MutableData();
    if (idsData == nullptr || maskData == nullptr) {
        job->error = "input MutableData failed";
        return;
    }
    if (inputs[0].DataSize() != static_cast<size_t>(kSeqLen) * sizeof(int64_t) ||
        inputs[1].DataSize() != static_cast<size_t>(kSeqLen) * sizeof(int64_t)) {
        job->error = "input size mismatch";
        return;
    }
    memcpy(idsData, inputIds.data(), inputIds.size() * sizeof(int64_t));
    memcpy(maskData, mask.data(), mask.size() * sizeof(int64_t));

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
    const float *hidden = reinterpret_cast<const float *>(outputs[0].Data().get());
    if (outputs[0].ElementNum() != static_cast<size_t>(kSeqLen) * kHidden) {
        job->error = "unexpected output shape";
        return;
    }

    // 均值池化（对非 padding 位置） + L2 归一化
    std::vector<float> pooled(kHidden, 0.0f);
    int count = 0;
    for (int t = 0; t < kSeqLen; t++) {
        if (mask[t] == 0) {
            continue;
        }
        count++;
        const float *row = hidden + static_cast<size_t>(t) * kHidden;
        for (int d = 0; d < kHidden; d++) {
            pooled[d] += row[d];
        }
    }
    if (count > 0) {
        for (int d = 0; d < kHidden; d++) {
            pooled[d] /= static_cast<float>(count);
        }
    }
    float norm = 0.0f;
    for (int d = 0; d < kHidden; d++) {
        norm += pooled[d] * pooled[d];
    }
    norm = std::sqrt(norm);
    if (norm > 0.0f) {
        for (int d = 0; d < kHidden; d++) {
            pooled[d] /= norm;
        }
    }
    job->embedding = pooled;
    LOGI("embed done, dim=%zu", job->embedding.size());
}

static void EmbedComplete(napi_env env, napi_status status, void *data)
{
    EmbedJob *job = static_cast<EmbedJob *>(data);
    if (status == napi_ok && job->error.empty()) {
        napi_value arr;
        napi_create_array_with_length(env, job->embedding.size(), &arr);
        for (size_t i = 0; i < job->embedding.size(); i++) {
            napi_value v;
            napi_create_double(env, job->embedding[i], &v);
            napi_set_element(env, arr, i, v);
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

static napi_value Embed(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1) {
        return ThrowError(env, "embed: need text");
    }
    char textBuf[4096];
    size_t textLen = 0;
    if (napi_get_value_string_utf8(env, args[0], textBuf, sizeof(textBuf), &textLen) != napi_ok) {
        return ThrowError(env, "embed: invalid text");
    }
    EmbedJob *job = new EmbedJob();
    job->env = env;
    job->text.assign(textBuf, textLen);

    napi_value promise;
    napi_create_promise(env, &job->deferred, &promise);
    napi_value resourceName;
    napi_create_string_utf8(env, "EmbeddingEmbed", NAPI_AUTO_LENGTH, &resourceName);
    napi_create_async_work(env, nullptr, resourceName, EmbedExecute, EmbedComplete, job, &job->work);
    napi_queue_async_work(env, job->work);
    return promise;
}

// ============ 模块注册 ============
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
