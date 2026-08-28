# Hmproject（鸿蒙健康应用）

基于 HarmonyOS NEXT（Stage 模型，API 12+）的健康应用工程，遵循以下编码规范：

1. **数字资源化**：代码中不出现魔法数字，布局尺寸、文案、颜色等统一放到 `resources` 限定词目录下（`base/element/float.json`、`string.json`、`color.json`、`integer.json`），代码中通过 `$r()` 引用，并预留 `zh_CN` / `en_US` 等多语言限定词目录。
2. **业务与页面分离**：`entry` 模块中 `pages/`、`components/` 只负责 UI；业务逻辑统一放在 `services/`，数据模型放在 `model/`，页面不直接写业务实现。
3. **能力 HAR 封装**：数据库（`database`）、网络请求（`network`）、图片读取（`image`）、日志打点（`logger`）、向量库（`vector`）、向量化（`embedding`）、大模型（`deepseek`）、对话记录（`conversation`）、图像识别（`yolo`）分别封装为独立 HAR 模块，通过 `index.ets` 暴露接口。

## 工程结构

```
HmProject
├── AppScope/                     # 应用级配置（bundleName、图标等）
├── entry/                        # 应用入口（HAP）
│   └── src/main/
│       ├── ets/
│       │   ├── entryability/     # Ability 入口（加载 pages/Chat）
│       │   ├── pages/            # 唯一对话页 Chat.ets
│       │   ├── components/       # ChatBubble / ApiKeyPrompt
│       │   ├── services/         # 业务层（ChatAgent 等 7 个服务）
│       │   ├── model/            # HealthProfile / ChatMessage 等
│       │   └── workers/          # ModelWorker（embedding/yolo 推理线程）
│       └── resources/            # 限定词资源 + rawfile（模型/提示词/知识 JSON）
├── database/                     # HAR：RDB 能力封装（health.db）
├── network/                      # HAR：HTTP 请求封装
├── image/                        # HAR：图片读取 + 相册选图
├── logger/                       # HAR：按模块日志打点
├── embedding/                    # HAR：文本向量化（原生 NDK + 占位回退）
├── vector/                       # HAR：向量库（RDB 持久化 + 余弦检索）
├── deepseek/                     # HAR：DeepSeek API + Key 存储
├── conversation/                 # HAR：对话记录持久化
├── yolo/                         # HAR：YOLOv8n 食物识别（NDK）
├── docs/                         # architecture.html（架构图）/ build-pitfalls.md（踩坑记录）
├── models/                       # 模型源文件（yolov8n / embedding）
├── LICENSE                       # 个人学习、非商用
├── build-profile.json5 / hvigorfile.ts / oh-package.json5
```

## 功能总览

- **统一对话（一个 Agent，多工作流）**：应用启动直接进入对话页，`ChatAgent` 根据上下文自动识别任务：
  - 健康档案采集（8 字段：年龄/身高/体重/睡眠/运动/症状/病史/患病周期）→ 存入向量库；
  - 健康问答：问题向量化 → RAG 检索（TopK=3）→ DeepSeek 结合记忆回答；
  - 食物确认：询问某食物能否食用时，先确认未痊愈病症，再给出能否吃的结论；
  - 事实记忆：对话中透出的健康事实自动入库（带时间戳、active/resolved 生命周期，痊愈自动解除旧事实）。
- **图片识别**：相册选图 → YOLOv8n 识别食物 → agent 判断能否食用（推理在 Worker 线程）。
- **饮食建议**：建档确认病史后，查询维基百科资料并由 DeepSeek 归纳饮食注意事项，写入向量库。
- **知识库**：联合国膳食营养指南（WHO/FAO）启动时导入向量库，供 RAG 检索。
- **对话记录**：所有用户/机器人消息按会话（health_chat / ai_chat）落库。

## 核心机制

