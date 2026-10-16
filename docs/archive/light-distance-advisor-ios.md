# 光线与站位顾问（LightAdvisor）设计方案（仅 iOS）

> 根据位置、时间、光线朝向和天气，给出相机参数提示或自动设置，并提示拍照者前进、后退、绕位。
> 与《构图规则引擎细化方案》共用 Finding / Action / HintArbiter 体系；与《最大化利用 iOS 原生相机能力调研》的 A 轨取景器配合使用。
> 标注【待验证】的条目需要真机 spike 确认。

---

## 0. 核心判断

1. **在 iPhone 上，最有效的不是调参数，而是调人和光的相对位置。** 系统管线（Smart HDR、人脸驱动的自动曝光）已经把参数处理得很好；再加上 WWDC26 的说明，手动 ISO 和快门只在 `speed` 优先级下生效，会失去多帧融合。所以：
   - **自动设置**只做"安全且可撤销"的少数几项：曝光补偿、补光、镜头建议。
   - **重点放在站位提示**：绕着人走到哪个方向、人转向哪里、前进或后退多少步、要不要换镜头。
2. **"预测"只能当先验，"实测"才算数。** 太阳位置、天气是基于模型算出来的，而真实场景里会有楼影、树荫、室内、云层变化。所有判断都以相机实测的场景亮度和人脸/背景亮度比为准，预测只用来解释原因和给出方向。
3. **两类提示、两种节奏：**
   - **实时提示**（取景时）：逆光、顶光、太阳入画、距离和焦段。
   - **计划提示**（打开 App 时、取景前）："距离日落黄金时刻还有 25 分钟"、"现在顶光强烈，建议找阴影处"。

---

## 1. 输入信号

| 信号 | 来源 | 刷新频率 | 精度和注意事项 |
|---|---|---|---|
| 位置（经纬度） | CoreLocation，**粗略定位即可**（`reducedAccuracy`） | 打开时 + 每移动 1 km | 太阳位置和天气只需要公里级精度；不需要精确定位，有利于隐私审核。国内的 GCJ-02 偏移（几百米）对太阳计算没有影响 |
| 当前时间、时区 | 系统时间 | — | — |
| 太阳方位角、高度角 | **本地计算**（NOAA 简化算法，见 3.1） | 1 Hz | 误差 < 0.1°，不需要联网 |
| 日出、日落、黄金时刻、蓝调时刻 | 本地计算 | 每天一次 | 黄金时刻：太阳高度 −4° ~ +6°；蓝调时刻：−6° ~ −4° |
| 相机朝向（方位角） | CMDeviceMotion，参考系 `.xTrueNorthZVertical`；后置镜头方向取设备 −Z 轴在水平面上的投影 | 30 Hz | 罗盘误差通常 ±5–15°，靠近金属、建筑会更大；用 `magneticField.accuracy` 判断是否可信 |
| 相机俯仰角 | 同上（重力向量） | 30 Hz | 用于判断太阳是否入画 |
| 天气 | WeatherKit（云量、天气状况、紫外线指数、能见度、降水） | 每 30 分钟，按 0.1° 网格缓存 | **国内可用性和数据合规【待验证】**；备选：和风天气（QWeather）API。Apple 天气 App 在国内的部分数据就来自 QWeather |
| **场景实测亮度 EV** | 从 `exposureDuration`、`iso`、`lensAperture` 计算 | 10 Hz | **最可靠的信号**，见 3.3 |
| **人脸 / 背景亮度比** | 分析流 Y 通道 + Vision 人脸框 + 人像掩码 | 10 Hz | 判断逆光、阴阳脸的直接证据 |
| 拍摄距离 | 优先用深度（LiDAR 或双摄视差的 `AVCaptureDepthDataOutput`）；没有时用眼距或身高估算（见 5.1） | 10 Hz | 估算误差约 ±15% |
| 当前焦段 | `videoZoomFactor`、`activePrimaryConstituent`、`activeFormat.videoFieldOfView` | 事件驱动 | 换算成等效焦距 |

---

## 2. 架构

