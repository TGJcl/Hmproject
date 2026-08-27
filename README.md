# Hmproject（鸿蒙健康应用）

基于 HarmonyOS NEXT（Stage 模型，API 12+）的健康应用工程，遵循以下编码规范：

1. **数字资源化**：代码中不出现魔法数字，布局尺寸、文案、颜色等统一放到 `resources` 限定词目录下（`base/element/float.json`、`string.json`、`color.json`、`integer.json`），代码中通过 `$r()` 引用，并预留 `zh_CN` / `en_US` 等多语言限定词目录。
2. **业务与页面分离**：`entry` 模块中 `pages/`、`components/` 只负责 UI；业务逻辑统一放在 `services/`，数据模型放在 `model/`，页面不直接写业务实现。
3. **能力 HAR 封装**：数据库（`database`）、网络请求（`network`）、图片读取（`image`）分别封装为独立 HAR 模块，通过 `index.ets` 暴露接口，供 `entry` 依赖调用。

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
├── build-profile.json5           # 工程级构建配置
├── hvigorfile.ts
└── oh-package.json5
```

## 使用说明

- 使用 DevEco Studio（5.0 及以上）打开工程根目录，等待工程同步完成后即可构建运行。
- 首次真机/模拟器运行前，在 `File > Project Structure > Signing Configs` 中勾选自动签名。
- 网络请求需要网络权限，已在 `entry/src/main/module.json5` 中声明 `ohos.permission.INTERNET`。
- 应用包名：`com.tgjcl.health`
