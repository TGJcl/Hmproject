# Hmproject（鸿蒙健康应用）

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