- **提示词可编辑**：Agent 行为由 `entry/src/main/resources/rawfile/prompts/agent_prompt.md` 控制，直接改文件即可调教（模型输出严格 JSON：mode/reply/fields/facts）。
- **RAG**：每轮输出日志（`LLM call prompt / rag results / reply`），便于观察检索打分与模型行为。
- **模型线程化**：embedding 与 YOLO 的模型加载和推理都在 `ModelWorker` 线程（`ModelWorkerService` 负责 Promise RPC，ArrayBuffer 走 transfer 零拷贝），主线程只做 UI 与编排。
- **双 ABI**：arm64-v8a 完整推理；x86_64（模拟器）使用桩实现自动回退，模拟器上可正常跑对话/数据库等功能。
- **日志**：所有业务日志按模块输出（`logger` HAR，底层 hilog），大模型调用日志 tag 为 `ChatAgent`。

## 使用说明

- 使用 DevEco Studio（5.0 及以上）打开工程根目录，等待工程同步完成后即可构建运行。
- 首次真机/模拟器运行前，在 `File > Project Structure > Signing Configs` 中勾选自动签名。
- 网络请求需要网络权限，已在 `entry/src/main/module.json5` 中声明 `ohos.permission.INTERNET`。
- 应用包名：`com.tgjcl.health`
- 真机（arm64）可完整跑通 YOLO/embedding；模拟器（x86_64）为桩实现，AI 向量使用占位回退。

## 模型部署

- **YOLO**：`yolov8n.ms`（12.2 MB）随 HAP rawfile 打包，开箱即用（COCO 80 类，食物识别取其中 10 类常见食物）。
- **Embedding**：`jina-embeddings-v2-base-zh-static.ms`（615 MiB）过大不入包，需放到应用沙箱 `filesDir/models/`（连同 `tokenizer.json`）；`MemoryService` 检测到后自动启用原生向量，否则回退占位实现。
- 运行时 `libmindspore-lite.so` 在 `libs/arm64-v8a/`，CMake 构建见各模块 `src/main/cpp/`。

## 性能与体积数据（实测）

> 数据均为本机实测；真机（麒麟 aarch64 + MindSpore Lite）需复测，量级可参考。

| 指标 | 数值 | 环境 / 方法 |
| --- | --- | --- |
| YOLOv8n 单次推理 | 均值 27.3 ms（min 19.2 / max 33.2，20 次） | 开发机 x64 CPU · onnxruntime 1.29 · 输入 1×3×640×640 |
| 余弦 TopK 检索 | 单轮 ≈ 0.55 ms（768 维 × 1000 条） | 开发机 Node 实测 JS 余弦计算；RDB 读取另计 |
| HAP 打包体积 | ≈ 21.6 MB（未签名） | entry-default-unsigned.hap |
| YOLO 模型体积 | 12.2 MB（yolov8n.ms，随包 rawfile） | — |
| Embedding 模型体积 | 615 MiB（jina-embeddings-v2-base-zh-static.ms，不入包） | 需放入应用沙箱 filesDir/models/ |
| MindSpore Lite 运行时 | ≈ 5.8 MB（libmindspore-lite.so） | arm64-v8a |

对比说明：端侧推理为毫秒级、无网络依赖、图片与文本不出端；纯 API 方案单次往返通常为秒级，且需上传数据。具体取舍取决于隐私与实时性要求。

## 已知限制

- C++ 分词器为近似实现（ASCII 小写 + 空白切分 + 字符级 BPE），未实现完整 NFC 归一化，个别字符可能产生与 HF tokenizer 不同的 token。
- 645 MB 的 embedding 模型真机内存占用较大，后续可转 fp16（约 322 MB）再部署；真机推理耗时待实测。
- YOLOv8n-COCO 仅覆盖 10 类常见食物（香蕉/苹果/披萨/胡萝卜等），超出范围的图片会提示未识别。
- 饮食建议依赖维基百科中文，国内部分网络环境可能无法访问，会提示查询失败。
- API Key 目前明文存在 Preferences（个人学习够用），后续如需安全存储可接入系统级加密或 Keystore。
- x86_64 模拟器上 YOLO/embedding 为桩实现，AI 能力需在 arm64 真机验证。