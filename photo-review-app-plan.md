# 照片复盘应用开发方案 v1.3（iOS + 桌面端 macOS / Windows / Linux）

> - **范围**：事后的照片复盘应用。**移动端只做 iOS（iPadOS 顺带支持）；桌面端跨平台，覆盖 macOS、Windows、Linux。**
> - **关系**：从帮拍相机方案（`camera-assist-app-plan.md`）中拆分出来；两者共用 Rust 规则核心 `compose-core`、阈值和文案。全项目研发优先级与排期对齐见 `development-priorities.md`。版本变化见附录 A。
> - **约定**：【待验证】表示需要 spike 确认（汇总在第 15 节）；尚未决定的事项汇总在第 2.3 节。文中代码为设计级示例，未经编译。

---

## 目录

1. 产品定义
2. 关键技术决策
3. 总体架构
4. 共享核心 compose-core（Rust）
5. 感知后端：Vision（Apple）与 ONNX（桌面）
6. 媒体读写 media-io
7. 复盘引擎 review-engine
8. iOS 应用
9. 桌面应用
10. 与帮拍相机的联动
11. 隐私、合规与许可证
12. 工程规范与发布
13. 测试与评测
14. 里程碑与团队
15. 待验证 spike 汇总
16. 风险
17. 后续路线图
18. 参考资料
- 附录 A：修订记录

---

## 1. 产品定义

### 1.1 定位

**一句话**：不管用什么相机拍，回来都可以给照片做一次"构图体检"，一键修正能修的问题，并学会"下次这样拍"。

| | 帮拍相机（`camera-assist-app-plan.md`） | 照片复盘应用（本文档） |
|---|---|---|
| 时机 | 拍摄时实时引导 | 拍完之后 |
| 平台 | iOS | iOS + macOS / Windows / Linux |
| 输入 | 实时画面 + IMU + 位置 | 照片库或文件夹里的照片（含 EXIF） |
| 价值 | 当场拍好 | 零迁移成本；覆盖任何相机（手机、微单、单反）；为帮拍相机导流 |

### 1.2 两端的分工

| | iOS | 桌面端 |
|---|---|---|
| 典型场景 | 旅途中、当天晚上翻看刚拍的照片 | 旅行回来后，在大屏上整理一整个旅行文件夹（几百到几千张） |
| 照片来源 | 系统照片库（PhotoKit）；从照片 App 分享进来 | 本地文件夹（JPEG、HEIC、PNG、RAW）；（v1.1）macOS 照片库 |
| 修正结果 | 非破坏性写回系统照片库，可在照片 App 中还原 | 导出新文件，或写 XMP 侧车文件；**从不覆盖原图** |
| 特有能力 | 一键跳转帮拍相机重拍 | 批量分析、批量修正、旅行报告 |

### 1.3 MVP 范围

**做：**
- 构图体检：复用帮拍相机的规则（裁切、位置、大小、头顶留白、脚悬空、视线留白、多人、广角近拍变形），外加静态图专用的**歪斜检测**。
- 光线复盘：根据 EXIF 的拍摄时间、GPS、曝光参数、（iPhone 照片的）拍摄方向，给出"这张是顶光 / 逆光，下次……"。
- 可修正问题的一键修正：拉直、推荐裁切（留白过多、贴边、头顶空太多）。
- "下次这样拍"图示卡片。
- 旅行报告：一组照片里最常见的问题统计 + 3 条最值得改进的建议。
- 桌面端：文件夹导入、后台批量分析、按问题筛选、批量修正、导出。
- iOS：最近照片体检、分享扩展、非破坏性写回、深链接到帮拍相机。

**不做（见第 17 节路线图）**：相似照片分组挑图、人脸质量打分、macOS 照片库、iOS 照片编辑扩展、Android、云同步、账号、生成式修图。

### 1.4 成功标准（Beta 阶段）

| 指标 | 目标 |
|---|---|
| 每条规则的离线精确率（每个感知后端分别统计） | ≥ 85% |
| 同一照片在 Vision 后端与 ONNX 后端的结论一致率 | ≥ 90% |
| 用户对一键修正结果的接受率（应用后没有撤销） | ≥ 70% |
| 桌面端：1000 张 24MP 照片的批量分析时间（中端笔记本，CPU） | ≤ 10 分钟【待验证】 |
| iOS：从复盘应用跳转帮拍相机的比例（看过"下次这样拍"的用户中） | 用于建立基线 |

---

## 2. 关键技术决策

### 2.1 决策一览

| 决策 | 选择 | 主要理由 |
|---|---|---|
| 共享核心语言 | **Rust**（`compose-core`） | 唯一能同时干净地服务 iOS（UniFFI → Swift）和三大桌面系统的选择；规则是纯逻辑，适合用 Rust 写 |
| iOS UI | **SwiftUI 原生** | PhotoKit 非破坏性编辑、分享扩展、深链接都需要原生代码；与帮拍相机团队技术栈一致 |
| 桌面 UI | **Flutter**（Dart）+ `flutter_rust_bridge` | 自绘渲染，三个系统表现一致；大图网格滚动性能稳定；Rust 绑定成熟 |
| iOS 感知后端 | Apple **Vision** | 与帮拍相机一致；使用神经网络引擎；不需要打包模型 |
| 桌面感知后端 | **ONNX Runtime**（Rust `ort` crate）+ 开源模型 | 三个系统通用；可以按系统选用硬件加速（CoreML / DirectML / CUDA / CPU） |
| 桌面本地存储 | SQLite（`rusqlite`） | 分析结果缓存、任务队列、修正记录 |

### 2.2 为什么不用其他方案

| 候选 | 不选的原因 |
|---|---|
| Tauri 2（Rust + 系统 WebView） | Linux 上的 WebKitGTK 在大图网格滚动时有已知的性能问题，近期仍有报告（单帧 40–90 ms），而图片网格正是本应用的核心界面 |
| Electron | 安装包和内存占用大；Rust 核心需要通过 Node 原生模块接入 |
| Qt（C++ / QML） | Rust 绑定不成熟；团队需要再学一套 C++ 技术栈 |
| Swift 跨平台（Swift on Windows / Linux） | 没有成熟的跨平台 UI；Vision 只在 Apple 平台可用，桌面端仍然需要另一套感知后端 |
| 桌面也用 Vision（只在 macOS） | 三个桌面系统必须一致，macOS 单独走 Vision 会让桌面端出现两套结果；先统一用 ONNX，macOS 走 CoreML 加速 |

### 2.3 决策记录与待决事项

| # | 事项 | 状态 | 内容与影响 |
|---|---|---|---|
| 1 | 帮拍相机是否也使用 Rust 核心 | **已决定：使用** | 规则只有一份实现；两个项目从同一周开始，共同完成 Rust 工具链和 XCFramework 流水线（14.3） |
| 2 | 桌面端是否上架 Mac App Store / Microsoft Store | **待决定**（建议首发不上架） | 首发用官网下载（签名 + 公证），商店版放到 v1.1。商店版有沙盒限制，影响文件夹访问方式（9.3） |

---

## 3. 总体架构

### 3.1 代码仓库结构（monorepo）

