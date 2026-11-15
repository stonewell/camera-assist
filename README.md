# Camera Assist (帮拍相机 & 照片复盘)

> 教帮拍的人把人拍好，帮拍完的人把片修好。

**Camera Assist** 是一个专为旅行和日常人像帮拍场景设计的摄影辅助工具体系。针对"帮拍者不懂构图和光线"、"拍完选片废片多"等痛点，提供**拍摄时实时引导**与**拍后照片体检复盘**两套互补的应用，两端共用同一套底层规则引擎。

---

## 核心应用与开发方案

本项目包含两个主要应用，各自拥有详细的架构与开发规划文档：

| 应用 | 定位与核心能力 | 目标平台 | 开发方案文档 |
|---|---|---|---|
| **帮拍相机 (CameraApp)** | **实时引导相机**：自建取景器 + 原生系统成像管线，提供实时构图提示、光线站位指引、安全自动曝光补偿、**路人帮拍模式**（锁定构图 + 对齐引导）以及**语音播报提示**。 | iOS 18+ (iPhone) | [帮拍相机 iOS App 开发方案 v1.7](docs/camera-assist-app-plan.md) |
| **照片复盘 (ReviewApp)** | **事后构图体检与修复**：无论使用手机还是单反拍摄，拍完后均可进行构图体检、光线复盘，支持一键拉直与推荐裁切、生成旅行总结报告，并可通过深链接一键跳转帮拍相机重拍。 | iOS + 桌面端 (macOS / Windows / Linux) | [照片复盘应用开发方案 v1.3](docs/photo-review-app-plan.md) |

### 辅助调研、全局规划与归档资料

- **任务优先级与协同**：[研发任务优先级与双项目协同规划](docs/development-priorities.md) —— 制定了双应用 P0–P3 任务优先级、依赖关键路径图与排期对齐表。
- **功能调研**：[帮拍场景其他有效功能调研](docs/helper-mode-features-research.md) —— 调研了路人帮拍、表情口令卡、偏好卡、智能挑片、双机实时预览等竞品与用户痛点。
- **归档文档**：[docs/archive/](docs/archive/) —— 包含合并重构前的三份早期技术规划：
  - [构图规则引擎 (`composition-rule-engine-ios.md`)](docs/archive/composition-rule-engine-ios.md)
  - [原生相机能力利用 (`native-camera-leverage-ios.md`)](docs/archive/native-camera-leverage-ios.md)
  - [光线与站位建议 (`light-distance-advisor-ios.md`)](docs/archive/light-distance-advisor-ios.md)

---

## 代码仓库结构 (Monorepo)

```
camera-assist/
├─ docs/                              产品方案、开发规划、功能调研与历史归档 (archive/)
├─ core/                              Rust workspace（多端共用底层核心）
│  ├─ compose-core/                   ★ 规则引擎：纯 Rust，A–G 类 19 条构图与光线规则、仲裁器、20 组黄金测试向量
│  ├─ compose-ffi/                    UniFFI 绑定 → 生成 iOS/macOS 适用的 XCFramework 与 Swift Package
│  ├─ perception-onnx/                ★ ONNX 兼容感知契约（COCO-17 骨骼转 19 关节、人脸朝向与景别推断、模型许可证审计）
│  ├─ media-io/                       ★ 媒体变换数学（非破坏性裁剪、旋转内接矩形、EXIF 提取、XMP 侧车生成）
│  ├─ review-engine/                  ★ 相册审片复盘引擎（0-100 构图评分、废片自动修复配方、批处理撤销与剔除）
│  └─ compose-eval/                   ★ 离线评测与基准测试工具（20 组黄金向量自动评估、常驻 CI 第 11 步门禁）
├─ apple/                             Apple 生态工程
│  ├─ CameraApp/                      ★ 帮拍相机 iOS 主应用（取景预览、24MP 拍照、HUD 引导、语音播报、iOS 18 ControlWidget）
│  ├─ CameraAppClip/                  ★ 路人帮拍 App Clip（纯 Swift，零 Rust 依赖，包体 ~1.5MB，扫码对齐与成片回传）
│  ├─ ReviewApp/                      ★ 照片复盘 iOS 应用（PhotoReviewCoordinator + 可逆 PHAdjustmentData）
│  ├─ Packages/
│  │   ├─ ComposeKit/                 compose-ffi 上的 Swift 封装（值类型、Sendable，全量 20 golden vectors 文案对齐）
│  │   ├─ PerceptionKit/              实时感知调度、平滑、Vision 姿态与人脸、IMU 滤波、运动插值
│  │   ├─ CaptureKit/                 AVCaptureSession 管线、24MP 输出、旋转监听、热节流降帧（TASK-06 已完成）
│  │   └─ SyncKit/                    ★ 跨机通信：100% 纯 Swift E2EE、Curve25519+AES-GCM、传输抽象（TASK-10 已完成，零 Rust 依赖）
├─ desktop/                           
│  └─ review_flutter/                 ★ Flutter 桌面端审片应用（GridView.builder 网格、一键废片拯救、前后对比划块）
├─ shared/
│  ├─ config/Thresholds.json          统一规则阈值与后端覆盖配置（所有应用共用）
│  ├─ hints/                          多语言文案源文件（zh-Hans.json, en.json）
│  └─ models/models.json              桌面端 ONNX 模型清单（版本、SHA-256、许可证；scripts/audit-models.py 读取）
└─ fixtures/
   └─ golden/                         黄金测试向量（20 组 001–020 + schema.json；感知输入 → 预期判定，TASK-02/04 已完成）
```

