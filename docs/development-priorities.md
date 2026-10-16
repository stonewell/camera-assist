# Camera Assist 研发任务优先级与双项目协同规划 (Master Development Plan)

> **关联方案**：
> - 实时相机应用：[`camera-assist-app-plan.md`](camera-assist-app-plan.md)（帮拍相机 iOS App 开发方案 v1.6）
> - 事后复盘应用：[`photo-review-app-plan.md`](photo-review-app-plan.md)（照片复盘应用开发方案 v1.3 - iOS + 桌面端）
> - 制定时间：2026-10 | 版本：v1.0

---

## 1. 规划背景与双应用协同定位

**Camera Assist** 体系致力于解决旅拍中"不懂拍"与"修图难"的两端痛点：
- **帮拍相机 (`CameraApp`)**：重在**拍摄时当场拍好**。通过自建取景器叠加系统成像管线，提供实时构图提示、光线站位引导、语音播报，以及**App Clip 扫码免交接帮拍与成片自动回传**。
- **照片复盘 (`ReviewApp`)**：重在**拍完后零门槛体检修复**。跨 iOS 移动端与 macOS / Windows / Linux 桌面三端，提供非破坏性一键拉直裁切、单反 RAW 批量处理与旅行复盘报告，并可通过深链接一键呼出帮拍相机重拍。

两套应用依托统一的 monorepo，**共享纯 Rust 核心规则引擎 `compose-core`、统一阈值配置 `Thresholds.json`、多语言文案与黄金测试向量集**。

---

## 2. 依赖架构全景图

```mermaid
graph TD
    classDef p0 fill:#ffebee,stroke:#c62828,stroke-width:2px;
    classDef p1 fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px;
    classDef p2 fill:#e3f2fd,stroke:#1565c0,stroke-width:2px;
    classDef p3 fill:#fff3e0,stroke:#ef6c00,stroke-width:2px;

    subgraph Phase0["P0: 核心基座与可行性验证 (W1-W2)"]
        Spike1["Spike #1: 相机画质盲测"]:::p0
        Spike22["Spike #22/R9: UniFFI 实时开销"]:::p0
        SpikeR1["Spike R1: ONNX 模型与许可证"]:::p0
        RepoInit["Monorepo 骨架与 CI 矩阵"]:::p0
        CoreContract["compose-core 数据契约与骨架"]:::p0
        GoldenInit["fixtures/golden 向量规范"]:::p0
    end

    subgraph Phase1["P1: 核心产品闭环与规则基线 (W3-W7)"]
        CaptureKit["CaptureKit: 24MP 采集管线"]:::p1
        PerceptionKit["PerceptionKit: Vision 姿态/掩码"]:::p1
        RulesAD["compose-core: A-D类构图规则"]:::p1
        ComposeKit["ComposeKit: Swift 封装与仲裁器"]:::p1
        CameraUI["CameraApp 取景页与实时叠加层"]:::p1
        EvalVision["compose-eval-vision 评测门禁"]:::p1
        ReviewKit["ReviewApp iOS PhotoKit 可逆体检"]:::p1
    end

    subgraph Phase2["P2: 差异化特色与体验增强 (W8-W12)"]
        SyncKit["SyncKit: 跨机 E2EE 临时中继"]:::p2
        AppClipTarget["CameraAppClip: 免装轻应用 (<5MB)"]:::p2
        StrangerUI["路人帮拍扫码与双向引导"]:::p2
        LightOptics["compose-core: E-G类光线距离规则"]:::p2
        VoicePrompt["VoicePrompter: 语音播报"]:::p2
        DesktopEngine["review-engine + perception-onnx"]:::p2
        FlutterUI["ReviewApp Flutter 桌面网格与报告"]:::p2
    end

    subgraph Phase3["P3: 生态扩展与发布准备 (W11-W18)"]
        LockedExt["LockedCameraCapture 锁屏扩展"]:::p3
        DeepLink["跨应用通用链接/深链接联动"]:::p3
        FieldTest["景区双盲测试与调优"]:::p3
        DesktopPkg["桌面端三平台签名与自动更新"]:::p3
        AppStoreAudit["TestFlight 外测与 App Store 提审"]:::p3
    end

    %% Dependencies
    CoreContract --> RulesAD
    RepoInit --> CaptureKit
    CoreContract --> ComposeKit
    RulesAD --> ComposeKit
    CaptureKit --> CameraUI
    PerceptionKit --> CameraUI
    ComposeKit --> CameraUI
    RulesAD --> EvalVision
    RulesAD --> ReviewKit

    CameraUI --> StrangerUI
    SyncKit --> AppClipTarget
    StrangerUI --> AppClipTarget
    RulesAD --> LightOptics
    LightOptics --> VoicePrompt
    RulesAD --> DesktopEngine
    DesktopEngine --> FlutterUI

    CameraUI --> LockedExt
    CameraUI --> DeepLink
    FlutterUI --> DeepLink
    StrangerUI --> FieldTest
    FlutterUI --> DesktopPkg
    FieldTest --> AppStoreAudit
    DesktopPkg --> AppStoreAudit
```