```
camera-assist/
├─ core/                                 Rust workspace
│  ├─ compose-core/                      ★ 规则、几何、分类器、光线模型、距离换算、仲裁器、静态图分析、报告、配置、文案键
│  ├─ compose-ffi/                       UniFFI 绑定 → Swift（XCFramework：iOS、iOS 模拟器、macOS + Swift Package）
│  ├─ perception-onnx/                   ONNX Runtime 推理：人体检测、姿态、实例分割、人脸、直线
│  ├─ media-io/                          解码（JPEG/PNG/HEIC/RAW 内嵌预览）、EXIF、缩略图、导出、XMP 写入
│  ├─ review-engine/                     扫描、任务队列、SQLite 缓存、旅行报告、批量修正
│  ├─ review-bridge/                     flutter_rust_bridge 绑定 → Dart（桌面端）
│  └─ compose-eval/                      Rust 命令行离线评测（ONNX 后端，三个桌面系统通用）
├─ apple/
│  ├─ CameraApp/                         帮拍相机（见 camera-assist-app-plan.md）
│  ├─ ReviewApp/                         照片复盘 iOS 应用
│  ├─ Packages/
│  │  ├─ ComposeKit/                     compose-ffi 的 Swift 封装（两个 iOS 应用共用）
│  │  ├─ PerceptionVision/               Vision 感知后端（两个 iOS 应用共用）
│  │  ├─ PerceptionKit/                  实时感知（帮拍相机专有）
│  │  ├─ CaptureKit/                     AVCaptureSession 与相机控件（帮拍相机专有）
│  │  └─ GuideKit/                       帮拍辅助：路人帮拍、语音播报（帮拍相机专有）
│  └─ Tools/
│     ├─ compose-eval-vision/            Swift 命令行离线评测（Vision 后端，macOS），报告格式与 Rust 版一致
│     └─ capture-replay/                 真机录制回放工具（帮拍相机专有）
├─ desktop/                              Flutter 桌面应用（macOS / Windows / Linux）
├─ shared/
│  ├─ config/Thresholds.json             规则阈值（带版本号，所有应用共用）
│  ├─ hints/zh-Hans.json, en.json        文案（所有应用共用；iOS 构建时生成 .strings）
│  └─ models/                            ONNX 模型 + 模型清单（版本、哈希、许可证）
└─ fixtures/
   ├─ golden/                            黄金测试向量（感知结果 → 期望的 finding）
   └─ eval-dataset/                      标注数据集（不进 Git，用对象存储）
```

### 3.2 分层

```
┌─────────────── iOS（SwiftUI） ───────────────┐   ┌──────────── 桌面（Flutter / Dart） ───────────┐
│ ReviewApp UI · 分享扩展 · PhotoKit · SwiftData │   │ 图库 · 网格 · 详情 · 批量 · 报告 · 导出           │
│ ImageIO（解码、EXIF）· Core Image（修正渲染）   │   └───────────────────┬─────────────────────────┘
└───────┬───────────────────────┬──────────────┘                       │ flutter_rust_bridge
   PerceptionVision        ComposeKit（Swift）                     review-bridge
   （Vision 感知）              │ UniFFI                                 │
        │                       ▼                                        ▼
        │              ┌──────────────────────── Rust ────────────────────────────────────┐
        └──感知结果──▶ │ compose-core（纯逻辑：规则、光线、距离、修正建议、报告聚合）          │  ← 两端共用
                       ├──────────────────────────────────────────────────────────────────┤
                       │ perception-onnx ── media-io ── review-engine（扫描、队列、SQLite） │  ← 仅桌面
                       └──────────────────────────────────────────────────────────────────┘
```

**关键边界**：
- `compose-core` 只接受"感知结果"（关节点、掩码摘要、人脸框、歪斜角、EXIF 摘要），不做任何图像推理、不读写文件。iOS 和桌面在规则层面的差别只来自感知后端。
- iOS 只链接 `compose-core`（经 `compose-ffi`）；解码、EXIF、缓存、编辑写回都用 Apple 系统框架完成。`perception-onnx`、`media-io`、`review-engine` 只用于桌面。

---

## 4. 共享核心 compose-core（Rust）

### 4.1 内容

`compose-core` 是两个应用唯一的规则实现。规则定义、阈值、优先级以 `camera-assist-app-plan.md` 第 7、8 节的算法规格为准；本应用在此基础上增加静态图专用的部分：

| 模块 | 内容 | 规格来源 | 使用方 |
|---|---|---|---|
| `model` | `Frame`、`Subject`、`Joint`、`MaskSummary`、`Finding`、`Action`、`Severity` | 相机方案 7.1、8.1 | 两者 |
| `geometry` | 线段与画框求交、外推 | 相机方案 8.3 | 两者 |
| `classify` | 景别、朝向（实时路径带迟滞；静态图不使用迟滞） | 相机方案 8.2 | 两者 |
| `rules` | A–G 类规则 | 相机方案 8.3 | 两者 |
| `light` | 太阳位置、光向分类、LightContext 融合 | 相机方案 7.9 | 两者 |
| `optics` | 视场角、距离换算（眼距 / 身高）、换焦段的步数 | 相机方案 7.8、8.3 F 类 | 两者 |
| `arbiter` | 合并、仲裁器、`LiveEngine`（实时入口） | 相机方案 8.4、8.6 | 帮拍相机 |
| `settings` | AutoSettingsPolicy | 相机方案 9 | 帮拍相机 |
| `still` | 静态图分析入口、歪斜规则、修正建议（拉直、裁切）、"下次这样拍"卡片生成 | 本文档 4.3 | 照片复盘 |
| `report` | 多张照片的问题聚合、旅行报告 | 本文档 7.4 | 照片复盘 |
| `config` | 读取 `shared/config/Thresholds.json`，叠加 `backendOverrides` | 相机方案 8.7、本文档 4.3、5.4 | 两者 |

`compose-core` 本身不依赖任何 FFI 框架：UniFFI 的派生宏通过 `uniffi` feature 条件启用（`compose-ffi` 打开该 feature）；`flutter_rust_bridge` 在 `review-bridge` 中通过镜像类型引用同一批结构。

### 4.2 对外接口（UniFFI 与 flutter_rust_bridge 共用的 API）

