# Camera Assist (帮拍相机 & 照片复盘)

> 教帮拍的人把人拍好，帮拍完的人把片修好。

**Camera Assist** 是一个专为旅行和日常人像帮拍场景设计的摄影辅助工具体系。针对"帮拍者不懂构图和光线"、"拍完选片废片多"等痛点，提供**拍摄时实时引导**与**拍后照片体检复盘**两套互补的应用，两端共用同一套底层规则引擎。

---

## 核心应用与开发方案

本项目包含两个主要应用，各自拥有详细的架构与开发规划文档：

| 应用 | 定位与核心能力 | 目标平台 | 开发方案文档 |
|---|---|---|---|
| **帮拍相机 (CameraApp)** | **实时引导相机**：自建取景器 + 原生系统成像管线，提供实时构图提示、光线站位指引、安全自动曝光补偿、**路人帮拍模式**（锁定构图 + 对齐引导）以及**语音播报提示**。 | iOS 18+ (iPhone) | [帮拍相机 iOS App 开发方案 v1.6](camera-assist-app-plan.md) |
| **照片复盘 (ReviewApp)** | **事后构图体检与修复**：无论使用手机还是单反拍摄，拍完后均可进行构图体检、光线复盘，支持一键拉直与推荐裁切、生成旅行总结报告，并可通过深链接一键跳转帮拍相机重拍。 | iOS + 桌面端 (macOS / Windows / Linux) | [照片复盘应用开发方案 v1.3](photo-review-app-plan.md) |

### 辅助调研、全局规划与归档资料

- **任务优先级与协同**：[研发任务优先级与双项目协同规划](development-priorities.md) —— 制定了双应用 P0–P3 任务优先级、依赖关键路径图与排期对齐表。
- **功能调研**：[帮拍场景其他有效功能调研](helper-mode-features-research.md) —— 调研了路人帮拍、表情口令卡、偏好卡、智能挑片、双机实时预览等竞品与用户痛点。
- **归档文档**：[archive/](archive/) —— 包含合并重构前的三份早期技术规划：
  - [构图规则引擎 (`composition-rule-engine-ios.md`)](archive/composition-rule-engine-ios.md)
  - [原生相机能力利用 (`native-camera-leverage-ios.md`)](archive/native-camera-leverage-ios.md)
  - [光线与站位建议 (`light-distance-advisor-ios.md`)](archive/light-distance-advisor-ios.md)

---

## 代码仓库结构 (Monorepo)

```
camera-assist/
├─ core/                              Rust workspace（多端共用底层核心）
│  ├─ compose-core/                   ★ 规则引擎：纯 Rust，包含规则 A–G、几何计算、光线模型、仲裁器、静态图分析
│  ├─ compose-ffi/                    UniFFI 绑定 → 生成 iOS/macOS 适用的 XCFramework 与 Swift Package
│  ├─ perception-onnx/                ONNX Runtime 推理（桌面端人体检测、分割、姿态、人脸与直线检测）
│  ├─ media-io/                       桌面端媒体读写（解码、EXIF、缩略图缓存、JPEG 导出、XMP 侧车文件）
│  ├─ review-engine/                  桌面端复盘引擎（文件夹扫描、后台任务队列、SQLite 缓存、旅行分组）
│  ├─ review-bridge/                  flutter_rust_bridge 绑定 → 供 Flutter 桌面端调用
│  └─ compose-eval/                   Rust 命令行评测工具（ONNX 后端）
├─ apple/                             Apple 生态工程
│  ├─ CameraApp/                      ★ 帮拍相机 iOS 主应用（SwiftUI 外壳 + UIKit 取景页 + 锁屏扩展）
│  ├─ CameraAppClip/                  ★ 路人帮拍 App Clip（免安装轻应用，< 5MB）
│  ├─ ReviewApp/                      照片复盘 iOS 应用（SwiftUI + PhotoKit 非破坏性写回 + 分享扩展）
│  ├─ Packages/
│  │   ├─ ComposeKit/                 compose-ffi 上的 Swift 薄封装（值类型、Sendable，双 iOS 应用共用）
│  │   ├─ PerceptionVision/           Vision 感知后端（双 iOS 应用共用）
│  │   ├─ PerceptionKit/              实时感知调度、平滑、IMU、定位、天气（帮拍相机专有）
│  │   ├─ CaptureKit/                 AVCaptureSession 管线、24MP 输出、相机控制控件（帮拍相机专有）
│  │   ├─ GuideKit/                   帮拍辅助：路人帮拍模式、语音播报（帮拍相机专有）
│  │   └─ SyncKit/                    ★ 跨机通信：E2EE 临时会话、AES-GCM-256 加解密（帮拍相机专有）
│  └─ Tools/
│      ├─ compose-eval-vision/        macOS 命令行离线评测工具（Vision 后端）
│      └─ capture-replay/             真机录制数据回放工具
├─ desktop/                           Flutter 桌面端应用（macOS / Windows / Linux 跨平台 UI）
├─ shared/
│  ├─ config/Thresholds.json          统一规则阈值与后端覆盖配置（所有应用共用）
│  ├─ hints/                          多语言文案源文件（zh-Hans.json, en.json）
│  └─ models/                         桌面端 ONNX 模型清单与配置文件
└─ fixtures/
   ├─ golden/                         黄金测试向量（感知输入 → 预期判定，双端一致性验收）
   └─ eval-dataset/                   离线标注测试数据集
```

---

## 核心设计原则

1. **规则唯一实现**：所有构图与光线规则均在 Rust `compose-core` 中实现并经过黄金测试向量验证，保证 iOS 实时端、iOS 复盘端、桌面复盘端的判定逻辑完全一致。
2. **一次只给一条提示**：实时帮拍取景时，通过内置仲裁器（防抖、优先级、冷却、静默）确保屏幕上始终最多只显示一条最关键的指导动作，不让帮拍者手忙脚乱。
3. **安全与非破坏性**：
   - 帮拍相机仅申请相册"仅添加"权限，路人帮拍先挑后存，不向相册写入废片；
   - 照片复盘应用从不覆盖原图（iOS 采用 PhotoKit 系统级可逆编辑，桌面端导出新文件或写入 XMP 侧车文件）。
4. **全面本地化与隐私优先**：所有画面分析、人体与人脸检测均在设备端本地神经网络引擎 / CPU / GPU 完成，不上传用户照片与生物特征。