---

## 3. 全局任务优先级矩阵 (P0 – P3)

### 🔴 P0 级：核心基座与阻断性可行性验证 (Weeks 1–2)
> **退出标准**：Rust + Swift 黄金测试向量打通；4 大关键 Spike 验证通过；CI 自动化构建矩阵就绪。

| 任务 ID | 领域 | 核心任务与交付标准 | 负责人 | 前置依赖 |
|---|---|---|---|---|
| **P0-1** | 基础设施 | 统一 Monorepo 骨架（Cargo + Xcode + Flutter），搭建 GitHub Actions 跨平台 CI 矩阵 | Rust 工程师 + 算法工程师 | 无 |
| **P0-2** | 共享核心 | 定义统一数据契约（`Frame`、`Subject`、`Joint`、`Finding`、`Action`、`Severity`），建立纯 Rust `compose-core` crate | Rust 核心工程师 | P0-1 |
| **P0-3** | FFI 绑定 | 建立 UniFFI 绑定与 XCFramework（iOS 真机/模拟器/macOS）自动化打包发布流水线 | Rust 核心工程师 | P0-2 |
| **P0-4** | 评测底座 | 制定黄金测试向量规范（`fixtures/golden/*.json`），实现 Rust 检验器与 Swift 运行器 | 算法工程师 + iOS B | P0-2 |
| **P0-5** | Spike #1 | **画质盲测**：AVCapturePhotoOutput 24MP 系统管线 vs 原生相机实拍盲测，验证自建取景器画质可行性 | iOS 工程师 A | 无 |
| **P0-6** | Spike #22/R9 | **UniFFI 实时开销验证**：真机调用 `engine.step()` 耗时必须 < 1.0 ms；验证 Swift 6 `Sendable` 兼容 | iOS 工程师 B + Rust 工程师 | P0-3 |
| **P0-7** | Spike R1 | **桌面模型选型审查**：审查 RTMPose、UltraFace、YOLOv8-Seg 开源许可证与商用限制，完成 ONNX 转换 | 算法 / 评测工程师 | 无 |
| **P0-8** | Spike #23 | **App Clip 架构隔离**：构建最小纯 Swift App Clip Target，验证未链接 Rust 库时体积 < 5 MB（远低于 15 MB 门禁） | iOS 工程师 A | P0-1 |

---

### 🟢 P1 级：核心产品闭环与规则基线 (Weeks 3–7)
> **退出标准**：CameraApp 完成实时取景与 A–D 类提示；ReviewApp 完成 iOS 照片体检与非破坏性修复；离线评测精确率 ≥ 85%。

| 任务 ID | 领域 | 核心任务与交付标准 | 负责人 | 前置依赖 |
|---|---|---|---|---|
| **P1-1** | 相机采集 | `CaptureKit`：AVCaptureSession 高画质管线、24MP 输出、RotationCoordinator 对齐与防畸变 | iOS 工程师 A | P0-5 |
| **P1-2** | 实时感知 | `PerceptionKit`：Vision 人体姿态、人像掩码、人脸检测及 60Hz IMU 运动姿态平滑融合 | iOS 工程师 B | P1-1 |
| **P1-3** | 构图规则 | `compose-core`：实现 A 类姿态/水平、B 类人体裁切、C 类画面位置大小、D 类多人站位平衡 | Rust 工程师 + iOS B | P0-2, P0-4 |
| **P1-4** | 提示仲裁 | `HintArbiter`：实现一次只给一条提示仲裁器（迟滞防抖、抢占、冷却、手持晃动静默） | Rust 核心工程师 | P1-3 |
| **P1-5** | Swift 封装 | `ComposeKit`：封装 `LiveComposer`，桥接 UniFFI，实现主线程 UI 消费的高性能值类型流 | iOS 工程师 B | P0-3, P1-4 |
| **P1-6** | 相机 UI | 取景页 UIKit/Core Animation 叠加层：实时单条提示胶囊、动态水平线、站位引导线、触感反馈 | iOS 工程师 A | P1-1, P1-5 |
| **P1-7** | 离线评测 | Swift 版 `compose-eval-vision` 评测流水线，300 张旅拍标注集门禁跑通（精确率 ≥ 85%） | 算法 / 工具工程师 | P1-3, P1-5 |
| **P1-8** | iOS 复盘 | `ReviewApp` iOS 最小闭环：相册浏览、PhotoKit 异步分析、构图体检项展示、一键可逆裁切拉直写回 | ReviewApp iOS 工程师 | P0-3, P1-3 |