```
           慢循环（1 Hz）                              快循环（10 Hz）
┌───────────────────────────────┐        ┌──────────────────────────────────┐
│ SunModel     太阳方位/高度/时刻  │        │ ExposureMeter  场景 EV             │
│ WeatherCache 云量/天气/UV       │        │ LumaProbe      人脸 vs 背景亮度比   │
│ HeadingModel 相机方位 + 可信度   │        │ DistanceEstimator 距离 + 置信度     │
└──────────────┬────────────────┘        └───────────────┬──────────────────┘
               └───────────────┬─────────────────────────┘
                               ▼
                      LightContext（融合后的光线判断）
                    光质、光向、太阳是否入画、是否在阴影/室内
                               │
            ┌──────────────────┼──────────────────────┐
            ▼                  ▼                      ▼
     LightRules           DistanceRules         AutoSettingsPolicy
   （Finding: 光线类）   （Finding: 距离/焦段）   （决定自动应用哪些设置）
            └────────┬─────────┘                      │
                     ▼                                ▼
          HintArbiter（与构图规则共用）        CameraSettingsApplier
                     │                    （平滑过渡、用户手动修改后不再覆盖、可一键撤销）
                     ▼                                │
                   提示 UI  ◀────────── 状态胶囊："逆光 · 已提亮 +0.7  [撤销]"
```

在 `CompositionKit` 里新增 `LightKit` 子模块，保持纯函数和单元测试的方式；传感器适配放在 `PerceptionKit`。

---

## 3. 光线判断

### 3.1 太阳位置（本地计算）

```swift
import Foundation

struct SunPosition { let azimuthDeg: Double; let elevationDeg: Double }  // 方位：正北顺时针

/// NOAA 简化算法，精度约 0.1°，足够用于光向判断
func sunPosition(date: Date, latDeg: Double, lonDeg: Double) -> SunPosition {
    let rad = Double.pi / 180
    let jd = date.timeIntervalSince1970 / 86400 + 2440587.5
    let n = jd - 2451545.0

    let L = (280.460 + 0.9856474 * n).truncatingRemainder(dividingBy: 360)
    let g = ((357.528 + 0.9856003 * n).truncatingRemainder(dividingBy: 360)) * rad
    let lambda = (L + 1.915 * sin(g) + 0.020 * sin(2 * g)) * rad      // 黄经
    let eps = (23.439 - 0.0000004 * n) * rad                          // 黄赤交角

    let ra  = atan2(cos(eps) * sin(lambda), cos(lambda))              // 赤经
    let dec = asin(sin(eps) * sin(lambda))                            // 赤纬

    let gmstHours = (18.697374558 + 24.06570982441908 * n).truncatingRemainder(dividingBy: 24)
    let H = (gmstHours * 15 + lonDeg) * rad - ra                      // 时角
    let lat = latDeg * rad

    let elev = asin(sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(H))
    // 以正南为 0 的方位角 + 180° → 以正北为 0、顺时针
    let az = atan2(sin(H), cos(H) * sin(lat) - tan(dec) * cos(lat)) / rad + 180

    return SunPosition(azimuthDeg: az.truncatingRemainder(dividingBy: 360),
                       elevationDeg: elev / rad)
}
```

> 上线前用 NOAA Solar Calculator 对几个城市和日期做核对。

### 3.2 光向分类

```swift
enum LightDirection { case back, sideLeft, sideRight, front, top }

/// φ = 太阳方位 − 相机方位，归一化到 [-180, 180]
/// φ ≈ 0：太阳在镜头前方 → 被拍者逆光；φ ≈ ±180：太阳在拍照者身后 → 被拍者顺光
func classify(sun: SunPosition, cameraAzimuthDeg: Double) -> (LightDirection, phi: Double) {
    if sun.elevationDeg > 55 { return (.top, 0) }
    var phi = sun.azimuthDeg - cameraAzimuthDeg
    while phi > 180 { phi -= 360 }; while phi < -180 { phi += 360 }
    switch abs(phi) {
    case ..<45:  return (.back, phi)
    case ..<135: return (phi > 0 ? .sideRight : .sideLeft, phi)
    default:     return (.front, phi)
    }
}

/// 太阳是否在画面内（会产生眩光，或者把人拍成剪影）
func sunInFrame(phi: Double, sunElev: Double, cameraPitch: Double,
                hFOV: Double, vFOV: Double) -> Bool {
    abs(phi) < hFOV / 2 && abs(sunElev - cameraPitch) < vFOV / 2
}
```

