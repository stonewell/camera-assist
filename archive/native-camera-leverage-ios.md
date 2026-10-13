# 最大化利用 iOS 原生相机能力调研

> 目标：只开发"构图引导"这一差异化能力，相机本身的功能尽量交给系统。
> 调研时间：2026-10（iOS 26 已发布，iOS 27 为 WWDC26 公布版本）。标注【待验证】的条目需要在真机上做 spike 确认。

---

## 1. 结论

1. **没有办法在原生相机 App 上叠加我们的提示。** iOS 不允许第三方读取相机 App 的取景画面，也不允许在它上面绘制浮层；相机同一时刻只能被一个 App 独占。所以**实时构图引导必须自建 `AVCaptureSession`**，这一点绕不过去。
2. 但"自建取景器"不等于"自研相机"。通过 AVFoundation，第三方可以拿到和原生相机**同一条成像管线**（Photonic Engine 多帧融合、24MP/48MP、延迟处理、零延迟快门、景深）。画质差距主要只剩**夜间模式**和**摄影风格**两项。
3. 推荐**双轨方案**：
   - **A 轨（实时）**：我们的极简取景器 = 系统成像管线 + 系统控件 + 构图引导层。只做帮拍模式这一个场景。
   - **B 轨（事后）**：用户继续用原生相机随便拍，我们通过 PhotoKit 读取最近的照片，用**同一套 CompositionKit** 做复盘和一键裁切/拉直，结果写回系统相册且可还原。
4. 照这样做，相机相关的自研工作量可以压缩到**大约一个"薄壳"**：取景、拍照、保存。变焦、曝光、快门按键、镜头切换、HDR、图库、编辑、分享全部交给系统。

---

## 2. 硬约束（为什么不能"寄生"在原生相机上）

| 想法 | 是否可行 | 原因 |
|---|---|---|
| 在原生相机 App 上画浮层 | ❌ | 沙盒隔离，没有任何跨 App 绘制接口 |
| 读取原生相机的实时画面 | ❌ | 没有接口；相机硬件被前台 App 独占 |
| 用 URL Scheme 带参数打开原生相机（比如指定模式） | ❌ | 原生相机没有公开的 URL Scheme；快捷指令可以打开相机，但拿不到回传结果 |
| 画中画（PiP）浮在相机 App 上显示提示 | ❌ 无意义 | 就算浮窗能显示，我们也拿不到相机画面，提示无从计算 |
| `UIImagePickerController`（系统拍照界面）+ `cameraOverlayView` | ⚠️ 只能用于兜底 | 可以加浮层，但**拿不到逐帧画面**，没法实时分析；能用的功能也远少于原生相机 |
| 使用 Photos 的"重新取景"（Spatial Reframe）等编辑能力 | ❌ | Apple 在 WWDC26 Lab 里明确表示没有开发者 API |
| 读取 Photos 自身的编辑参数（adjustment plist） | ❌ | Apple 在 WWDC26 Lab 里明确表示没有 API，格式也不公开 |

**结论**：实时引导只能靠自建取景器（A 轨）；如果要"零侵入"，只能做事后分析（B 轨）。

---

## 3. 能力对照表：原生相机有的，我们怎么处理

图例：✅ 调用系统 API 直接获得 ｜ 🔁 交给系统 App 完成 ｜ ⛔ 第三方无法获得，接受差距 ｜ 🛠 需要自己做

### 3.1 成像与画质