---

### 🔵 P2 级：杀手级特性与多端能力增强 (Weeks 8–12)
> **退出标准**：App Clip 扫码帮拍与 E2EE 自动回传真机打通；光线/距离与语音播报上线；桌面端三平台批量引擎就绪。

| 任务 ID | 领域 | 核心任务与交付标准 | 负责人 | 前置依赖 |
|---|---|---|---|---|
| **P2-1** | 跨机通信 | `SyncKit`：`ReferencePackage` / `CapturePackage` 编解码；集成 CryptoKit AES-256-GCM 本地加密 | iOS 工程师 B | P0-1 |
| **P2-2** | 云端中继 | 部署轻量短时 E2EE 中继服务（Cloudflare Worker / WebSocket），15 分钟 TTL 自毁，零知识盲转发 | 算法/工具工程师 (兼) | P2-1 |
| **P2-3** | App Clip | 构建 `CameraAppClip` Target：Associated Domains 关联、扫码 1 秒冷启动、轻量 Vision 图像配准 | iOS 工程师 A | P0-8, P2-1 |
| **P2-4** | 路人帮拍 | 主人端"生成帮拍码"交互 + 路人端 App Clip 极简对齐取景/致谢页；打通**拍摄完成后成片秒级自动回传主人** | iOS 工程师 A + B | P2-2, P2-3 |
| **P2-5** | 光线与距离 | `compose-core`：E 类光线（逆光/阴影/太阳模型）、F 类距离换算、G 类低光与脏污；AutoSettingsPolicy | Rust 工程师 + iOS B | P1-3 |
| **P2-6** | 语音播报 | `VoicePrompter` 本地语音合成播报（AVSpeechSynthesizer，避让快门录音、AirPods 私密播报） | iOS 工程师 A | P1-4 |
| **P2-7** | 桌面引擎 | 桌面端三大 crate：`perception-onnx` 推理流、`media-io` 解码与 XMP、`review-engine` SQLite 批处理 | Rust 核心工程师 | P0-7, P1-3 |
| **P2-8** | 桌面 UI | Flutter 桌面端：海量缩略图 60fps 虚拟滚动网格、体检详情面板、批量一键拉直修复与 XMP 写入 | Flutter 桌面工程师 | P2-7 |

---

### 🟡 P3 级：生态集成、全场景压测与发布交付 (Weeks 11–18)
> **退出标准**：锁屏/相机按键扩展就绪；跨应用深链接打通；实地盲测达标；完成三个桌面系统与 iOS App Store 审核。

| 任务 ID | 领域 | 核心任务与交付标准 | 负责人 | 前置依赖 |
|---|---|---|---|---|
| **P3-1** | 系统扩展 | `LockedCameraCapture` 锁屏扩展（限制内存与 4KB appContext 传输）与系统相机控制按键菜单交互 | iOS 工程师 A | P1-1, P1-5 |
| **P3-2** | 深链接联动 | 通用链接与 URL Scheme 联动：复盘应用"用帮拍相机重拍"携带 `focus` 规则参数直达取景页并提权 | iOS 工程师 A + ReviewApp iOS | P1-6, P1-8 |
| **P3-3** | 实地测试 | 景区双盲实测：20 组情侣帮拍盲测满意度提升 ≥ 65%，30 组路人 App Clip 扫码成功率 ≥ 95% | 测试 / 实地人员 + 全员 | P2-4, P2-6 |
| **P3-4** | 性能与发热 | 连续 15 分钟取景发热与内存压测，Instruments 打点优化，确保不触发系统热节流降频 | iOS 工程师 B | P1-6, P2-5 |
| **P3-5** | 桌面打包发布 | 桌面端 macOS（Developer ID + 公证）、Windows（MSIX 签名）、Linux（AppImage/Flatpak）打包构建 | Flutter 工程师 + Rust | P2-8 |
| **P3-6** | 合规与提审 | 中国大陆 App 备案合规审查、隐私政策、零用户个人数据出境证明；提交 App Store 正式审核 | 全体团队 | 全部前置任务 |