### 3.3 实测校验（决定预测是否可信）

**场景 EV（ISO 100）：**

```swift
/// EV100 = log2(N² / t) − log2(ISO / 100)
func sceneEV100(aperture: Float, durationSec: Double, iso: Float) -> Double {
    log2(Double(aperture * aperture) / durationSec) - log2(Double(iso) / 100)
}
```

| EV100 | 典型场景 |
|---|---|
| ≥ 14 | 晴天直射阳光（海滩、雪地可达 16） |
| 12 – 13.9 | 阴天、晴天阴影处 |
| 10 – 11.9 | 浓阴、日出日落 |
| 7 – 9.9 | 明亮室内、蓝调时刻 |
| < 7 | 夜景、昏暗室内 → 提示切换到系统相机夜间模式 |

> 场景 EV 是从自动曝光的结果反推出来的，会受到 Smart HDR 等处理的影响，阈值需要实测校准【待验证】。

**人脸与背景亮度比：** 在分析流的 Y 通道上，分别求人脸框内和人像掩码以外区域的平均亮度，`ratio = 人脸亮度 / 背景亮度`。

**融合规则（LightContext）：**

| 预测 | 实测 | 结论 |
|---|---|---|
| 晴天，太阳高度 > 5° | EV ≥ 13.5 | **直射光**，光向判断可信 |
| 晴天 | EV < 12.5 | **在阴影里**（楼影、树荫）：不使用太阳光向，改为"柔光"处理 |
| 阴天或多云（云量 > 80%） | 任意 | **散射光**：光向不重要，忽略太阳方位 |
| 任意 | EV < 10 且 GPS 精度差，或者天气与实测明显矛盾 | **可能在室内**：关闭太阳相关的逻辑 |
| 任意 | 人脸亮度比 < 0.45 | **实测逆光**（不管预测怎么说） |
| 罗盘精度差（`magneticField.accuracy` 较低） | — | 只给"人脸偏暗"这类基于实测的提示，不给"往哪边走"这类方向提示 |

---

## 4. 场景决策表

记号：**[自动]** 默认自动应用、可以撤销；**[一键]** 显示按钮，由用户点击应用；**[提示]** 只显示文字。

### 4.1 直射光（晴天，太阳高度 > 5°）

| 光向 | 问题 | 站位提示 | 参数 |
|---|---|---|---|
| **顶光**（高度 > 55°） | 眼窝和鼻下有阴影、眯眼 | ① "带 TA 到树荫或屋檐下（脸进阴影、背景保持明亮）" ② 找不到阴影时："让 TA 背对太阳，变成逆光" | 逆光后自动提亮，见下一行 |
| **逆光**（\|φ\| < 45°） | 脸暗、背景过曝 | ① 太阳在画面内时："往左/右挪半步，让太阳藏在 TA 头后" ② "走近到 2 米内" | [自动] 人脸驱动曝光（默认开）；如果人脸亮度比仍然 < 0.45 → 曝光补偿 +0.7（最大 +1.3）；[一键] 补光（闪光灯，距离 ≤ 3 m 时才显示） |
| **侧光**（45° ≤ \|φ\| < 135°） | 阴阳脸（太阳高度高时明显） | 太阳低于 20°：**最好的光**，提示"光线很好"。太阳高于 20°："让 TA 脸转向太阳一侧约 30°" | 不调整 |
| **顺光**（\|φ\| ≥ 135°） | 眯眼、画面平淡；太阳低时拍照者的影子会落到 TA 身上 | ① "绕着 TA 往左/右走约 60°，变成侧光" ② 太阳高度 < 15°："注意自己的影子" | [自动] 曝光补偿 −0.3，保护高光 |

### 4.2 黄金时刻、蓝调时刻

| 时段 | 提示 | 参数 |
|---|---|---|
| 黄金时刻之前 30 分钟（计划提示） | "日落前 X 分钟光线最好，建议到西侧开阔处"（方向按太阳方位换算成"西/西南"） | — |
| 黄金时刻，侧光或逆光 | "很好的光！试试让 TA 侧身对着光" | [一键] "保留暖色"：锁定白平衡约 5200K，防止自动白平衡把暖色校正掉【效果待验证】 |
| 黄金时刻，逆光且太阳入画 | 两种玩法：① 剪影 ② 轮廓光 | [一键] 剪影：曝光补偿 −1.0，对焦锁在人，曝光以天空为准；[一键] 轮廓光：+0.7 + 补光 |
| 蓝调时刻 | "天空很漂亮，人站在路灯或店铺灯光下" | EV < 9 时：提示人保持不动，开启 Live Photo 防抖 |

