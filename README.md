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
│  ├─ compose-core/                   ★ 规则引擎：纯 Rust，已实现规则 A–D（12 条）；几何、光线、仲裁器等按设计规格逐步补齐
│  ├─ compose-ffi/                    UniFFI 绑定 → 生成 iOS/macOS 适用的 XCFramework 与 Swift Package（Swift 侧尚未链接，见 TASK-01）
│  ├─ perception-onnx/                （计划中）ONNX Runtime 推理（桌面端人体检测、分割、姿态、人脸与直线检测）
│  ├─ media-io/                       （计划中）桌面端媒体读写（解码、EXIF、缩略图缓存、JPEG 导出、XMP 侧车文件）
│  ├─ review-engine/                  （计划中）桌面端复盘引擎（文件夹扫描、后台任务队列、SQLite 缓存、旅行分组）
│  ├─ review-bridge/                  （计划中）flutter_rust_bridge 绑定 → 供 Flutter 桌面端调用
│  └─ compose-eval/                   （计划中）Rust 命令行评测工具（ONNX 后端）
├─ apple/                             Apple 生态工程
│  ├─ CameraApp/                      ★ 帮拍相机 iOS 主应用（当前为静态文字占位，端到端未接线）
│  ├─ CameraAppClip/                  ★ 路人帮拍 App Clip（当前为 Color.black 桩）
│  ├─ ReviewApp/                      （计划中）照片复盘 iOS 应用（SwiftUI + PhotoKit 非破坏性写回 + 分享扩展）
│  ├─ Packages/
│  │   ├─ ComposeKit/                 compose-ffi 上的 Swift 薄封装（值类型、Sendable，双 iOS 应用共用）
│  │   ├─ PerceptionVision/           （计划中）Vision 感知后端（双 iOS 应用共用）
│  │   ├─ PerceptionKit/              实时感知调度、平滑、IMU、定位、天气（帮拍相机专有）
│  │   ├─ CaptureKit/                 AVCaptureSession 管线、24MP 输出、相机控制控件、热节流降帧（帮拍相机专有，TASK-06 已完成）
│  │   ├─ GuideKit/                   （计划中）帮拍辅助：路人帮拍模式、语音播报（帮拍相机专有）
│  │   └─ SyncKit/                    ★ 跨机通信：100% 纯 Swift E2EE、Curve25519+AES-GCM、传输抽象（TASK-10 已完成，零 Rust 依赖）
│  └─ Tools/                          （计划中）
│      ├─ compose-eval-vision/        macOS 命令行离线评测工具（Vision 后端）
│      └─ capture-replay/             真机录制数据回放工具
├─ desktop/                           （计划中）Flutter 桌面端应用（macOS / Windows / Linux 跨平台 UI）
├─ shared/
│  ├─ config/Thresholds.json          统一规则阈值与后端覆盖配置（所有应用共用）
│  ├─ hints/                          多语言文案源文件（zh-Hans.json, en.json）
│  └─ models/models.json              桌面端 ONNX 模型清单（版本、SHA-256、许可证；scripts/audit-models.py 读取）
└─ fixtures/
   ├─ golden/                         黄金测试向量（20 组 001–020 + schema.json；感知输入 → 预期判定，TASK-02/04 已完成）
   └─ eval-dataset/                   （计划中）离线标注测试数据集
```

### 当前实现状态（2026-11-03）

- **核心基座与规则全量交付（TASK-01、TASK-02、TASK-03、TASK-04、TASK-06、TASK-10）**：
  - **`compose-core` 规则 A–G 闭环**：共 19 条构图、光线与距离规则（`light.backlit`, `light.harsh_top`, `light.flat_front`, `light.side_harsh`, `distance.distortion`, `distance.ultra_wide_edge`, `light.low_light` 等），实际消费 `ctx.light` 与镜头内参；支持 `enterDelayOverride` 仲裁器延迟覆盖与 glob 匹配；Merger 冲突焦段去重与 HFOV 范围安全（TASK-04）。暂缓规则：`light.sun_in_frame`、`lens.smudge`、`distance.fill_range`。
  - **20 组黄金测试向量**：`fixtures/golden`（`001`–`020`），Rust 检验器与 Swift 模式校验均实现 exact finding-set parity 100% 通过（TASK-02/04）。
  - **`ComposeKit` 严格链接**：通过 `.binaryTarget` 链接 `ComposeCore.xcframework` 并禁止静默 mock（TASK-01）。
  - **`CaptureKit` 24MP 完整采集**：透出未压缩 `CVPixelBuffer` 与完整 EXIF/相机内参/曝光元数据；`RotationCoordinator` 真实 KVO 朝向监听与对齐；系统热状态监听自动 60→30fps 平滑降帧与恢复（TASK-06）。
  - **`SyncKit` 纯 Swift E2EE 通信**：100% 纯 Swift 实现（零 C/Rust 依赖），Curve25519 + HKDF + AES-GCM-256 加密、`ReferencePackage`/`CapturePackage` 编解码、会话令牌/二维码、WebSocket/Bonjour 传输抽象及 17 项单元测试（TASK-10）。
  - **质量门禁体系**：10 步门禁脚本升级真实 compiled `.app` bundle 体积测量、合成自测标记（`SYNTHETIC_SELF_TEST`）与字段级 Swift Parity 比对（TASK-02）。
- **当前优先推进（TASK-05, TASK-07, TASK-08）**：
  - `ComposeKit` / FFI：扩展 UniFFI 契约输出 severity、完整 action 与 target 并重生成绑定（TASK-05）。
  - `PerceptionKit`：基于 TASK-06 透出数据真正执行 Vision 姿态/掩码/人脸请求并做运动插值（TASK-07）。
  - `CameraApp`：端到端串联采集、感知、推理流与快门拍照（TASK-08）。
- **待办特性**：用户引导 HUD（TASK-09）、App Clip 助手交互流程（TASK-11）、语音 TTS（TASK-12）、照片复盘应用 `ReviewApp` 与桌面端（TASK-13）。
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