---

## 4. 双项目排期协同表 (Timeline Synchronization)

| 周数 | 阶段 | 帮拍相机 (`CameraApp`) | 照片复盘应用 (`ReviewApp`) | 跨项目公共交付物 |
|---|---|---|---|---|
| **W1–2** | 基础验证 | M0：工程骨架、Spike #1（画质）、Spike #22（FFI 开销）、Spike #23（App Clip 体积） | P0：Spike R1（模型合规）、Spike R2（CPU 耗时）、Spike R3（HEIC 解码）、Spike R7（Flutter Linux 滚动） | Monorepo 骨架、Rust workspace、`compose-ffi` XCFramework 流水线、CI 矩阵 |
| **W3–4** | 采集感知 | M1：CaptureKit 采集管线、PerceptionKit（Vision 姿态/掩码/IMU）、调试面板 | P1 前段：`model`、`geometry`、`classify`、`config`、`ComposeKit` 骨架封装 | 统一数据结构定义、`Thresholds.json`、`PerceptionVision` 共享包 |
| **W5–7** | 构图规则 | M2：构图规则 A–D 落地、Merger、仲裁器、取景页 UIKit 叠加层 | P1 中段：共用 A–D 规则；iOS ReviewApp 原型与 PhotoKit 可逆体检 | 规则 A–D 黄金测试向量通过、`compose-eval-vision` 评测门禁跑通 (≥85%) |
| **W8–10** | 光线与引擎 | M4：光线规则 E、距离 F、镜头环境 G；AutoSettingsPolicy 自动设置 | P2：桌面端 `perception-onnx`、`media-io`、`review-engine` 批处理 | 规则 E–G 黄金测试向量通过、太阳位置与天气模型就绪 |
| **W11–12** | 杀手特性 | M5：**App Clip 扫码帮拍与 E2EE 自动回传**、语音播报、锁屏扩展、深链接 | P3：Flutter 桌面端相册网格与批量修复面板；iOS 复盘应用功能完备 | `SyncKit` 传输协议落地、E2EE 临时中继联调、跨应用深链接打通 |
| **W13–14** | 双端联调 | M6 前段：景区两轮实地双盲评测、路人帮拍可用率测试、性能与发热压测 | P3 后段：1000 张照片批量分析稳定性测试、跨后端判定一致率对比 (≥90%) | **第 14 周里程碑：CameraApp 全功能提审就绪，ReviewApp iOS 具备发布条件** |
| **W15–16** | 交付发布 | M6 后段：TestFlight 公测、App Store 提审与上线发布 | P4 前段：桌面端三平台签名公证、安装包构建、自动更新通道打通 | CameraApp 1.0 正式上线；ReviewApp iOS 1.0 协同上线 |
| **W17–18** | 桌面发布 | 线上稳定性监控、首批用户反馈迭代 | P4 后段：桌面端三平台内测与正式发版 | ReviewApp 桌面端三平台 1.0 正式发版 |

---

## 5. 关键瓶颈与人员配额化解策略 (Anti-Blocking Strategy)

1. **化解 Rust 工程师单点瓶颈（SPOF）**：
   - 方案已给出详尽的 Swift 算法规格伪代码。在 W1–W4 期间，iOS 工程师 B 在 Swift 侧先用算法规格运行 mock，**取景前端无需等待 Rust 库完成即可全速推进**；
   - 规则 A–D 开发期间，iOS 工程师 B 参与编写 Rust 单元测试与黄金测试向量，实现跨语言结对编程。
2. **移动端优先阶梯发版（Staged Release）**：
   - 旅拍具有较强的季节性，移动端抢占"景区帮拍"痛点具有最高的商业时效价值；
   - 第 14–16 周优先保 CameraApp（含 App Clip）与 ReviewApp iOS 版上线；桌面端按节奏在第 18 周全量交付。