### 4.3 散射光、特殊天气

| 天气 | 提示 | 参数 |
|---|---|---|
| 阴天 | "阴天光线柔和，适合拍特写；避开灰白天空作为大面积背景" | [自动] +0.3 |
| 雪地、白沙滩（EV ≥ 15 且画面平均亮度高） | — | [自动] +0.7（防止画面发灰） |
| 雨天 | "注意镜头上的水滴"（同时启用镜头脏污检测）；"地面倒影可以入画" | — |
| 雾、霾（能见度 < 2 km） | "远景会发灰，靠近拍" | — |
| 夜间（EV < 7） | "光线太暗，建议用系统相机夜间模式" | 不尝试自行处理 |

### 4.4 自动设置策略（AutoSettingsPolicy）

| 设置 | 默认 | 范围、条件 | 原因 |
|---|---|---|---|
| 人脸驱动自动曝光 | 保持系统默认（开） | `isFaceDrivenAutoExposureEnabled`【能否手动开关待验证】 | 系统已经做得很好 |
| 曝光补偿 | [自动] | −1.0 ~ +1.3；以 0.33 EV/秒的速度平滑过渡；**用户手动调过后，本次取景不再自动覆盖** | 唯一和 quality 优先级兼容的曝光调整方式 |
| 补光（闪光灯） | [一键] | 只在逆光、距离 ≤ 3 m、人脸亮度比 < 0.45 时显示 | 闪光会改变画面风格，必须由用户决定 |
| 白平衡 | [一键] | 只在黄金时刻提供"保留暖色" | 自动白平衡在其他情况下已经很好 |
| 镜头/焦段 | [一键] | 见第 5 节 | 自动变焦会让帮拍者困惑 |
| 手动 ISO、快门 | **不做** | — | 只在 `speed` 优先级下生效，会失去多帧融合 |
| 拍摄优先级 | 固定 `quality`；人在动时自动切换到快速连拍 | — | 抓拍时保证不漏拍 |

```swift
final class CameraSettingsApplier {
    private var userOverrodeBias = false
    private var currentBias: Float = 0

    func apply(targetBias: Float, on device: AVCaptureDevice) {
        guard !userOverrodeBias else { return }
        let clamped = max(device.minExposureTargetBias, min(device.maxExposureTargetBias, targetBias))
        // 平滑：每次调用最多移动 0.1 EV（10 Hz 调用 ≈ 1 EV/秒；按需要调整）
        let step = max(-0.1, min(0.1, clamped - currentBias))
        guard abs(step) > 0.01 else { return }
        currentBias += step
        do {
            try device.lockForConfiguration()
            device.setExposureTargetBias(currentBias, completionHandler: nil)
            device.unlockForConfiguration()
        } catch { /* 记录日志，不打断取景 */ }
    }

    func userDidAdjustBias() { userOverrodeBias = true }    // 系统曝光滑杆被用户拖动时调用
    func resetForNewSession() { userOverrodeBias = false; currentBias = 0 }
}
```

---

## 5. 距离与焦段（前进 / 后退 / 换镜头）

### 5.1 距离估计

优先级：**深度数据 > 眼距估算 > 身高估算**。

```swift
/// 焦距（像素）：由水平视场角和分析流宽度换算
func focalPx(hFOVDeg: Double, imageWidthPx: Double) -> Double {
    (imageWidthPx / 2) / tan(hFOVDeg * .pi / 360)
}

/// 正脸时用瞳距估算：成人平均约 63 mm
func distanceFromEyes(ipdPx: Double, fPx: Double) -> Double { fPx * 0.063 / ipdPx }

/// 全身站立时用身高估算：默认 1.65 m（可以在设置里改成被拍者的身高）
func distanceFromHeight(bodyPx: Double, fPx: Double, heightM: Double = 1.65) -> Double {
    fPx * heightM / bodyPx
}
```