```rust
// compose-core/src/still.rs
#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
#[derive(Clone, Debug)]
pub struct StillInput {
    pub subjects: Vec<Subject>,          // 感知后端给出的所有人物
    pub horizon_deg: Option<f64>,        // 地平线角度（Vision 或直线检测给出）
    pub vertical_lines_deg: Vec<f64>,    // 画面中近似竖直的直线角度（建筑、电线杆）
    pub face_luma_ratio: Option<f64>,    // 人脸亮度 / 背景亮度
    pub ipd_px: Option<f64>,             // 正脸瞳距（像素），用于距离换算
    pub image_width_px: u32,
    pub image_aspect: f64,               // 宽 / 高
    pub exif: ExifSummary,
}

#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
#[derive(Clone, Debug)]
pub struct LatLon { pub lat: f64, pub lon: f64 }   // UniFFI 不支持元组，用记录类型

#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
#[derive(Clone, Debug)]
pub struct Rect { pub x: f64, pub y: f64, pub width: f64, pub height: f64 }

#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
#[derive(Clone, Debug)]
pub struct ExifSummary {
    pub taken_at_utc: Option<i64>,       // 秒；由 DateTimeOriginal + OffsetTimeOriginal 换算（4.3）
    pub location: Option<LatLon>,
    pub img_direction_deg: Option<f64>,  // GPSImgDirection（iPhone 会写入拍摄方向）
    pub exposure_time_s: Option<f64>,
    pub f_number: Option<f64>,
    pub iso: Option<f64>,
    pub focal_35mm: Option<f64>,         // FocalLengthIn35mmFilm
    pub camera_model: Option<String>,
}

#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
#[derive(Clone, Debug)]
pub struct Lesson {
    pub rule_id: String,
    pub reason_key: String,
    pub params: std::collections::HashMap<String, String>,
}

#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
#[derive(Clone, Debug)]
pub struct StillReport {
    pub findings: Vec<Finding>,          // 已按统一优先级排序
    pub fixes: Vec<FixSuggestion>,       // 可以一键修正的
    pub lessons: Vec<Lesson>,            // "下次这样拍"（文案键 + 参数）
    pub light: Option<LightContext>,
    pub score: f64,                      // 0–100，仅用于排序和报告，不展示为"颜值分"
}

#[cfg_attr(feature = "uniffi", derive(uniffi::Enum))]
#[derive(Clone, Debug)]
pub enum FixSuggestion {
    Straighten { angle_deg: f64 },
    Crop { rect: Rect, reason_key: String },          // 成片坐标；reason_key 为文案键
    StraightenAndCrop { angle_deg: f64, rect: Rect },
}

#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
#[derive(Clone, Debug)]
pub struct IssueSummary {
    pub rule: String,
    pub count: u32,
    pub ratio: f64,
}

#[cfg_attr(feature = "uniffi", derive(uniffi::Record))]
#[derive(Clone, Debug)]
pub struct TripReport {
    pub trip_id: Option<i64>,
    pub trip_name: Option<String>,
    pub total_photos: u32,
    pub portrait_photos: u32,
    pub top_issues: Vec<IssueSummary>,
    pub fixable_count: u32,
    pub lessons: Vec<Lesson>,
}

/// 配置是不可变对象，跨 FFI 以共享引用传递
#[cfg_attr(feature = "uniffi", derive(uniffi::Object))]
pub struct Config { /* 解析后的 Thresholds.json + 后端覆盖 */ }

#[cfg_attr(feature = "uniffi", uniffi::export)]
pub fn analyze_still(input: StillInput, cfg: Arc<Config>) -> StillReport { /* … */ }

#[cfg_attr(feature = "uniffi", uniffi::export)]
pub fn aggregate_report(items: Vec<StillReport>, cfg: Arc<Config>) -> TripReport { /* … */ }
```

帮拍相机使用的实时入口 `LiveEngine`（含分类器状态、迟滞和仲裁器）也在同一个 crate 里导出；复盘应用不使用它。

### 4.3 静态图专用规则与修正

| 规则 | 判定 | 修正建议 |
|---|---|---|
| `still.tilt` | 地平线可信时：\|地平线角度\| > 1.5°；没有地平线时：竖直线角度的加权中位数偏离 90° 超过 1.5°【待验证 spike R8】 | `Straighten`，裁掉旋转后的黑边 |
| `still.keystone` | 竖直线向上明显汇聚（仰拍导致楼歪） | 不提供修正（梯形校正会让人变形），只给"下次手机拿竖直" |
| 裁切类（`head.cut`、`limbCut.*`、`feet.floating`） | 与帮拍相机相同 | 不可修正，只给"下次这样拍" |
| `headroom`（太多）、`edge.crowd`、`scale`（太小） | 与帮拍相机相同 | `Crop`：在不切到人的前提下，按 4:3 / 原比例重新裁切；裁切后分辨率低于原图 50% 时不推荐 |
| `leadRoom`、`placement` | 与帮拍相机相同 | `Crop`：把主体移到三分线；同样受分辨率下限约束 |
| `level.roll`、`tilt.vertical` | 静态图没有 IMU，**不使用**，由 `still.tilt`、`still.keystone` 代替 | — |
| 光线类 | 光向需要拍摄方向：有 `GPSImgDirection` 时才判断顺光、侧光、逆光；没有时只用人脸亮度比判断"逆光脸暗" | 不可修正（提亮交给照片 App 或其他修图工具），只给"下次这样拍" |
| `distance.distortion` | 由 `focal_35mm` 换算视场角，再用眼距或身高估算距离 | 不可修正，只给"下次切 2× 后退" |

**拍摄时区**：只有 `DateTimeOriginal`、没有 `OffsetTimeOriginal` 时，用 GPS 坐标离线查时区（Rust `tzf-rs` 等离线时区库）【待验证 spike R10】；两者都没有时，不做太阳相关的判断。

**静态图专用阈值**（写在共享的 `shared/config/Thresholds.json` 中，帮拍相机不读取）：

```json
{
  "still": {
    "tiltMinDeg": 1.5,
    "tiltMaxAutoDeg": 8.0,
    "keystoneMinConvergeDeg": 3.0,
    "cropMinKeepRatio": 0.5,
    "cropAspects": ["original", "4:3"],
    "horizonMinConfidence": 0.6
  }
}
```

- `tiltMaxAutoDeg`：歪斜超过 8° 时通常是有意的倾斜构图，只提示、不推荐一键拉直。
- `cropMinKeepRatio`：裁切后保留的像素少于原图 50% 时不推荐裁切。

### 4.4 Swift 侧封装（ComposeKit）

- `compose-ffi` 用 UniFFI 生成 Swift 绑定，构建为 XCFramework（`aarch64-apple-ios`、`aarch64-apple-ios-sim`、`x86_64-apple-ios`，以及供 macOS 命令行工具使用的 `aarch64-apple-darwin`、`x86_64-apple-darwin`），封装为 Swift Package。
- `ComposeKit` 在生成的绑定之上提供 Swift 风格的 API（值类型、`Sendable`），两个 iOS 应用都只依赖 `ComposeKit`。
- UniFFI 尚未发布 1.0，API 可能随版本变化：**锁定版本**，升级单独排期。

---

## 5. 感知后端：Vision（Apple）与 ONNX（桌面）

### 5.1 统一的感知输出

两个后端都输出同一套结构（`Subject`、`MaskSummary`、人脸框、地平线、竖直线），由 `compose-core` 消费。

### 5.2 iOS：Vision 后端（PerceptionVision）

| 任务 | API |
|---|---|
| 人体姿态 | `VNDetectHumanBodyPoseRequest`（19 个关节） |
| 人物实例掩码 | `VNGeneratePersonInstanceMaskRequest` |
| 人脸 | `VNDetectFaceRectanglesRequest` |
| 地平线 | `VNDetectHorizonRequest` |
| 竖直线 | `VNDetectContoursRequest` + 线段拟合，或 Core Image 边缘检测 + 霍夫变换 |

与帮拍相机共用同一个 Swift Package，区别只是输入为静态图（1024 px 缩略图）。

### 5.3 桌面：ONNX 后端（perception-onnx）

| 任务 | 候选模型 | 说明 |
|---|---|---|
| 人体检测 + 实例分割 | RTMDet-Ins（OpenMMLab）、Mask R-CNN（torchvision） | **避免 AGPL 许可证的模型（如 Ultralytics YOLO 系列）**；权重许可证需要逐个确认【spike R1】 |
| 人体姿态 | RTMPose（COCO 17 点）、MoveNet MultiPose | 自上而下：先检测人，再对每个人估计姿态 |
| 人脸 | YuNet（OpenCV Zoo） | 体积小、CPU 上速度快 |
| 地平线、竖直线 | OpenCV 霍夫直线检测（`opencv` crate），或纯 Rust 实现 | 只需要角度，不需要分割 |

- **推理加速**：macOS 用 CoreML 执行提供程序；Windows 用 DirectML；Linux 有 NVIDIA GPU 时用 CUDA，否则用 CPU。所有系统都以 CPU 结果为准做验收。
- **模型清单**（`shared/models/manifest.json`）：每个模型记录版本、SHA-256、输入尺寸、许可证、来源链接；构建时校验。

### 5.4 关节点映射与后端差异