| 原生能力 | 第三方可得性 | 我们的做法 | 对应 API / 说明 |
|---|---|---|---|
| Photonic Engine / Deep Fusion / Smart HDR 多帧融合 | ✅ | 拍照时选择 quality 优先级 | `maxPhotoQualityPrioritization = .quality`，每次拍照时设 `photoQualityPrioritization` |
| 24MP 默认输出（iPhone 15 及以后） | ✅ | 与原生默认保持一致 | `sessionPreset = .photo` + `maxPhotoDimensions`；**24MP 必须开启延迟处理** |
| 48MP | ✅ | MVP 不用，作为"高清"开关预留 | 48MP 为单帧处理，只支持 balanced/quality |
| 延迟处理（拍完立即可以拍下一张） | ✅ | 必须开启 | `isAutoDeferredPhotoProcessingEnabled`，回调 `didFinishCapturingDeferredPhotoProxy` |
| 零快门延迟 / 快速连拍 | ✅ | 开启，用于自动快门和抓拍 | `isResponsiveCaptureEnabled`、`captureReadiness`、快速拍摄优先级；iOS 27 起 iPhone 16/17 的快速连拍也会走延迟处理 |
| 快速启动 | ✅ | 采用 | iOS 26 的 deferred start：先启动预览，照片输出延后初始化 |
| 自动切换镜头（超广角、微距、长焦） | ✅ | 用虚拟设备，不自己写切换逻辑 | `.builtInTripleCamera` / `.builtInDualWideCamera` |
| 人像景深、事后调虚化 | ✅ | 拍摄时把景深数据嵌入照片，虚化留给 Photos 后期调整 | `isDepthDataDeliveryEnabled`、`portraitEffectsMatteDeliveryEnabled`；Apple 表示开启景深后可以"之后再加人像效果"。**Photos 能否把它识别为可编辑的人像照片【待验证】** |
| 语义分割（皮肤、头发、天空） | ✅ | 拍照时一并保存，供 B 轨和后续功能使用 | `enabledSemanticSegmentationMatteTypes` |
| Live Photo | ✅ | 开启。抓拍容错高，选帧交给 Photos | `livePhotoMovieFileURL` |
| ProRAW | ✅ | 不做（不是目标用户的需求） | — |
| **夜间模式** | ⛔ | 接受差距：低光时提示"夜景请用系统相机" | 没有找到公开 API；Halide 等专业相机也公开表示拿不到 |
| **摄影风格（Photographic Styles）** | ⛔ | 不做滤镜，色调交给 Photos 后期 | 没有找到公开 API【待验证】 |
| 镜头脏污提醒 | ✅ | 采用，作为一条 critical 提示 | `cameraLensSmudgeDetectionStatus`（iOS 26）；Vision 也有 `DetectLensSmudgeRequest`。有开发者反馈很难触发 |
| 电影效果模式（视频实时虚化） | ✅ | 不做（MVP 只拍照） | iOS 26 的 Cinematic Video Capture API |

### 3.2 取景与交互

| 原生能力 | 第三方可得性 | 我们的做法 | 对应 API / 说明 |
|---|---|---|---|
| 变焦拨盘（0.5× / 1× / 2× …） | ✅ | **直接用系统控件**，不自己画 | `AVCaptureSystemZoomSlider`，在相机控制按键和屏幕上表现与原生一致 |
| 曝光补偿 | ✅ | 直接用系统控件 | `AVCaptureSystemExposureBiasSlider` |
| 相机控制按键（iPhone 16 及以后） | ✅ | 绑定拍照；自定义菜单只加一项"引导开/关" | `AVCaptureEventInteraction` + `AVCaptureIndexPicker` |
| 音量键拍照 | ✅ | 同一个 `AVCaptureEventInteraction` | — |
| AirPods 按柄遥控拍照（iOS 26） | ✅ **免费获得** | 帮拍者可以把手机交给被拍者，或者架起来远程拍 | 已经用了 `AVCaptureEventInteraction` 的 App 在 iOS 26 自动支持 |
| 点按对焦、测光 | ✅ | 几行代码，自己写 | `focusPointOfInterest` / `exposurePointOfInterest` |
| 水平仪 + 预览随横竖屏旋转 | ✅ | **用系统的旋转协调器**，替代自己写的握持方向判断 | `AVCaptureDevice.RotationCoordinator`（iOS 17）：`videoRotationAngleForHorizonLevelPreview` / `…Capture` |
| 网格线 | 🛠 | 自己画（成本极低，引导层本来就要画三分线） | — |
| 锁屏、控制中心、操作按钮快速启动 | ✅ | 做一个 LockedCameraCapture 扩展 | 限制：扩展必须立即显示取景画面；不能联网、不能读相册；不能用 App Group 共享数据；`appContext` 限 4KB；不符合要求约 10 秒后会被系统终止 |
| 智能取景建议（Center Stage 前置摄像头） | ✅ 但不适用 | 只支持前置摄像头，与帮拍场景无关 | `AVCaptureSmartFramingMonitor`（iOS 26，iPhone 17 系列） |

