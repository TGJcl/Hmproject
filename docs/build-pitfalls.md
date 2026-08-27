# 鸿蒙工程编译阶段踩坑记录

> 记录 HmProject 搭建与编译过程中实际遇到的问题、根因与解决方案，供后续开发参考。

## 环境

- DevEco Studio（内置 OpenHarmony SDK，compatibleSdkVersion 5.0.0(12) / API 12）
- 工程结构：Stage 模型，entry（HAP）+ 9 个 HAR（database / network / image / logger / embedding / vector / deepseek / conversation / yolo）
- 原生依赖：MindSpore Lite 2.11.0（官方仅有 ohos-aarch64 运行时）
- 开发/调试设备：Windows 上的 HarmonyOS 模拟器（x86_64）

## 一、CMake / NDK 层

### 1. CMake 相对路径算错，ninja 报 “missing and no known rule to make it”

- 现象：
  `ninja: error: 'D:/HmProject/embedding/src/libs/arm64-v8a/libmindspore-lite.so', needed by '.../libembedding.so', missing and no known rule to make it`（外层错误码 00308018 “Unknown Error” 只是包装，真实原因看 ninja 行）
- 原因：CMakeLists.txt 位于 `src/main/cpp`，`${CMAKE_CURRENT_SOURCE_DIR}/../../libs` 实际解析为 `src/libs`，而 .so 放在模块根目录 `libs/`。
- 解决：改为 `../../../libs/arm64-v8a/libmindspore-lite.so`（cpp → main → src → 模块根）。
- 涉及：embedding / yolo 的 `src/main/cpp/CMakeLists.txt`

### 2. `LOG_TAG` 与 hilog 宏冲突

- 现象：`static constexpr char LOG_TAG[] = "..."` 处报 `expected unqualified-id`
- 原因：`hilog/log.h` 内置 `#define LOG_TAG NULL`，变量名与宏撞名。
- 解决：变量改名（如 `EMBEDDING_LOG_TAG` / `YOLO_LOG_TAG`），LOGI/LOGE 宏同步引用新名。

### 3. MindSpore `Model::Build` 第 4 个参数要 `shared_ptr<Context>`

- 现象：`no known conversion from 'mindspore::Context' to 'const std::shared_ptr<Context>'`
- 解决：

  ```cpp
  auto ctx = std::make_shared<mindspore::Context>();
  auto &deviceList = ctx->MutableDeviceInfo();
  auto cpuInfo = std::make_shared<mindspore::CPUDeviceInfo>();
  cpuInfo->SetEnableFP16(false);
  deviceList.push_back(cpuInfo);
  model.Build(data, size, mindspore::kMindIR, ctx);
  ```

### 4. `MSTensor::Data()` 返回 `shared_ptr`，不能直接 `reinterpret_cast`

- 现象：`reinterpret_cast from 'std::shared_ptr<const void>' to 'const float *' is not allowed`
- 解决：先 `.get()` 再转：`reinterpret_cast<const float *>(outputs[0].Data().get())`

### 5. NAPI 异步完成回调返回类型必须是 `void`

- 现象：`no known conversion from 'napi_value (napi_env, napi_status, void *)' to 'napi_async_complete_callback'`
- 解决：`napi_create_async_work` 的完成回调声明为 `static void XxxComplete(napi_env, napi_status, void*)`，不能返回 `napi_value`。

## 二、依赖与模块解析

### 6. HAR 缺 `main` 入口，导致 “Cannot find module”

- 现象：ArkTS 编译报大量 `Cannot find module 'logger'/'database'/...`，同时伴随一批 “Use explicit types instead of any/unknown” 的连带错误；构建开头有 WARN：`Set either main or types, or both for this HSP/HAR module.`
- 原因：本地 HAR 的 `oh-package.json5` 没有声明包入口，编译器无法解析 `import ... from 'xxx'`。
- 解决：每个 HAR 的 `oh-package.json5` 增加 `"main": "./src/main/ets/index.ets"`。
- 经验：构建开头的 WARN 往往就是根因线索，先看再查报错。

### 7. `oh_modules` 没有依赖链接