Vision 输出 19 个关节，COCO 模型输出 17 个，没有"颈部"和"根部"：

```rust
/// COCO 17 点 → 统一的 JointID
fn from_coco(kp: &[Keypoint; 17]) -> HashMap<JointId, Joint> {
    let mut m = HashMap::new();
    for (i, id) in COCO_ORDER.iter().enumerate() {   // nose, l/r eye, l/r ear, l/r shoulder, …
        if kp[i].conf >= 0.3 { m.insert(*id, kp[i].into()); }
    }
    // 颈部 = 两肩中点；根部 = 两胯中点（两侧都可信时才生成）
    if let (Some(l), Some(r)) = (m.get(&LShoulder), m.get(&RShoulder)) {
        m.insert(Neck, Joint::midpoint(l, r));
    }
    if let (Some(l), Some(r)) = (m.get(&LHip), m.get(&RHip)) {
        m.insert(Root, Joint::midpoint(l, r));
    }
    m
}
```

- 两个后端的置信度含义不同，**同一个阈值在两边的效果不一定一样**。`Thresholds.json` 支持按后端覆盖：

```json
{
  "backendOverrides": {
    "onnx": { "limbCut": { "minWristConf": 0.4 }, "head": { "noseNeckFactor": 1.0 } }
  }
}
```

- 每个后端单独跑评测、单独达到 85% 精确率门槛；同时统计两个后端在同一批照片上的结论一致率（目标 ≥ 90%）。

---

## 6. 媒体读写 media-io

### 6.1 解码

| 格式 | 桌面端方案 | 说明 |
|---|---|---|
| JPEG、PNG | `image` crate（或 `zune-jpeg`） | — |
| HEIC / HEIF | macOS：系统 ImageIO；Windows：系统 WIC（需要用户已安装 HEIF/HEVC 扩展）；Linux 及兜底：`libheif` | **HEVC 解码涉及专利问题**，随应用分发 HEVC 解码器之前需要法务评估【spike R3】 |
| RAW（DNG、CR3、NEF、ARW 等） | **只读取文件内嵌的 JPEG 预览图**（足够 1024 px 分析） | 不做 RAW 全解码；修正结果用 XMP 侧车文件表达（6.3） |
| 方向 | 统一按 EXIF Orientation 转正后再分析 | — |

- 系统解码器的调用方式：macOS 的 ImageIO 通过 `objc2` 系列 crate 调用；Windows 的 WIC 通过 `windows` crate 调用；都封装在 `media-io` 内，对上层只暴露统一的解码接口。
- 分析统一使用长边 1024 px 的缩略图；缩略图缓存在本地（Linux `~/.cache`、Windows `%LOCALAPPDATA%`、macOS `~/Library/Caches`），以"文件路径 + 修改时间 + 大小"为键。
- 色彩：解码时读取 ICC 色彩配置（iPhone 照片多为 Display P3），缩略图统一转换到 sRGB 用于分析和显示。

### 6.2 EXIF

用 Rust EXIF 库（如 `kamadak-exif`）读取 `ExifSummary` 所需字段（4.2）。iOS 端由 ImageIO 读取后转换成同一结构。

### 6.3 修正结果的输出（桌面端）

**原则：从不覆盖原图。**

| 原图格式 | 默认输出 | 可选输出 |
|---|---|---|
| JPEG、HEIC、PNG | 在原图旁边导出新文件 `原文件名_fixed.jpg`（JPEG 质量 92；保留 EXIF 和原 ICC 色彩配置；Orientation 重置为 1、尺寸更新），或导出到用户指定的文件夹；文件名已存在时追加序号 | 在新文件中嵌入 XMP 裁切信息 |
| RAW | **XMP 侧车文件**（与 Lightroom 兼容的 `crs:` 裁切字段），原 RAW 不动 | 同时导出一张 JPEG 预览 |

```xml
<!-- IMG_1234.xmp（侧车文件，示意） -->
<rdf:Description xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
    crs:HasCrop="True"
    crs:CropTop="0.042" crs:CropLeft="0.031"
    crs:CropBottom="0.968" crs:CropRight="0.955"
    crs:CropAngle="-1.8"
    crs:CropConstrainToWarp="0"/>
```

- `crs:Crop*` 的坐标基于**未旋转的传感器方向**，而我们的修正建议基于转正后的成片坐标；写入前要按 EXIF Orientation 做逆变换，角度的正负号也要相应调整【spike R4】。
- 如果侧车文件已经存在，只合并 `crs:Crop*` 字段，保留其他内容；写入前备份原侧车文件。
- 其他工具（如 darktable、Capture One）对 `crs:` 字段的支持程度不同【spike R4】。

### 6.4 修正结果的输出（iOS）

使用 PhotoKit 非破坏性编辑（从原方案迁移）：

```swift
// adjustmentData 格式：formatIdentifier = "<bundle id>.crop", formatVersion = "1"
// data = JSON { rotateDeg, cropRect }，用于下次在本应用中继续编辑
asset.requestContentEditingInput(with: options) { input, _ in
    guard let input, let url = input.fullSizeImageURL else { return }
    let output = PHContentEditingOutput(contentEditingInput: input)
    output.adjustmentData = PHAdjustmentData(formatIdentifier: fmt, formatVersion: "1", data: json)
    // Core Image：旋转 + 裁切 → 写入 output.renderedContentURL（保留原始元数据）
    PHPhotoLibrary.shared().performChanges {
        PHAssetChangeRequest(for: asset).contentEditingOutput = output
    }
}
```

- 用户可以在照片 App 中"复原"。
- 编辑后 Live Photo 是否保留（需要 `PHLivePhotoEditingContext`）、景深是否保留【spike R5】。
- 无法读取或修改用户在照片 App 中做过的编辑（格式不公开）：已经被编辑过的照片，只提供"复盘"，不提供"修正"。

---

## 7. 复盘引擎 review-engine

### 7.1 职责

| 职责 | iOS | 桌面 |
|---|---|---|
| 扫描照片来源 | Swift：PhotoKit | Rust：遍历文件夹、监听文件变化 |
| 任务队列 | Swift：`TaskGroup`，并发数 2 | Rust：后台线程池，并发数 = CPU 核数 − 1，可暂停和恢复 |
| 结果缓存 | Swift：SwiftData（照片数量少，不需要跨语言共享存储） | Rust：SQLite（7.2） |
| 报告聚合 | `compose-core::report`（经 `ComposeKit`） | `compose-core::report` |
| 批量修正 | —（iOS 逐张修正） | Rust：按筛选条件批量生成修正结果 |

两端缓存的"是否需要重新分析"判断一致：`compose-core` 版本、阈值版本、感知后端三者任何一个变化，都需要重新分析。

### 7.2 SQLite schema（简化）

