# YOLOv8n 蔬菜识别模型

> 本模型仅用于个人学习、非商用场景。YOLOv8 遵循 Ultralytics AGPL-3.0 开源协议，使用请注意协议要求。

## 文件清单（models/yolov8n/）

| 文件 | 大小 | 说明 |
| --- | --- | --- |
| `yolov8n.pt` | 6.5 MB | Ultralytics 官方预训练权重（不纳入 git，可随时重新下载） |
| `yolov8n.onnx` | 12.3 MB | ONNX 导出格式（opset 12，输入 640×640），已用 onnxruntime 验证 |
| `yolov8n.ms` | 12.8 MB | MindSpore Lite 转换格式，供 C++/NDK 侧直接加载推理 |

下载地址：`https://github.com/ultralytics/assets/releases/download/v8.3.0/yolov8n.pt`

## 模型规格

- 输入：`[1, 3, 640, 640]` float32，RGB，0~255
- 输出：`[1, 84, 8400]` float32（不含 NMS 后处理）
  - 84 = 4（cx, cy, w, h）+ 80（COCO 类别置信度）
  - 8400 = 三种尺度的候选框数量（80×80 + 40×40 + 20×20）
- 后处理（C++ 侧实现）：置信度阈值过滤 → 类别得分取最大 → NMS 去重 → 坐标还原到原图尺寸

## 转换流程（已在本地完成）

```bash
# 1. pt -> onnx（本机 D:\pyenv 环境，Python 3.13 + ultralytics）
python -c "
from ultralytics import YOLO
YOLO('models/yolov8n/yolov8n.pt').export(format='onnx', imgsz=640, opset=12, dynamic=False, simplify=True)
"

# 2. onnx -> ms（MindSpore Lite 2.10.0 转换器，Windows 版位于 D:\tools）
converter_lite.exe --fmk=ONNX --modelFile=models/yolov8n/yolov8n.onnx --outputFile=models/yolov8n/yolov8n
```

## 验证结果

- onnxruntime（CPU）：输入/输出形状校验通过 `[1,3,640,640] -> [1,84,8400]`
- MindSpore Lite benchmark（CPU，随机输入）：加载成功，单次推理约 49ms（2 线程）

## C++/ArkTS 调用计划（后续实现）

1. 新建 `yolo` HAR 模块，包含 NDK C++ 工程：
   - 集成 MindSpore Lite runtime（`libmindspore-lite.so` + 头文件），C++ 侧加载 `yolov8n.ms`
   - 实现预处理（resize/letterbox + 归一化）、推理、后处理（阈值 + NMS）
   - 通过 NAPI 暴露给 ArkTS，如 `detect(pixelMap): Promise<DetectionResult[]>`
2. ArkTS 侧由 `image` HAR 读取图片 → 调用 `yolo` HAR 推理 → UI 展示检测框与类别

## 注意

预训练 YOLOv8n 只在 COCO 80 类上训练，其中蔬菜类仅 **broccoli（西兰花）** 和 **carrot（胡萝卜）** 两类。若要让应用识别更多蔬菜品种，需要后续用蔬菜数据集对模型做微调（fine-tune），再按上述流程重新导出 ONNX / MS。

---

# Jina Embeddings v2 base zh（中文文本向量模型）

> 用于功能 1：把对话中采集的健康信息向量化后存入本地向量数据库。
> 模型来源：HuggingFace `jinaai/jina-embeddings-v2-base-zh`（Apache-2.0，个人学习、非商用）。

## 文件清单（models/embedding/）

| 文件 | 大小 | 说明 |
| --- | --- | --- |
| `jina-embeddings-v2-base-zh-static.ms` | 645 MB | MindSpore Lite 格式（固定输入 1×256），C++/NDK 直接加载（不纳入 git） |
| `tokenizer.json` | 2 MB | BERT 分词器（C++ 侧分词用，已纳入 git） |
| `config.json` / `tokenizer_config.json` / `special_tokens_map.json` | 小 | 模型与分词器配置（已纳入 git） |

源 ONNX 位置：`D:\codexSpace\models\models--jinaai--jina-embeddings-v2-base-zh\snapshots\...\onnx\model.onnx`（641MB）

## 模型规格

- 输入：`input_ids [1, 256]` int64、`attention_mask [1, 256]` int64
- 输出：`last_hidden_state [1, 256, 768]` float32
- 句向量取法（C++ 侧实现）：取 `[CLS]` 位置或对非 padding 位置做 mean pooling，再 L2 归一化

## 转换命令（已在本地完成）

```bash
converter_lite.exe --fmk=ONNX --modelFile=<onnx 路径> \
  --outputFile=models/embedding/jina-embeddings-v2-base-zh-static \
  --inputShape='input_ids:1,256;attention_mask:1,256'
```

## 验证结果

- MindSpore Lite benchmark（CPU，seq=256 随机输入）：单次推理约 260ms（2 线程），加载与推理成功。

## C++/ArkTS 调用计划

1. `embedding` HAR 增加 NDK C++ 工程：加载 `.ms` + tokenizer（C++ 实现 BERT 分词）→ 推理 → 返回句向量，NAPI 暴露 `embed(text): Promise<number[]>`
2. ArkTS 侧 `EmbeddingManager.setProvider(napiProvider)` 切换到真实模型，替换当前占位实现（`LocalHashEmbedding`）
3. 模型部署方式：645MB 体积较大，后续可转 fp16（体积减半）或放入应用 rawfile / 首次启动从本地拷贝