- 眼距只在正脸（`|yaw| < 0.15`）时使用，侧脸时测得的眼距会偏小，导致距离偏大。
- 有 `AVCaptureDepthDataOutput`（LiDAR 或双摄视差）时，直接取人脸区域的中位深度。
- 结果用 One Euro Filter 平滑；置信度低于阈值时，距离类提示不出现。

### 5.2 焦段与距离建议

人像的透视由**拍摄距离**决定，不由焦段决定：离得太近，用广角会让脸变形。

| 景别（来自构图引擎） | 推荐等效焦距 | 推荐距离 | 典型问题 → 提示 |
|---|---|---|---|
| 特写 | 2×–3×（约 48–77 mm） | 1.5 – 2.5 m | 1× 且距离 < 1.0 m → **"切到 2×，后退 N 步"**（脸会变形） |
| 半身 | 2×（约 48 mm） | 2 – 3.5 m | 1× 且距离 < 1.5 m → "切到 2×，后退 N 步" |
| 全身 | 1× 或 2× | 3 – 6 m | 0.5× 且人在画面边缘 → "换 1×"（边缘拉伸会让人变形） |
| 环境人像 | 0.5× / 1× | 不限 | 人太小 → "前进 N 步" |
| 逆光补光 | — | ≤ 3 m | 补光开启且距离 > 3 m → "走近到 3 米以内，补光才有效" |

**步数换算（换镜头时保持取景范围不变）：**

```swift
/// 换镜头时，要保持人在画面中的大小不变，距离需要按焦段比例缩放
func stepsToKeepFraming(currentDistanceM d1: Double, fromZoom z1: Double, toZoom z2: Double,
                        stepLengthM: Double = 0.7) -> (newDistance: Double, steps: Int) {
    let d2 = d1 * z2 / z1
    return (d2, Int(((d2 - d1) / stepLengthM).rounded()))   // 正数 = 后退
}
// 例：1× 下距离 1.0 m 拍半身 → 换 2× 需要 2.0 m → 后退约 1 步
```

**和构图引擎的分工：** 构图引擎的 `scale` 规则判断"人在画面里太大还是太小"；距离规则判断"在当前焦段下，这个距离会不会导致变形，或者让补光失效"。两条规则同时触发时，由仲裁器合并为一个动作，比如"切到 2×，后退 1 步"。

---

## 6. 与构图引擎的整合

### 6.1 新增的 Action

```swift
extension Action {
    // 已有：stepBack, stepForward, pan, tilt, …
    // 新增：
    case steps(Int)                         // 正数后退，负数前进；替代不带数量的 stepBack/stepForward
    case switchZoom(to: Double)             // 一键切换镜头
    case orbit(degrees: Double)             // 拍照者绕着被拍者走；正数 = 顺时针（从上往下看）
    case subjectTurn(degrees: Double)       // 让被拍者转身
    case moveToShade
    case hideSunBehindSubject(dx: CGFloat)  // 往左/右挪，让太阳藏到人头后
    case enableFill                         // 一键补光
    case applyBias(Float)                   // 只用于展示"已自动提亮"状态
}
```

### 6.2 新增的规则和优先级

| 规则 | 严重度 | 在构图规则中的位置 |
|---|---|---|
| `light.lowLight`（夜间） | critical | 和 `head.cut` 同级 |
| `distance.distortion`（广角离得太近） | major | 在 `limbCut` 之后 |
| `light.backlit`、`light.sunInFrame` | major | 在 `feet.floating` 之后 |
| `light.harshTop`、`light.flatFront` | minor | 在 `scale` 之前 |
| `distance.fillRange` | minor | 只在补光开启时检查 |
| `light.goldenHourSoon` | 计划提示 | 不进入实时仲裁，显示在开始页 |

**原则：先解决"废片"问题（切头、歪斜），再解决光线，最后才是锦上添花。** 光线类提示的进入延迟设为 1.0 秒（比构图的 minor 还慢），因为人和光的位置调整需要时间，过早提示会让人烦躁。

### 6.3 "绕位"提示的计算