```sql
CREATE TABLE trip (
  id INTEGER PRIMARY KEY, name TEXT, start_at INTEGER, end_at INTEGER,
  user_edited INTEGER NOT NULL DEFAULT 0      -- 用户合并、拆分、重命名过的旅行不再自动重算
);
CREATE TABLE photo (
  id INTEGER PRIMARY KEY,
  path TEXT NOT NULL UNIQUE,                   -- 文件绝对路径（桌面端只有文件来源）
  mtime INTEGER NOT NULL, size INTEGER NOT NULL,
  taken_at INTEGER, time_reliable INTEGER NOT NULL DEFAULT 1,
  lat REAL, lon REAL,
  trip_id INTEGER REFERENCES trip(id) ON DELETE SET NULL,
  is_portrait INTEGER,                         -- 是否含人物；非人像不进入报告
  analyzed_at INTEGER,
  analysis_key TEXT,                           -- compose-core 版本 + 阈值版本 + 后端；任一变化需重新分析
  score REAL
);
CREATE TABLE finding (
  id INTEGER PRIMARY KEY,
  photo_id INTEGER NOT NULL REFERENCES photo(id) ON DELETE CASCADE,
  rule TEXT NOT NULL, finding_id TEXT NOT NULL, severity INTEGER NOT NULL, metric REAL
);
CREATE TABLE batch (
  id INTEGER PRIMARY KEY, created_at INTEGER NOT NULL,
  output_mode TEXT NOT NULL,                   -- 'new_file' | 'xmp' | 'export_dir'
  undone_at INTEGER
);
CREATE TABLE fix (
  id INTEGER PRIMARY KEY,
  photo_id INTEGER NOT NULL REFERENCES photo(id) ON DELETE CASCADE,
  batch_id INTEGER REFERENCES batch(id) ON DELETE SET NULL,       -- 单张修正时也会生成一个只含一张的批次
  kind TEXT NOT NULL, params_json TEXT NOT NULL,
  output_path TEXT,                            -- 生成的新文件或侧车文件
  backup_path TEXT,                            -- 被修改的已有侧车文件的备份
  applied_at INTEGER NOT NULL
);
CREATE INDEX idx_finding_rule  ON finding(rule);
CREATE INDEX idx_finding_photo ON finding(photo_id);
CREATE INDEX idx_photo_trip    ON photo(trip_id);
CREATE INDEX idx_fix_batch     ON fix(batch_id);
CREATE INDEX idx_fix_photo     ON fix(photo_id);
```

撤销以批次为单位：删除该批次生成的新文件、用备份恢复侧车文件，然后标记 `batch.undone_at`。

### 7.3 旅行分组

- 按拍摄时间断档（间隔 > 12 小时）和地点跳变（> 100 km）自动分成"旅行"；用户可以合并、拆分、重命名。
- 没有 EXIF 时间的照片按文件修改时间处理，并标记为"时间不可靠"。

### 7.4 旅行报告

```
这次旅行（三亚 · 5 天 · 412 张，其中人像 168 张）
──────────────────────────────────────────
最常见的问题
  1. 脚没贴底边，腿显短        38 张（23%）   [查看]
  2. 膝盖被切                  21 张（13%）   [查看]
  3. 正午顶光                  19 张（11%）   [查看]
一键可修正：歪斜 27 张、留白过多 12 张          [全部修正]
下次这样拍（3 条最值得改进的）
  · 手机放到腰部、保持竖直，让脚贴住底边
  · 拍全身时退后一步，别让底边落在膝盖上
  · 中午带 TA 到树荫下，或者让 TA 背对太阳
  [用帮拍相机试试]（iOS）
```

- 报告只统计人像照片；问题按"出现次数 × 严重度"排序。
- "下次这样拍"直接复用帮拍相机的文案（`shared/hints`）。

---

## 8. iOS 应用

### 8.1 页面

| 页面 | 内容 |
|---|---|
| 首页 | 最近 24 小时（可调）的体检摘要；最近一次旅行的报告卡片；"开始体检"按钮 |
| 照片网格 | 只显示人像照片，每张带问题标签；按问题类型筛选；"只看可修正" |
| 详情 | 原图上标出问题（被切的关节、地平线、推荐裁切框）；修正前后对比；"应用修正"；"下次这样拍"卡片；"用帮拍相机重拍" |
| 旅行报告 | 见 7.4 |
| 设置 | 体检范围、语言、隐私说明 |

### 8.2 系统集成

| 能力 | 实现 |
|---|---|
| 照片库读取 | PhotoKit，优先"有限访问"；首次进入体检时申请 |
| 分享扩展 | 从照片 App 分享照片 → 体检（不需要照片库权限）。扩展内存有限（约 120 MB 量级【待验证 R11】），一次最多分析 5 张；收到的是照片副本而不是 PHAsset，**扩展内只能看报告，不能非破坏性写回**；要修正时引导用户打开主应用并授权照片库 |
| 非破坏性写回 | 6.4 |
| 跳转帮拍相机 | 第 10 节 |
| 后台分析 | 前台分析为主；可选用 `BGProcessingTask` 在充电时分析最近的照片【spike R6】 |

### 8.3 性能目标

| 项目 | 目标 |
|---|---|
| 单张分析（1024 px，Vision） | iPhone 12 上 < 150 ms |
| 100 张批量分析 | < 20 秒，期间界面不卡顿 |
| 内存 | 批量分析时 < 300 MB |

---

## 9. 桌面应用

### 9.1 页面

```
┌────────────────────────────────────────────────────────────────────┐
│ 侧栏            │  网格（虚拟化滚动，按需加载缩略图）              │ 详情面板   │
│ ─────────────  │  [筛选：全部 ▾] [问题：膝盖被切 ▾] [只看可修正]     │           │
│ 旅行            │  ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐           │ 大图 +     │
│  · 三亚 2026.09 │  │ ⚠ │ │ ✓ │ │ ⚠ │ │🔧 │ │ ✓ │ │ ⚠ │           │ 问题标注    │
│  · 京都 2026.04 │  └───┘ └───┘ └───┘ └───┘ └───┘ └───┘           │           │
│ 文件夹          │  ┌───┐ ┌───┐ ┌───┐ …                            │ 修正前/后   │
│  + 添加文件夹    │                                                  │ [应用修正]  │
│ 报告            │                                                  │ 下次这样拍  │
│ ─────────────  │  进度：分析中 312 / 412（可暂停）                    │           │
│ 设置            │                                                  │           │
└────────────────────────────────────────────────────────────────────┘
```

| 页面 | 内容 |
|---|---|
| 导入 | 添加文件夹（可多个）；选择是否包含子文件夹；首次导入后自动后台分析 |
| 网格 | 虚拟化滚动；问题标签；筛选（问题类型、严重度、是否可修正、相机型号、日期） |
| 详情 | 大图 + 问题标注；修正前后对比；手动微调裁切框和角度；"下次这样拍" |
| 批量修正 | 选中多张（或按筛选条件全选）→ 预览 → 选择输出方式（新文件 / XMP 侧车 / 导出文件夹）→ 执行；可以整批撤销（删除生成的新文件、恢复备份的侧车文件） |
| 旅行报告 | 7.4；可以导出为图片或 PDF 分享 |
| 设置 | 语言、推理加速方式（自动 / CPU / GPU）、并发数、缓存位置和大小、模型信息与许可证 |

### 9.2 Flutter 与 Rust 的边界

- Dart 层只负责界面和交互；扫描、解码、推理、规则、导出全部在 Rust 中完成。
- 通过 `flutter_rust_bridge` 暴露异步 API 和进度流（`Stream<Progress>`）。
- 缩略图由 Rust 生成并写入缓存目录，Dart 直接按文件路径加载，避免大块数据跨语言拷贝。
- 网格必须虚拟化（只渲染可见区域），并对缩略图解码做并发限制。

```rust
// review-bridge/src/api.rs（示意）
pub fn add_folder(path: String, recursive: bool) -> anyhow::Result<FolderId> { /* … */ }
pub fn start_analysis(scope: Scope, sink: StreamSink<Progress>) -> anyhow::Result<()> { /* … */ }
pub fn query_photos(filter: PhotoFilter, page: u32, page_size: u32) -> anyhow::Result<Vec<PhotoRow>> { /* … */ }
pub fn preview_fix(photo_id: i64, fix: FixSuggestion) -> anyhow::Result<String> { /* 返回预览图路径 */ }
pub fn apply_fixes(ids: Vec<i64>, output: OutputMode) -> anyhow::Result<BatchId> { /* … */ }
pub fn undo_batch(batch: BatchId) -> anyhow::Result<()> { /* … */ }
pub fn trip_report(trip_id: i64) -> anyhow::Result<TripReport> { /* … */ }
```