### 3.3 拍摄之后

| 原生能力 | 第三方可得性 | 我们的做法 |
|---|---|---|
| 图库、浏览、筛选 | 🔁 | **不做图库**。拍完直接存入系统相册，"查看"按钮跳转到 Photos |
| 选片、打分 | ✅ | 可选：通过 PhotoKit 给照片写 1–5 分（WWDC26 提到的新评分枚举），给 B 轨做"推荐保留"标记 |
| 裁切、拉直 | ✅（我们的格式） | B 轨用 `PHContentEditingOutput` 写**我们自己的** adjustmentData，Photos 里可以一键还原 |
| 调色、滤镜、消除路人（Clean Up） | 🔁 | 交给 Photos 自带编辑功能，不做 |
| 分享 | 🔁 | 系统分享面板 `UIActivityViewController` |
| iCloud 同步 | 🔁 | 存入系统相册后自动同步 |

---

## 4. 双轨方案细节

### 4.1 A 轨：极简取景器（实时帮拍引导）

**定位**：只服务于"帮别人拍人像"这一个场景，不追求替代原生相机。

```
┌───────────────────────────────┐
│ [引导 开/关]               [⚙] │ ← 只有一个开关；设置页尽量少
│                               │
│     取景画面（系统成像管线）      │
│     + 构图引导层（CompositionKit） │
│                               │
│  ── AVCaptureSystemZoomSlider ── │ ← 系统控件
│  [相册→Photos]  (●拍照)  [翻转]  │
└───────────────────────────────┘
低光时：顶部提示"光线太暗，建议切换到系统相机夜间模式"
```

**采集配置清单（全部是现成的系统 API，不自己实现算法）：**

```swift
let session = AVCaptureSession()
session.beginConfiguration()
session.sessionPreset = .photo

// 1) 虚拟设备：自动切换镜头，与原生相机行为一致
let device = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
    ?? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
    ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)!
session.addInput(try AVCaptureDeviceInput(device: device))

// 2) 照片输出：与原生同一条管线
let photo = AVCapturePhotoOutput()
session.addOutput(photo)
photo.maxPhotoQualityPrioritization = .quality
if let dims = device.activeFormat.supportedMaxPhotoDimensions
    .filter({ $0.width * $0.height <= 24_000_000 })          // 与原生默认的 24MP 对齐
    .max(by: { $0.width * $0.height < $1.width * $1.height }) {
    photo.maxPhotoDimensions = dims
}
photo.isAutoDeferredPhotoProcessingEnabled = photo.isAutoDeferredPhotoProcessingSupported  // 24MP 必需
photo.isZeroShutterLagEnabled = photo.isZeroShutterLagSupported
photo.isResponsiveCaptureEnabled = photo.isResponsiveCaptureSupported
photo.isFastCapturePrioritizationEnabled = photo.isFastCapturePrioritizationSupported
photo.isDepthDataDeliveryEnabled = photo.isDepthDataDeliverySupported
photo.isPortraitEffectsMatteDeliveryEnabled = photo.isPortraitEffectsMatteDeliverySupported
photo.isLivePhotoCaptureEnabled = photo.isLivePhotoCaptureSupported

// 3) 分析流：给 CompositionKit 用（低分辨率、丢弃迟到帧）
let analysis = AVCaptureVideoDataOutput()
analysis.alwaysDiscardsLateVideoFrames = true
session.addOutput(analysis)

// 4) 系统控件：变焦、曝光（同时出现在相机控制按键上）
if session.supportsControls {
    session.addControl(AVCaptureSystemZoomSlider(device: device))
    session.addControl(AVCaptureSystemExposureBiasSlider(device: device))
}
session.commitConfiguration()

// 5) 旋转、水平：交给系统
let rotation = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)

// 6) 物理按键 / 相机控制按键 / AirPods 遥控：一个交互全部覆盖
let shutter = AVCaptureEventInteraction { event in
    if event.phase == .ended { capture() }
}
view.addInteraction(shutter)
```