### 全量交付状态（TASK-01 至 TASK-13 全部完成）

- **全量 13 项核心开发与门禁任务（TASK-01 至 TASK-13）全部交付通过**：
  - **`compose-core` 规则 A–G 闭环**：共 19 条构图、光线与距离规则，消费 `ctx.light` 与镜头内参；仲裁器防抖；20 组黄金测试向量 100% 精确匹配。
  - **`ComposeKit` 严格链接与 FFI 契约扩展**：`.binaryTarget` 严格链接 `ComposeCore.xcframework`；导出 `reload_config`、`analyze_still`、`reset` 与 `backend`。
  - **`CaptureKit` 24MP 完整采集**：透出 `CVPixelBuffer` 与 EXIF/相机内参；`RotationCoordinator` 真实 KVO 朝向监听；系统热节流 60→30fps 降帧与恢复。
  - **`PerceptionKit` 真实 Vision 与运动插值**：`VisionFrameProcessor` 多率感知调度；`FrameSyncHub` 运动线性插值与姿态补偿。
  - **`CameraApp` 取景与引导闭环**：`UserGuidanceHUD` 提示胶囊、水平仪、绿框与触觉；`VoicePrompter` 语音播报（节流与快门保护）；iOS 18 `ControlWidget` 快捷启动。
  - **`SyncKit` 纯 Swift E2EE 与 `CameraAppClip`**：零 Rust 依赖（包体 ~1.5MB 远低于 15MB 预算），Curve25519+AES-GCM，扫码对齐与免交接成片回传。
  - **`ReviewApp`、`review_flutter` 与 `compose-eval`**：相册可逆拉直裁切 (`PHAdjustmentData`)、Flutter 桌面审片网格与前后对比滑动、`compose-eval` 20 组黄金向量评测 100% 精确匹配。
  - **11 步自动化验证门禁**：`verify-all.sh` 涵盖格式、Clippy、单测、黄金向量、微基准、模型审计、App Clip 隔离测量、Swift Parity 比对、解码器审计、合成画质、`compose-eval` 自测。
- 逐项状态与详细任务序列见 [研发任务优先级与双项目协同规划 · 第 8 节](docs/development-priorities.md#8-修订后的待办任务序列)。

---

## 构建与开发指南 (Building with xtool & Cargo)

本项目支持在 Linux 与 macOS 跨平台环境下使用 `xtool` 与 Cargo 进行独立编译与质量验证。

### 环境依赖 (Prerequisites)
- **Rust Toolchain**: 包含 `cargo` 与 iOS 交叉编译 target (`rustup target add aarch64-apple-ios`)。
- **xtool**: 跨平台 SwiftPM iOS 编译工具（可在 Linux/macOS 上替代 Xcode 进行 SwiftPM 构建）。
- **Darwin Swift SDK**: 通过 `xtool sdk status` 确认已安装 iOS SDK。
- **Python 3**: 用于运行质量门禁与黄金向量校验脚本。

### 常用构建与开发命令 (Commands)

```bash
# 1. 编译 Rust compose-ffi iOS 静态库
make rust-ios
# (或执行 ./scripts/build-rust-ios.sh aarch64-apple-ios)

# 2. 构建路人帮拍 App Clip (纯 Swift，零 Rust 依赖)
cd apple/CameraAppClip && xtool dev build
# (或执行 make dev-camera-clip)

# 3. 构建帮拍相机主应用 (CameraApp)
cd apple/CameraApp && xtool dev build
# (或执行 make dev-camera-app)

# 4. 生成 UniFFI Swift 绑定与 C 头文件
make generate-bindings

# 5. 执行全量 10 步质量门禁验收 (包含 Rust 测试、App Clip 隔离与大小检查、黄金测试向量校验)
#    注意：其中多项当前是脚本自断言/源码字节统计，真实验收标准见 TASK-02
./scripts/verify-all.sh
# (或执行 make verify / make test)
```

---

## 核心设计原则

1. **规则唯一实现**：所有构图与光线规则均在 Rust `compose-core` 中实现并经过黄金测试向量验证，保证 iOS 实时端、iOS 复盘端、桌面复盘端的判定逻辑完全一致。
2. **一次只给一条提示**：实时帮拍取景时，通过内置仲裁器（防抖、优先级、冷却、静默）确保屏幕上始终最多只显示一条最关键的指导动作，不让帮拍者手忙脚乱。
3. **安全与非破坏性**：
   - 帮拍相机仅申请相册"仅添加"权限，路人帮拍先挑后存，不向相册写入废片；
   - 照片复盘应用从不覆盖原图（iOS 采用 PhotoKit 系统级可逆编辑，桌面端导出新文件或写入 XMP 侧车文件）。
4. **全面本地化与隐私优先**：所有画面分析、人体与人脸检测均在设备端本地神经网络引擎 / CPU / GPU 完成，不上传用户照片与生物特征。