### 9.3 各系统的差异

| 项目 | macOS | Windows | Linux |
|---|---|---|---|
| 推理加速 | CoreML 执行提供程序 | DirectML | CUDA（有 NVIDIA GPU 时）/ CPU |
| HEIC 解码 | 系统 ImageIO | 系统 WIC（需要 HEIF/HEVC 扩展）；没有时提示安装 | `libheif`（法务评估后决定是否随包分发） |
| 安装包 | 签名 + 公证的 DMG | 签名的 MSIX 或 NSIS 安装程序 | AppImage、`.deb`、Flatpak |
| 自动更新 | 签名的更新包（如 Sparkle） | 安装程序自更新或 MSIX 更新 | Flatpak / 包管理器；AppImage 内置更新 |
| 文件访问 | 首发不进沙盒；商店版需要安全作用域书签 | 无限制 | Flatpak 需要文件访问门户（portal） |

### 9.4 性能目标（中端笔记本，CPU 推理）

| 项目 | 目标 |
|---|---|
| 单张分析（1024 px，ONNX：检测 + 分割 + 姿态 + 人脸 + 直线） | < 400 ms【spike R2】 |
| 1000 张 24MP JPEG 批量分析（含解码和缩略图） | ≤ 10 分钟 |
| 网格滚动（10000 张） | 三个系统都稳定在 60 fps【spike R7】 |
| 内存 | 批量分析时 < 1.5 GB |

---

## 10. 与帮拍相机的联动

| 联动 | 方式 |
|---|---|
| "用帮拍相机重拍"（iOS） | 打开帮拍相机的深链接 `https://<域名>/capture?mode=normal&focus=<规则 id>&src=review-ios`（参数定义见帮拍相机方案 12.1）。`focus` 取这张照片最严重的不可修正问题，帮拍相机会在取景页优先关注它；未安装时通用链接落到网页，引导到 App Store |
| 桌面端 | 旅行报告中显示帮拍相机的二维码（App Store 链接） |
| 规则和文案一致 | 所有应用使用同一版本的 `compose-core`、`Thresholds.json`、`shared/hints` |
| 数据 | 两个应用不共享照片数据，不需要账号 |

---

## 11. 隐私、合规与许可证

### 11.1 隐私

| 项目 | 措施 |
|---|---|
| 照片、人脸、人体数据 | 全部在本地处理，不上传；不保存人脸特征 |
| 桌面端联网 | 只有自动更新和（用户同意时的）匿名埋点会联网；模型随安装包分发，离线可用 |
| iOS 照片库 | 优先有限访问；只在用户确认后写回 |
| 埋点 | 默认关闭（桌面端）/ 首次询问（iOS）；只上报事件和数值，不上报图片、文件名、路径、坐标 |

### 11.2 许可证（上线前必须完成审查）

| 组件 | 风险 | 处理 |
|---|---|---|
| 模型权重 | 代码许可证（如 Apache-2.0）不一定覆盖预训练权重；部分模型（如 Ultralytics YOLO）是 AGPL | 逐个确认权重许可证并记录在模型清单中；不使用 AGPL 模型【spike R1】 |
| HEVC / HEIC 解码 | HEVC 有专利池；`libheif`、`libde265` 为 LGPL | 优先使用系统解码器；随包分发前做法务评估【spike R3】 |
| ONNX Runtime | MIT | 保留许可证声明 |
| OpenCV（如使用） | Apache-2.0 | 保留许可证声明 |
| Flutter、Rust 依赖 | 大多为 BSD / MIT / Apache | CI 中用 `cargo-deny` 和 Flutter 许可证工具检查，禁止 GPL/AGPL 依赖 |
| 第三方许可证页面 | — | 应用内"关于 → 开源许可证" |

### 11.3 中国大陆

- iOS：App 备案；隐私政策符合 PIPL；强调照片和人脸只在本地处理。
- 桌面端：官网下载需要遵守软件分发的相关要求；不涉及生成式 AI，不需要算法备案。

---

## 12. 工程规范与发布

| 项目 | 约定 |
|---|---|
| Rust | stable 工具链，锁定版本；`clippy`、`rustfmt`；`cargo-deny` 检查许可证和漏洞 |
| UniFFI | 锁定版本；生成的 Swift 代码不手改；XCFramework 由 CI 构建并发布为 Swift Package |
| Flutter | 锁定 Flutter 版本；`flutter_rust_bridge` 代码生成由 CI 校验是否与源码一致 |
| Swift | Swift 6 严格并发；`ComposeKit`、`PerceptionVision` 由两个 iOS 应用共用 |
| 共享配置 | `Thresholds.json`、`shared/hints` 带版本号；任何修改都要跑全部后端的评测 |
| CI 矩阵 | macOS（arm64）、Windows（x64）、Linux（x64，Ubuntu 22.04/24.04）：Rust 单元测试 + 黄金向量 + 桌面构建；macOS 上额外构建 iOS XCFramework 和两个 iOS 应用 |
| 评测门禁 | `compose-eval`（Rust，ONNX 后端，所有系统）和 `compose-eval-vision`（Swift，Vision 后端，macOS）跑同一个固定数据集；任何规则精确率 < 85%，或两份报告对比得到的跨后端一致率 < 90%，即失败 |
| 发布 | iOS：TestFlight → App Store；桌面：内测通道 → 正式通道，三个系统同时发版 |
| 代码签名 | Apple Developer ID + 公证；Windows 代码签名证书（建议 EV，减少 SmartScreen 警告）；Linux 包签名 |

---

## 13. 测试与评测

### 13.1 黄金测试向量

- `fixtures/golden/*.json`：每个用例包含"感知结果（关节、掩码摘要、EXIF …）→ 期望的 finding 和修正建议"。
- Rust（`compose-core`）、Swift（`ComposeKit` 封装）都必须通过同一组用例；帮拍相机的实时用例（带时间序列的仲裁器场景）也放在同一目录。

### 13.2 离线评测（compose-eval）

```
# ONNX 后端（Rust，macOS / Windows / Linux）
compose-eval --images ./dataset --labels labels.json \
             --config shared/config/Thresholds.json --report onnx.json --html onnx.html

# Vision 后端（Swift，macOS；与帮拍相机共用）
compose-eval-vision --images ./dataset --labels labels.json \
                    --config shared/config/Thresholds.json --report vision.json --html vision.html

# 跨后端一致率
compose-eval diff vision.json onnx.json
```

- 数据集：复用帮拍相机的标注集（300–500 张旅拍人像），再补充：微单和单反照片、RAW 内嵌预览、横构图、歪斜照片、建筑仰拍（用于 `still.tilt`、`still.keystone`）。
- 指标：每条规则、每个后端的精确率和召回率；两个后端的一致率；修正建议的人工接受率（摄影师判断推荐的裁切和拉直是否合理）。

### 13.3 端到端测试

| 平台 | 方法 |
|---|---|
| iOS | XCUITest：体检、筛选、修正、复原、分享扩展、深链接 |
| 桌面 | Flutter 集成测试：导入文件夹、批量分析、筛选、批量修正、整批撤销、导出；三个系统都跑 |
| 文件安全 | 专项测试：任何操作后原图的哈希值都不变；XMP 合并不丢失已有字段；磁盘满、权限不足、文件被占用时不损坏数据 |