```swift
/// 目标：让相机方位与太阳的夹角 φ 落到目标区间，例如顶光转逆光时目标 |φ| ≈ 20°，顺光转侧光时目标 |φ| ≈ 70°
/// 拍照者绕着被拍者转动 θ 后，相机方位也改变 θ，所以需要的转动量 = 当前 φ − 目标 φ（取同号、最近的方向）
func orbitDegrees(currentPhi: Double, targetAbsPhi: Double) -> Double {
    let target = currentPhi >= 0 ? targetAbsPhi : -targetAbsPhi
    var delta = currentPhi - target
    while delta > 180 { delta -= 360 }; while delta < -180 { delta += 360 }
    return delta   // 用 orbit(degrees:) 展示为"绕着 TA 往左/右走约 X°"，同时提示被拍者转身跟着镜头
}
```

UI 上用一个小的俯视图示：中心是被拍者，一个弧形箭头指向拍照者应该走到的位置，太阳图标标出方向。

---

## 7. 隐私与合规

- **定位**：只申请"使用 App 期间"+"粗略位置"；文案说明"用于计算太阳方向和天气，不会上传精确位置"。
- **天气请求**：坐标先四舍五入到 0.1°（约 10 km）再请求和缓存，降低隐私风险。
- **国内**：WeatherKit 的数据出境、处理地在 PIPL 下的合规性未见 Apple 官方说明。国内版本建议优先使用和风天气（QWeather）等境内服务【待确认】。
- **太阳计算、罗盘、实测亮度**：全部在本地完成，不需要联网。

---

## 8. 测试与评测

| 项目 | 方法 | 通过标准 |
|---|---|---|
| 太阳位置精度 | 与 NOAA Solar Calculator 对比 50 个城市、日期组合 | 方位、高度误差 < 0.5° |
| 罗盘可信度 | 在开阔地、街道、室内分别与已知方向对比 | 开阔地误差 < 10°；误差大的场景能被 `magneticField.accuracy` 识别 |
| 光向分类准确率 | 实地采集 200 组（太阳位置、朝向、EV、亮度比、照片），由人标注"逆光/侧光/顺光/顶光/阴影/室内" | 准确率 ≥ 85%；"阴影里"不能被误判为直射 |
| 距离估计误差 | 用卷尺标定 1–6 m | 中位误差 < 15% |
| 自动曝光补偿效果 | 逆光人像：自动 vs 关闭，各 30 组盲测 | 自动组的人脸曝光主观评分显著更好，且没有明显的天空过曝增加 |
| 提示打扰度 | 实地测试的提示频率 | 光线类提示每分钟不超过 2 次 |

**数据采集**：开发版每次拍照时，把 LightContext、全部输入信号和照片一起保存成调试包，用于离线复盘和调阈值（复用 `compose-eval` 工具）。

---

## 9. 排期（1 人，约 4 周）

| 周 | 交付内容 |
|---|---|
| W1 | SunModel（含单元测试）、HeadingModel、ExposureMeter、LumaProbe；调试面板显示太阳方向和 φ |
| W2 | LightContext 融合 + 光线规则 + AutoSettingsPolicy（曝光补偿、补光按钮） |
| W3 | DistanceEstimator（深度 / 眼距 / 身高）+ 距离与焦段规则 + 绕位图示 |
| W4 | 天气接入（WeatherKit / 备选服务）、计划提示、实地采集和阈值调整 |

---

## 10. 待验证 spike 清单

| # | 验证项 | 影响 |
|---|---|---|
| 1 | 用 `exposureDuration`、`iso`、`lensAperture` 反推的 EV 在 Smart HDR 下是否稳定，能否区分"直射"和"阴影" | 决定融合规则的阈值 |
| 2 | `isFaceDrivenAutoExposureEnabled` 能否由 App 控制；人脸驱动曝光和曝光补偿叠加后的效果 | 决定逆光自动提亮的策略 |
| 3 | 锁定白平衡"保留暖色"在 quality 优先级下是否生效、效果是否明显 | 决定是否保留该功能 |
| 4 | 街道环境下罗盘的实际误差，以及 `xTrueNorthZVertical` 在手机竖直握持时的稳定性 | 决定绕位提示是否上线 |
| 5 | WeatherKit 在国内的可用性和合规；QWeather 的接入成本 | 决定国内天气数据源 |
| 6 | 双摄视差深度（非 Pro 机型）在 2–5 m 范围内的精度 | 决定非 Pro 机型的距离估计方式 |
