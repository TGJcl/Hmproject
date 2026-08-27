# Hmproject（鸿蒙健康应用）
这是一个没有价值的垃圾项目
基于 HarmonyOS NEXT（Stage 模型，API 12+）的健康应用工程，遵循以下编码规范：

1. **数字资源化**：代码中不出现魔法数字，布局尺寸、文案、颜色等统一放到 `resources` 限定词目录下（`base/element/float.json`、`string.json`、`color.json`、`integer.json`），代码中通过 `$r()` 引用，并预留 `zh_CN` / `en_US` 等多语言限定词目录。
2. **业务与页面分离**：`entry` 模块中 `pages/`、`components/` 只负责 UI；业务逻辑统一放在 `services/`，数据模型放在 `model/`，页面不直接写业务实现。
3. **能力 HAR 封装**：数据库（`database`）、网络请求（`network`）、图片读取（`image`）、日志打点（`logger`）分别封装为独立 HAR 模块，通过 `index.ets` 暴露接口，供 `entry` 依赖调用。

## 工程结构

```
HmProject
├── AppScope/                     # 应用级配置（bundleName、应用图标等）
│   └── resources/base/
├── entry/                        # 应用入口（HAP）：页面与业务层
│   └── src/main/
│       ├── ets/
│       │   ├── entryability/     # Ability 入口
│       │   ├── pages/            # 页面（仅 UI）
│       │   ├── components/       # 可复用 UI 组件
│       │   ├── services/         # 业务逻辑层
│       │   └── model/            # 数据模型
│       └── resources/            # 资源目录（含限定词目录）
├── database/                     # HAR：数据库能力封装
├── network/                      # HAR：网络请求能力封装
├── image/                        # HAR：图片读取能力封装
├── logger/                       # HAR：日志打点能力封装
├── build-profile.json5           # 工程级构建配置
├── hvigorfile.ts
└── oh-package.json5
```

## 使用说明

- 使用 DevEco Studio（5.0 及以上）打开工程根目录，等待工程同步完成后即可构建运行。
- 首次真机/模拟器运行前，在 `File > Project Structure > Signing Configs` 中勾选自动签名。
- 网络请求需要网络权限，已在 `entry/src/main/module.json5` 中声明 `ohos.permission.INTERNET`。
- 应用包名：`com.tgjcl.health`

## 日志打点工具（logger HAR）

`logger` 是一个独立的 HAR 模块，业务日志统一通过它按模块输出（底层走 `hilog`）：

```ts
import { getLogger, LogLevel, LogManager } from 'logger';

const LOG = getLogger('HealthService'); // 按模块取日志器，tag 即为模块名
LOG.info('init begin');
LOG.warn('数据为空');
LOG.error('请求失败：%{public}s', errorMsg);

// 可选：调整日志级别（默认 DEBUG，全部输出）
LogManager.setGlobalLevel(LogLevel.INFO);      // 全局级别
LogManager.setModuleLevel('HealthService', LogLevel.WARN); // 按模块覆盖
```

说明：
- 每个业务模块通过 `getLogger('模块名')` 获取独立日志器，输出的 tag 即模块名，便于在 DevEco 日志中按模块过滤。
- 支持 `debug / info / warn / error` 四个级别，可按模块单独设置级别开关。
- 日志消息支持 `hilog` 占位符（`%{public}s` / `%{public}d`），隐私字段请改用 `%{private}s`。

## 功能 1：对话采集健康信息 → 存入向量数据库

- **入口**：首页「健康对话」按钮 → `pages/HealthChat`
- **对话采集**：`HealthChatService` 按顺序提问（年龄/身高/体重/睡眠/运动/症状），用规则从回复中抽取健康字段，支持「没有/无」等回答
- **记忆入库**：采集完成后 `MemoryService` 把健康档案文本向量化（`embedding` HAR）后写入本地向量库（`vector` HAR，基于 RDB 持久化，余弦相似度检索）
- **Embedding 说明**：当前使用占位实现 `LocalHashEmbedding`；真实模型 `jina-embeddings-v2-base-zh`（MindSpore Lite `.ms`，固定 1×256）已转换并部署在 `models/embedding/`，后续通过 NDK C++ 封装后经 `EmbeddingManager.setProvider()` 切换

## 功能：DeepSeek 大模型交互（RAG 问答）

- **入口**：首页「AI 问答」按钮 → `pages/AiChat`
- **API Key**：应用首次启动时（首页 `aboutToAppear`）检测未配置则弹出输入框索取，保存到本地 Preferences（`deepseek` HAR 的 `DeepSeekConfig`）
- **RAG 流程**（`AiChatService`）：用户提问 → 问题向量化（`embedding`）→ 从向量库检索最相关的健康记忆（`vector`，TopK=3）→ 组装 system prompt + 记忆片段 + 问题 → 调用 DeepSeek `chat/completions`（`deepseek` HAR → `network` HAR）→ 返回答案展示
- **DeepSeek 接口**：`deepseek-chat` 模型，请求超时 60s
- 注意：API Key 目前明文存在 Preferences（个人学习够用），后续如需安全存储可接入系统级加密或 Keystore

## NDK C++ 推理封装（MindSpore Lite）

两个推理模型都已完成 C++/NAPI 封装：

- **yolo HAR**：模型 `yolov8n.ms` 随模块 rawfile 打包；`YoloDetector.init(resourceManager)` 加载，`detect(rgbaBuffer, width, height)` 异步推理，返回 `DetectionResult[]`（COCO 80 类标签 + 置信度 + 坐标，已做 letterbox/NMS 后处理）
- **embedding HAR**：`NativeEmbedding.init(modelPath, tokenizerPath)` 加载 `jina-embeddings-v2-base-zh-static.ms` 与 BPE 分词器（`tokenizer.json`）；`embed(text)` 返回 768 维归一化向量（均值池化）
- 运行时：`libmindspore-lite.so` 已放到各模块 `libs/arm64-v8a/`，头文件在 `src/main/cpp/include/`，CMake 在 `src/main/cpp/CMakeLists.txt`

部署与使用：

- yolo 模型随 HAP 打包（rawfile），开箱即用
- embedding 模型 645MB 过大不能进 rawfile，需放到应用沙箱 `filesDir/models/` 下（`jina-embeddings-v2-base-zh-static.ms` + `tokenizer.json`）；`MemoryService` 检测到文件后会自动切换 `EmbeddingManager` 到原生实现，否则回退占位 embedding
- 目前只提供 `arm64-v8a` ABI；模拟器（x86_64）需要另行放置对应架构的 `libmindspore-lite.so`

已知限制：

- C++ 分词器为近似实现（ASCII 小写 + 空白切分 + 字符级 BPE），未实现完整 NFC 归一化，个别字符可能产生与 HF tokenizer 不同的 token，后续可按需完善
- 645MB 的 embedding 模型在真机上内存占用较大，后续可转 fp16（约 322MB）再部署