### 13.4 性能测试

按 8.3、9.4 的目标，在基准设备上测量：iPhone 12；MacBook Air（M1）；Windows 中端笔记本（无独显）；Linux（Ubuntu 24.04，Intel 核显 + NVIDIA 独显各一台）。

---

## 14. 里程碑与团队

### 14.1 团队

| 角色 | 人数 | 职责 |
|---|---|---|
| Rust 核心工程师 | 1.5 | `compose-core`（与帮拍相机的工程师 B 共同实现规则 A–G）、`compose-ffi` 与 XCFramework 流水线、`perception-onnx`、`media-io`、`review-engine` |
| iOS 工程师 | 1 | iOS 应用、`ComposeKit` 封装、PhotoKit、分享扩展（可与帮拍相机团队共享 `PerceptionVision`） |
| Flutter 工程师 | 1 | 桌面应用 UI、三个系统的打包与发布 |
| 算法 / 评测 | 0.5 | 模型选型与转换、阈值的后端覆盖、`compose-eval` 的 ONNX 后端、数据集补充（与帮拍相机的算法工程师协作） |
| 设计 | 0.5 | 两端界面、报告、"下次这样拍"卡片 |
| 测试 | 0.5（从 P2 起） | 三个桌面系统 + iOS 的测试、文件安全专项 |

### 14.2 排期（18 周）

| 阶段 | 周 | 内容 | 退出标准 |
|---|---|---|---|
| **P0 基础与验证** | W1–2（与帮拍相机 M0 同一周开始） | Rust workspace、`compose-ffi` → XCFramework 流水线（与帮拍相机共同完成）、CI 矩阵；`compose-core` 骨架与黄金向量格式；spike R1、R2、R3、R7、R9 | 模型和许可证确定；单张 ONNX 分析 < 400 ms；Flutter 网格在 Linux 上滚动达标 |
| **P1 共享核心** | W3–10 | W3–4：`model`、`geometry`、`classify`、`config`、`compose-ffi` + `ComposeKit`；W5–7：规则 A–D、合并、仲裁器（与帮拍相机 M2 同步）；W7–8：`still`、`report`；W8–10：`light`、`optics`、规则 E–G、`settings`（与帮拍相机 M4 同步）；黄金向量贯穿全程 | Rust 与 Swift 都通过全部黄金向量；帮拍相机 M2、M4 按时接入 |
| **P2 桌面引擎** | W6–11 | `perception-onnx`（检测、分割、姿态、人脸、直线，三个系统的加速）、`media-io`（解码、EXIF、缩略图、导出、XMP）、`review-engine`（扫描、队列、SQLite、旅行分组、批次撤销） | 1000 张照片批量分析达标；文件安全专项测试通过 |
| **P3 应用** | W8–14 | 桌面：导入、网格、详情、批量修正、报告、设置；iOS：首页、网格、详情、PhotoKit 写回、分享扩展、深链接、报告 | 两端主流程走通；`compose-eval` 两个后端都达到 85% 精确率、一致率 ≥ 90% |
| **P4 发布准备** | W15–18 | 三个系统的签名、公证、安装包、自动更新；许可证页面；性能与内存优化；内测（每个平台 20 名用户）；App Store 审核 | 达到 1.4 节的成功标准；内测崩溃率 < 0.5% |

### 14.3 与帮拍相机的排期关系

| 周 | 本项目 | 帮拍相机 | 共同交付 |
|---|---|---|---|
| W1–2 | P0 | M0 | Rust workspace、`compose-ffi` → XCFramework 流水线、spike R9（= 相机 spike #22） |
| W3–4 | P1 前段 | M1（感知） | Rust 工程师先完成 `model`、`geometry`、`classify`、`config` 和 `ComposeKit` 骨架 |
| W5–7 | P1 中段 | M2（构图规则） | 规则 A–D、合并、仲裁器（Rust 工程师 + 相机工程师 B） |
| W8–10 | P1 后段 | M4（光线与距离） | `light`、`optics`、规则 E–G、`settings` |

- 静态图专用部分（`still`、`report`）只有本项目使用，排在 W7–8，不阻塞帮拍相机。
- 共同交付项延期会同时影响两个项目，每周同步一次进度；黄金向量是两边的验收依据。

---

## 15. 待验证 spike 汇总

| # | 验证项 | 方法 | 影响 | 阶段 |
|---|---|---|---|---|
| R1 | 候选模型（检测、实例分割、姿态、人脸）的权重许可证；ONNX 转换后的精度与 Vision 的差距 | 许可证审查 + 在标注集上对比 | 模型选型 | P0 |
| R2 | 中端笔记本 CPU 上单张分析耗时；三个系统硬件加速的收益与稳定性 | 基准测试 | 批量分析时间目标 | P0 |
| R3 | HEIC 在 Windows（WIC）和 Linux（libheif）上的解码方案及专利、许可证风险 | 法务 + 技术验证 | 是否随包分发解码器 | P0 |
| R4 | XMP `crs:` 裁切字段在 Lightroom、darktable、Capture One 中的兼容性；按 EXIF Orientation 做坐标逆变换后结果是否正确 | 实测（含竖拍 RAW） | RAW 修正结果的可用范围 | P2 |
| R5 | iOS 非破坏性编辑后 Live Photo 和景深是否保留（原相机方案 spike #16） | 真机 | iOS 修正的适用范围 | P3 |
| R6 | iOS `BGProcessingTask` 在充电时后台分析照片的可行性与系统限制 | 真机 | 是否提供后台体检 | P3 |
| R7 | Flutter 桌面在 Linux（Intel 核显、NVIDIA）、Windows 上 10000 张缩略图网格的滚动性能 | 原型 | 桌面 UI 技术选型是否成立 | P0 |
| R8 | 静态图歪斜估计（地平线 + 竖直线）的准确率（原相机方案 spike #7） | compose-eval | 是否默认推荐拉直 | P1 |
| R9 | UniFFI 生成的 Swift 绑定在帮拍相机实时路径（15 fps）上的调用开销与 Swift 6 并发兼容性 | 原型 + Instruments | 共用 Rust 核心在实时路径上是否可行（与帮拍相机 spike #22 合并） | P0 |
| R10 | 没有 `OffsetTimeOriginal` 的照片，按 GPS 离线推断时区的准确率；非 iPhone 照片中 `GPSImgDirection` 的覆盖率 | 数据集统计 | 光线复盘的覆盖范围 | P1 |
| R11 | iOS 分享扩展的内存上限下，Vision + `compose-core` 一次能分析几张照片；从照片 App 分享时能拿到的元数据（EXIF、GPS 是否被剥离） | 真机 | 分享扩展的功能范围 | P3 |

---

## 16. 风险

| 风险 | 应对 |
|---|---|
| ONNX 模型的效果明显不如 Vision，两端结论不一致 | 按后端覆盖阈值；一致率作为 CI 门禁；必要时桌面端减少依赖精细关节的规则 |
| 模型权重许可证不允许商用 | P0 先完成审查；准备至少两个候选；必要时用自有数据微调开源许可的模型 |
| HEIC 解码的专利问题 | 优先使用系统解码器；Linux 上提供"请安装系统 HEIF 支持"的引导 |
| 三个桌面系统的打包、签名、更新成本高 | 首发不上商店；统一的 CI 发布流水线；Linux 先只提供 AppImage + Flatpak |
| 修改用户文件造成数据损失 | 从不覆盖原图；侧车文件写前备份；整批撤销；文件安全专项测试 |
| Rust 在团队中的学习成本 | Rust 核心工程师主导；`compose-core` 保持简单的数据结构和纯函数；Swift / Dart 两侧只做薄封装 |
| UniFFI、flutter_rust_bridge 升级带来的破坏性变化 | 锁定版本；升级单独排期并跑全部黄金向量 |
| 用户觉得"体检"是在挑刺，体验负面 | 文案以"下次这样拍"为主，不展示分数；先展示可以一键修好的问题 |