> 上面的属性名基于 Apple 文档和 WWDC 讲稿整理，个别属性（如 deferred start 的写法、`isFastCapturePrioritizationEnabled` 的准确名称）需要对照最新 SDK 校正。

### 4.2 B 轨：原生拍摄 + 事后复盘（零侵入）

**定位**：覆盖"用户懒得换 App"的大多数场景，同时可以作为 A 轨的拉新入口。

```
用户用原生相机拍照
      │
      ▼
打开我们的 App（或者接收系统分享面板的照片）
      │  PhotoKit：取最近 N 小时内含人物的照片（PHAsset 筛选 + Vision 人体检测）
      ▼
同一套 CompositionKit 对静态照片跑规则（规则本来就是纯函数，可以直接复用）
      │
      ├─ 可以修正的：歪斜 → 自动拉直；留白多、贴边 → 推荐裁切框
      │     → 用 PHContentEditingOutput 非破坏性地写回系统相册，Photos 里可以"还原"
      │
      └─ 无法修正的：切头、裁在关节上、脚悬空 → 生成"下次这样拍"的图示复盘
            → 一键"用帮拍模式重拍"，进入 A 轨
```

**和 A 轨共用的部分**：CompositionKit 的规则、阈值、文案几乎全部可以复用。差别只在于：B 轨没有时间维度，所以不需要仲裁器；也拿不到 IMU，所以"歪斜"改为用 Vision 的地平线和直线检测来估计（`VNDetectHorizonRequest`）。

**B 轨的限制**：
- 需要相册的读写权限，用户的接受度要实际测试。
- 我们写回的裁切参数，Photos 编辑器里看不到具体数值，只能整体还原。
- 照片里的人像景深数据可以读取，但 Photos 的编辑参数格式不公开，不能修改用户已经做过的 Photos 编辑。

### 4.3 入口整合

| 入口 | 指向 | 实现方式 |
|---|---|---|
| 相机控制按键（长按 / 设置里指定 App） | A 轨取景器 | 用户在"设置 → 相机控制"里选择我们的 App |
| 锁屏、控制中心按钮 | A 轨（锁屏版） | LockedCameraCapture 扩展；只保留取景、引导、拍照 |
| 操作按钮 | A 轨 | 用户自行在系统设置里绑定 |
| 系统分享面板（从 Photos 分享照片） | B 轨复盘 | Share Extension |
| 打开 App 首页 | B 轨："最近 N 张照片的构图体检" | PhotoKit |

---

## 5. 不做清单（相对"自研完整相机"节省的工作量）

| 功能 | 原本需要投入 | 现在 |
|---|---|---|
| 变焦拨盘、镜头切换逻辑 | 1–2 周 | 系统控件 + 虚拟设备，约 0.5 天 |
| 曝光、对焦交互 | 1 周 | 系统曝光控件 + 点按对焦，约 1 天 |
| 物理按键、相机控制按键、遥控快门 | 1 周 | `AVCaptureEventInteraction`，约 0.5 天 |
| HDR、降噪、多帧融合 | 无法做到原生水平 | 系统管线，零成本 |
| 横竖屏旋转与水平 | 3–5 天 | `RotationCoordinator`，约 1 天 |
| 滤镜、调色 | 2–4 周 | 交给 Photos |
| 图库、浏览、管理 | 2–3 周 | 交给 Photos |
| 编辑（裁切以外） | 4 周以上 | 交给 Photos |
| 夜间模式 | 无法做到原生水平 | 提示用户切换到系统相机 |
| **合计** | **约 3 个月** | **约 1–1.5 周** |

> 节省的时间估算是粗略值，用于说明数量级。

---

## 6. 对《构图规则引擎细化方案》的修改建议