- 现象：新增/变更本地 HAR 依赖后，模块仍解析失败。
- 原因：没有执行 ohpm 同步，根目录 `oh_modules` 为空。
- 解决：

  ```powershell
  $env:NODE_HOME = 'D:\DevEco_Stdio\DevEco Studio\tools\node'
  $env:Path = "$env:NODE_HOME;$env:Path"
  & "D:\DevEco_Stdio\DevEco Studio\tools\ohpm\bin\ohpm.bat" install
  ```

- 注意：ohpm 依赖 node，必须先把 `NODE_HOME` 指到 DevEco 自带的 node，否则报 `Failed to find the executable 'node'`。

## 三、ArkTS 严格模式

### 8. 对象字面量必须有显式类型（arkts-no-untyped-obj-literals）

- 现象：`Object literal must correspond to some explicitly declared class or interface`
- 场景与解决：
  - RDB 写入：`const values: relationalStore.ValuesBucket = { ... }`
  - DeepSeek 请求体：声明接口，例如 `export interface DeepSeekRequest { model: string; messages: Array<DeepSeekMessage>; temperature: number; stream: boolean }`

### 9. `List({ space: $r(...) })` 类型错误

- 现象：`Type 'Resource' is not assignable to type 'string | number'`
- 原因：该 SDK 中 `ListOptions.space` 只接受 `number | string`，不接受 Resource。
- 解决：使用数值（与 float 资源值保持一致），并注释说明 SDK 限制。

### 10. `Text` 没有 `maxWidth` 属性

- 现象：`Property 'maxWidth' does not exist on type 'TextAttribute'`
- 解决：改用 `constraintSize({ maxWidth: $r('...') })`。

## 四、构建产物与部署

### 11. 构建生成文件污染 git

- 现象：构建后多出 `**/BuildProfile.ets`、`.clangd`、`.clang-tidy`。
- 解决：在根 `.gitignore` 增加忽略规则：

  ```
  **/BuildProfile.ets
  .clangd
  .clang-tidy
  ```

### 12. 模拟器部署失败 code:9568347（ABI 不匹配）

- 现象：`error: install parse native so failed. In the module named entry, the Abi type supported by the device does not match the Abi type configured in the C++ project.`
- 原因：
  - Windows 的 HarmonyOS 模拟器是 **x86_64**；
  - 工程原生构建默认只有 **arm64-v8a**（hvigor 默认 ABI 就是 arm64-v8a）；
  - MindSpore Lite 官方只发布 ohos-aarch64 运行时，x86_64 没有官方库可用。
- 解决（双 ABI + 桩库回退）：
  1. `abiFilters: ["arm64-v8a", "x86_64"]` 加在模块 `build-profile.json5` 的 `buildOption.externalNativeOptions` 里。注意：**不能放 `targets`**，否则 schema 校验报错（00303038，提示 targets 只允许 name/config/source/resource/runtimeOS/output）；
  2. CMakeLists 按 `OHOS_ARCH` 分支：arm64-v8a 编译完整推理（链接 mindspore-lite），其余架构编译 `stub.cpp`（init/embed/detect 直接抛“该 ABI 不支持”）；
  3. ArkTS 侧初始化失败已有回退逻辑（MemoryService 检测失败后回退 `LocalHashEmbedding` 占位向量），模拟器上功能不崩溃。
- 验证：HAP 同时包含 `libs/arm64-v8a`（完整 embedding + mindspore-lite）与 `libs/x86_64`（桩 embedding），hdc 实测安装成功。
- 结论：模拟器上 AI 向量/RAG 用占位实现，真机（arm64）自动走完整推理。

## 五、命令行小贴士

- PowerShell 调用带空格的程序路径必须用 `&`：`& "D:\DevEco_Stdio\DevEco Studio\tools\node\node.exe" ...`
- 常用构建命令（与 DevEco 一致）：

  ```
  & "D:\DevEco_Stdio\DevEco Studio\tools\node\node.exe" "D:\DevEco_Stdio\DevEco Studio\tools\hvigor\bin\hvigorw.js" --mode module -p module=entry@default -p product=default -p requiredDeviceType=phone assembleHap --analyze=normal --parallel --incremental
  ```

- 排查顺序：先看构建开头 WARN（如 HAR main 缺失）→ 再看 ninja 真实错误 → 最后看 ArkTS 编译错误；很多 “any/unknown” 类报错是模块解析失败的连带现象。