---

## 17. 后续路线图

| 版本 | 内容 |
|---|---|
| v1.1 | 相似照片分组 + 自动挑出最佳（连拍、多张相近照片）；人脸质量打分（iOS 用 `VNDetectFaceCaptureQualityRequest`，桌面用开源模型）；macOS 照片库支持（通过 Swift 插件接入 PhotoKit）；iOS 照片编辑扩展（在照片 App 中直接使用）；Mac App Store / Microsoft Store 版本 |
| v1.2 | 背景穿头检测（与帮拍相机路线图一致）；路人入画检测；报告的历史趋势（"你的膝盖裁切问题比上次旅行少了 40%"） |
| V2 | Android；可选的跨设备同步（需要账号与隐私评估）；生成式修图（如消除路人，需要合规评估） |

---

## 18. 参考资料

- [研发任务优先级与双项目协同规划（本仓库）](development-priorities.md)
- [帮拍相机 iOS 开发方案（本仓库）](camera-assist-app-plan.md)
- [帮拍场景其他有效功能调研（本仓库）](helper-mode-features-research.md)
- [Linux Graphics Issues – Tauri](https://v2.tauri.app/develop/debug/linux-graphics/)
- [webkit-renderer-repaint-lag – xnmp/tauri-explorer #1057](https://github.com/xnmp/tauri-explorer/issues/1057)
- [Linux WebKitGTK performance pass – takasurazeem/chaff #55](https://github.com/takasurazeem/chaff/issues/55)
- [Track Linux scrolling lag on WebKitGTK – marlin #23](https://github.com/StirlingMarketingGroup/marlin/issues/23)
- [WebKit2GTK 2.40 causes Tauri app to render slowly – tauri #7021](https://github.com/tauri-apps/tauri/issues/7021)
- [mozilla/uniffi-rs](https://github.com/mozilla/uniffi-rs)
- [Rust on iOS: XCFramework & Swift Package Packaging – Stadia Maps](https://stadiamaps.com/blog/ferrostar-building-a-cross-platform-navigation-sdk-in-rust-part-2/)
- [ianthetechie/uniffi-starter](https://github.com/ianthetechie/uniffi-starter)
- [RTMPose paper – arXiv](https://arxiv.org/abs/2303.07399)
- [rtmlib – RTMPose without mmcv](https://github.com/Tau-J/rtmlib)
- [RTMPose checkpoint license question – mmpose #3273](https://github.com/open-mmlab/mmpose/issues/3273)
- [RTMPose AIC-COCO checkpoint license – mmpose #3277](https://github.com/open-mmlab/mmpose/issues/3277)

---

## 附录 A：修订记录

| 版本 | 变化 |
|---|---|
| v0.1 | 从帮拍相机方案的"B 轨：照片复盘"迁移内容，列出待决问题 |
| v1.0 | 确定平台范围（iOS + macOS / Windows / Linux）；技术选型：Rust 共享核心、SwiftUI、Flutter 桌面、Vision / ONNX 双感知后端；完整开发方案 |
| v1.1 | 帮拍相机决定共用 Rust 核心；排期与帮拍相机对齐 |
| v1.2 | 两份方案联合评审后的修正与润色 |
| v1.3 | 开发方案深化评审后的问题修复（见下表） |

### v1.2 修正明细

| 类别 | 修正 | 位置 |
|---|---|---|
| 接口缺陷 | UniFFI 不支持元组：`lat_lon: Option<(f64, f64)>` 改为 `LatLon` 记录；`&Config` 改为 `Arc<Config>`（UniFFI Object）；`compose-core` 的 FFI 派生宏改为 feature 条件启用，核心本身不依赖 FFI 框架 | 4.1、4.2 |
| 架构矛盾 | 分层图写 iOS 使用 `media-io`，而 6.2 写 iOS 用 ImageIO；缓存写 iOS 通过 Rust 访问 SQLite。统一为：iOS 只链接 `compose-core`，解码、EXIF、缓存（SwiftData）、写回都用系统框架 | 3.2、7.1 |
| 命名统一 | 评测工具与帮拍相机统一：`compose-eval`（Rust，ONNX）+ `compose-eval-vision`（Swift，Vision）+ `compose-eval diff` 计算一致率；实时入口统一为 `LiveEngine` | 3.1、4.2、12、13.2 |
| 共享核心 | 增加 `optics`（距离换算）与 `settings` 模块，与帮拍相机的模块划分一致；`StillInput` 增加距离换算需要的瞳距和图像宽度 | 4.1、4.2 |
| 配置 | 补充静态图专用阈值 `still` 一节（歪斜上下限、裁切保留比例等） | 4.3 |
| 构建 | XCFramework 补充 macOS 切片（供 `compose-eval-vision` 等命令行工具使用） | 3.1、4.4 |
| 数据安全 | `crs:Crop*` 坐标基于未旋转的传感器方向，写入前需要按 Orientation 逆变换；导出保留 ICC 色彩配置；文件名冲突追加序号 | 6.1、6.3 |
| 数据模型 | SQLite schema 补齐主键、批次表（支持整批撤销）、旅行外键、"时间不可靠"和"用户编辑过的旅行"标记 | 7.2 |
| iOS 限制 | 分享扩展内存有限、收到的是照片副本，不能非破坏性写回；改为扩展内只看报告，修正需要回到主应用；新增 spike R11 | 8.2、15 |
| 联动 | 深链接参数与帮拍相机方案 12.1 统一（`mode`、`focus`、`src`） | 10 |
| 排期 | P1 拆成与帮拍相机 M2、M4 同步的阶段，修正"P1 在 W7 前交付 A–G"与"E–G 在 W8–10 交付"的矛盾；新增两项目的周对照表 | 14.2、14.3 |
| 结构 | 文档头精简；第 2.3 节改为决策记录与待决事项；新增本附录 | 文档头、2.3、附录 A |

### v1.3 修正明细

| 类别 | 修正 | 位置 |
|---|---|---|
| 排期矛盾 | 修正 14.2 阶段表中 P0 写为 `W1–3` 的错误，统一为 `W1–2`，与 14.3 对照表和帮拍相机 M0 保持一致 | 14.2 |
| 类型补全 | 在 4.2 中正式补齐 `Rect`、`Lesson`、`IssueSummary`、`TripReport` 的 UniFFI Record 定义，消除外部未定义类型 | 4.2 |
| 数据库健全 | `fix` 表增加 `batch_id` 外键级联定义，新增 `idx_fix_batch` 与 `idx_fix_photo` 索引，避免批量撤销与详情查询全表扫描 | 7.2 |
| 验证项标记 | 静态图 `still.tilt` 与拍摄时区离线推断补齐 `【待验证 spike R8】` 与 `【待验证 spike R10】` 标签 | 4.3 |
| 一致性 | 仓库结构补齐 Apple 侧专有 Package（`CaptureKit`、`PerceptionKit`、`GuideKit`）与 `capture-replay` 工具 | 3.1 |
| 规范引用 | `config` 模块的规格来源补充引用相机方案 8.7 与本文档 4.3 | 4.1 |