| 章节 | 修改 |
|---|---|
| 4.1 坐标变换 | 握持方向和预览旋转改用 `AVCaptureDevice.RotationCoordinator`，不再自己根据重力向量判断握持方向。roll 角度仍然由 IMU 计算，用于 `level.roll` 规则 |
| 2 模块结构 | `PerceptionKit/CaptureSession` 按照第 4.1 节的清单配置；新增 `PhotoLibraryAnalyzer`（B 轨） |
| 6 规则清单 | 新增 `lens.smudge`（critical，数据来源是 `cameraLensSmudgeDetectionStatus`）；新增 `light.low` 提示（引导用户切换到系统相机夜间模式） |
| 6.A | B 轨的 `level.roll` 改用 Vision 地平线检测，规则接口不变，只是输入来源不同 |
| 10 测试 | `compose-eval` 可以直接作为 B 轨的原型，因为它本来就是在静态照片上跑规则 |

---

## 7. 待验证 spike 清单（建议第 1 周完成）

| # | 验证项 | 方法 | 影响 |
|---|---|---|---|
| 1 | 按 4.1 节配置后，第三方拍出的照片与原生相机同场景照片的画质差异 | 白天、阴天、逆光、室内各 10 组，盲测对比 | 决定 A 轨的画质是否可以接受 |
| 2 | 嵌入景深的 HEIC 存入相册后，Photos 能否识别为可编辑的人像照片 | 真机保存后，看 Photos 里有没有"人像"开关 | 决定是否需要自己做虚化 |
| 3 | 夜间模式、摄影风格确实没有公开 API | 查阅最新 SDK 头文件和 iOS 27 发布说明 | 决定低光提示的策略 |
| 4 | 镜头脏污检测的触发率 | 真机上故意弄脏镜头测试 | 决定 `lens.smudge` 规则是否值得上线 |
| 5 | 分析流（640×480）与 24MP 拍照同时运行时的性能和发热 | Instruments | 可能需要调整分析频率 |
| 6 | LockedCameraCapture 扩展里能否跑 Vision 和 CompositionKit，内存是否超限 | 真机测试 | 决定锁屏版是否带引导功能 |
| 7 | B 轨：静态照片上地平线和直线检测估计歪斜的准确率 | 用 `compose-eval` 跑数据集 | 决定 B 轨是否自动拉直 |

---

## 参考资料

- [Enhancing your camera experience with capture controls – WWDC25](https://developer.apple.com/videos/play/wwdc2025/253/)
- [Implement high resolution photo capture – WWDC26](https://developer.apple.com/videos/play/wwdc2026/304/)
- [Camera and Photo Technologies Group Lab – WWDC26](https://developer.apple.com/videos/play/wwdc2026/8018/)
- [Support the Center Stage front camera in your iOS app – WWDC26](https://developer.apple.com/videos/play/wwdc2026/341/)
- [Create a more responsive camera experience – WWDC23](https://developer.apple.com/videos/play/wwdc2023/10105/)
- [cameraLensSmudgeDetectionStatus – Apple Developer Documentation](https://developer.apple.com/documentation/avfoundation/avcapturedevice/cameralenssmudgedetectionstatus)
- [DetectLensSmudgeRequest – Apple Developer Documentation](https://developer.apple.com/documentation/vision/detectlenssmudgerequest)
- [LockedCameraCapture Extension Demo & Explanation](https://juniperphoton.substack.com/p/lockedcameracapture-extension-demo)
- [iOS 18 lets third-party camera apps launch from Lock Screen – MacRumors](https://www.macrumors.com/2024/06/12/ios-18-activate-camera-app-lock-screen/)
- [Halide 关于 Night Mode API 的诉求（X）](https://x.com/halidecamera/status/1527728518582239232)
- [Halide Process Zero – DPReview](https://www.dpreview.com/news/5101705770/halide-process-zero-ai-computational-photograpy-phones-raw/)
- [Capturing Depth in iPhone Photography – WWDC17](https://developer.apple.com/videos/play/wwdc2017/507/)
- [ImageMagick 讨论：HEIC + 深度图在 Photos 中显示为人像](https://github.com/ImageMagick/ImageMagick/discussions/3892)
