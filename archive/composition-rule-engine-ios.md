# 构图规则引擎细化方案（仅 iOS）

## 0. 范围

**这期要做：**
- 实时检测三类构图问题：水平/俯仰、裁切、主体位置与大小。
- 把检测结果折算成一条可执行的提示：先给动作，再给原因。
- 提供离线评测工具，用来调阈值。

**这期不做：**
- 姿势匹配、场景识别、大模型。
- 前置摄像头和自拍。
- 地平线位置判断（比如"地平线穿过脖子"），放到后续版本。
- 多人合影的精细构图。MVP 只处理一个主体，多人时退化为整组包围框。

**最低系统版本：iOS 17。** 需要用到 `VNGeneratePersonInstanceMaskRequest`（按人分开的掩码），避免路人的掩码污染主体的判断。

---

## 1. 相对上一版要改的地方

| 问题 | 上一版做法 | 改为 |
|---|---|---|
| 坐标系混乱 | 直接用 Vision 坐标（原点左下、相对缓冲区） | 统一换成**成片坐标**：原点左上，按最终照片画幅归一化 |
| 预览与成片不一致 | 没有处理 | 分析流、预览、成片全部用 4:3，预览改为 `resizeAspect`，所见即所得 |
| 横拍 | 没有处理 | 用重力向量判断握持方向，把关节点旋转到成片坐标 |
| 路人干扰 | 整体人像掩码 | 按人分开的实例掩码，加主体选择和跟踪 |
| 裁切判断 | 只看关节距边缘的距离，太粗 | **肢体线段与画框求交**；关节缺失时外推线段 |
| 朝向判断 | 鼻子相对两耳，一侧耳朵被挡就失效 | 鼻子相对肩中点的偏移，用肩宽归一化 |
| 三分法 | 强行要求放在三分线上 | 改为"**前方空间/后方空间**比例"加"居中或三分，二选一" |
| 仰拍矛盾 | "脚贴底边"和"手机竖直"会互相打架 | 合并成一个动作："手机放低，保持竖直" |
| 仲裁 | 只做了简单防抖 | 改为状态机：进入防抖、离开保持、被忽略后降级、手在动时静默 |

---

## 2. 模块结构

```
CameraAssist.xcodeproj
├─ App/                      UI、调试面板
├─ Packages/
│  ├─ CompositionKit/        ★ 纯 Swift，不依赖 UIKit/Vision，可单元测试
│  │   ├─ Model/             Frame、Subject、Finding、Action
│  │   ├─ Geometry/          线段与画框求交、坐标变换
│  │   ├─ Classify/          ShotType（带迟滞）、Facing
│  │   ├─ Rules/             LevelRule、TiltRule、HeadRule、LimbCutRule、
│  │   │                     FeetRule、LeadRoomRule、PlacementRule、ScaleRule、EdgeRule
│  │   ├─ Arbiter/           HintArbiter 状态机
│  │   └─ Config/            Thresholds.json（所有阈值外置）
│  └─ PerceptionKit/         Vision、CoreMotion 适配层 → 输出 Frame
│      ├─ CaptureSession     4:3、分析流 640×480
│      ├─ PoseProvider       VNDetectHumanBodyPoseRequest
│      ├─ MaskProvider       VNGeneratePersonInstanceMaskRequest → MaskSummary
│      ├─ MotionProvider     CMDeviceMotion（重力、角速度）
│      └─ SubjectTracker     选主体 + 按 IoU 跟踪
└─ Tools/
   └─ compose-eval/          macOS 命令行：同一份 Vision 代码 + CompositionKit 跑标注集
```

> **关键设计：** Vision 在 macOS 上也能用，所以 `compose-eval` 可以复用与线上完全相同的感知层和规则代码批量跑照片，离线结果与线上一致。

---

## 3. 数据模型

```swift
// 成片坐标：原点在左上，x 向右、y 向下，范围 [0,1]，按最终照片画幅归一化
public struct Joint { public let p: CGPoint; public let conf: Float }

public enum JointID: String, CaseIterable {
    case nose, neck, lEye, rEye, lEar, rEar
    case lShoulder, rShoulder, lElbow, rElbow, lWrist, rWrist
    case root, lHip, rHip, lKnee, rKnee, lAnkle, rAnkle
}

public struct MaskSummary {          // 由实例掩码降采样后扫描得到，耗时 <1ms
    public let bbox: CGRect          // 主体掩码的包围框
    public let touchesTop: Bool      // 顶部 1% 行内主体像素是否超过阈值
    public let touchesLeft: Bool, touchesRight: Bool, touchesBottom: Bool
}

public struct Subject {
    public let joints: [JointID: Joint]   // 只保留 conf ≥ 0.3 的关节
    public let mask: MaskSummary?
    public let trackID: Int
    public func p(_ j: JointID) -> CGPoint? { joints[j]?.p }
}

public struct Attitude {
    public let rollDeg: Double        // 相对握持方向的画面倾斜
    public let elevationDeg: Double   // 镜头仰俯，0 = 平视
    public let angularSpeed: Double   // rad/s，用来判断手是否在动
    public let isFlatish: Bool        // |g.z| > 0.8 时 roll 不可靠
}

public struct Frame {
    public let t: TimeInterval
    public let subject: Subject?
    public let otherSubjects: Int
    public let attitude: Attitude
}

// —— 规则输出 ——
public enum Severity: Int, Comparable {
    case critical = 3   // 废片级：切头、严重歪
    case major = 2      // 明显不好看：关节裁切、脚悬空
    case minor = 1      // 锦上添花：位置、留白
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public enum Action: Equatable {     // 给帮拍者的动作，文案在单独的本地化表
    case rotate(clockwise: Bool)
    case holdVertical
    case lowerPhone, raisePhone
    case stepBack, stepForward
    case pan(dx: CGFloat)           // 正数 = 镜头往右移，主体在画面中左移
    case tilt(dy: CGFloat)          // 正数 = 镜头往下移
    case cropTighter, cropLooser    // 二选一的建议
}

public struct Finding: Identifiable {
    public let id: String           // 如 "limbCut.bottom.knee"
    public let rule: String         // 所属规则，仲裁时按规则去重
    public let severity: Severity
    public let actions: [Action]    // 可多选，UI 只显示第一个
    public let metric: Double       // 偏差量，0 = 刚好合格；用于判断"是否在改善"
    public let target: CGPoint?     // 可选：画面上的目标位置（用来画目标圈）
}

public protocol CompositionRule {
    var name: String { get }
    func evaluate(_ f: Frame, _ ctx: RuleContext) -> [Finding]   // 纯函数，无状态
}

public struct RuleContext {
    public let shot: ShotType
    public let facing: Facing
    public let cfg: Thresholds
}
```

**规则是无状态的纯函数，所有跟时间有关的逻辑（防抖、迟滞、冷却）都放在仲裁器和分类器里。** 这样每条规则都可以用固定输入做单元测试。

---

## 4. 感知层要点

### 4.1 坐标变换（Vision → 成片坐标）

```swift
/// Vision 归一化坐标（原点左下、相对传入的图像方向）→ 成片坐标（原点左上）
/// 采集统一用竖持方向（.right）喂给 Vision，再按握持方向把结果旋转到成片坐标
func toFrame(_ v: CGPoint, grip: Grip) -> CGPoint {
    let up = CGPoint(x: v.x, y: 1 - v.y)            // 先翻成左上原点
    switch grip {
    case .portrait:          return up
    case .landscapeLeft:     return CGPoint(x: 1 - up.y, y: up.x)
    case .landscapeRight:    return CGPoint(x: up.y,     y: 1 - up.x)
    case .portraitUpsideDown:return CGPoint(x: 1 - up.x, y: 1 - up.y)
    }
}
```

- **握持方向**由重力向量判断，带 ±10° 迟滞，避免在 45° 附近来回切换。
- 拍照时把同一个方向写入 EXIF，保证分析结果与成片一致。
- 采集配置：`sessionPreset = .photo`，分析流取 4:3、640×480；预览层用 `.resizeAspect`。

### 4.2 主体选择与跟踪（SubjectTracker）

1. 对每个检测到的人计算得分：`score = 面积 × (1 − 0.5 × 到画面中心的距离)`。
2. 上一帧主体与本帧候选的 IoU > 0.3 时，得分 × 1.5，增加粘性，防止主体在两人之间跳动。
3. 如果有两人的面积比 < 1.5 且两人相邻，就合并成一个"组主体"：包围框取并集，关节点类规则跳过，只跑掩码和包围框类规则。
4. 用姿态的包围框与实例掩码求 IoU，配对出每个人自己的掩码。

### 4.3 MaskSummary 计算

- 实例掩码降采样到约 128×96。
- 扫描主体掩码所在的行和列，得到 bbox 和四个 `touches*` 标志。触边的判定是：边缘 1% 宽的条带内，主体像素超过该条带长度的 2%。
- 掩码低频运行（8 fps），中间帧复用上一次结果，并按姿态包围框的位移做平移补偿。

### 4.4 关节平滑

每个关节的 x、y 分别加 One Euro Filter（参数先取 `minCutoff=1.0, beta=0.01, dCutoff=1.0`）。关节连续 3 帧丢失后清空它的滤波状态，避免重新出现时从旧位置拖过来。

---

## 5. 分类器（带迟滞）

### 5.1 ShotType（景别）

| 景别 | 进入条件 | 退出条件 |
|---|---|---|
| `environmental` 环境人像 | 主体高度 < 0.30 | 主体高度 > 0.36 |
| `fullBody` 全身 | 至少一个脚踝可见，且不是环境人像 | 两个脚踝都丢失超过 0.5 秒 |
| `halfBody` 半身 | 胯部可见，脚踝不可见 | — |
| `closeUp` 特写 | 胯部不可见，肩部可见 | — |
| `unknown` | 关节太少 | — |

景别切换需要连续 0.4 秒满足新条件。**景别决定哪些规则启用、用哪组阈值。**

### 5.2 Facing（朝向）

```swift
/// yaw ≈ (鼻子.x − 肩中点.x) / 肩宽；正数 = 朝向画面右侧
func facingYaw(_ s: Subject) -> Double? {
    guard let n = s.p(.nose), let l = s.p(.lShoulder), let r = s.p(.rShoulder) else { return nil }
    let w = abs(l.x - r.x)
    // 侧身到肩宽接近 0 时，比值不可靠，改用"哪只耳朵可见"兜底
    guard w > 0.02 else {
        switch (s.p(.lEar) != nil, s.p(.rEar) != nil) {
        case (true, false): return -0.8   // 只看到左耳 → 脸朝画面左（后置摄像头、非镜像）
        case (false, true): return 0.8
        default: return nil
        }
    }
    return Double((n.x - (l.x + r.x) / 2) / w)
}
// 分级：|yaw| < 0.15 正面；0.15–0.35 微侧（不触发视线留白）；> 0.35 侧向
```

> 耳朵兜底的左右方向必须用真机验证。Vision 的 left/right 指的是被拍者自身的左右。

---

## 6. 规则清单（阈值全部写在 `Thresholds.json`）

### A. 设备姿态类（只依赖 IMU，任何景别都启用）

| ID | 前置条件 | 触发 / 解除 | 严重度 | 动作 |
|---|---|---|---|---|
| `level.roll` | 非平放（`!isFlatish`） | \|roll\| > 2.5° 触发；< 1.0° 解除 | 歪 > 5° 为 critical，否则 major | `rotate(clockwise:)` |
| `tilt.vertical` | 景别为 fullBody 或 environmental | \|elevation\| > 10° 触发；< 6° 解除 | major | `holdVertical` |

水平线 UI 总是显示（绿、黄、红三色），**不经过仲裁**；仲裁只决定是否额外显示文字提示。

### B. 裁切类

#### B1 `head.cut`：切头

- **前置条件**：有掩码，或者鼻子可见。
- **判定**：掩码 `touchesTop` 为真，且掩码顶部所在的列与头部区域重叠。头部区域取鼻子 x ± 1.2 × 眼距，避免把举起的手误判成头。没有掩码时，用估算的头顶 `headTopY = nose.y − 0.9 × |neck.y − nose.y|`，判定 `headTopY < 0.005`。
- **例外**：特写景别下，如果画面顶边位于额头以上、头顶以下，属于有意的大特写裁切（tight crop），不报。
- **严重度**：critical
- **动作**：`tilt(dy: −Δ)`（镜头上抬）或 `stepBack`

#### B2 `limbCut.*`：裁在关节上（核心算法）

做法是把画框四条边与每段肢体线段求交，看交点离关节有多近。

```swift
struct Segment { let a: JointID; let b: JointID }   // a 靠近躯干，b 靠近末端

let chains: [[JointID]] = [
    [.lShoulder, .lElbow, .lWrist], [.rShoulder, .rElbow, .rWrist],
    [.lHip, .lKnee, .lAnkle],       [.rHip, .rKnee, .rAnkle],
]

/// 链条末端关节缺失时，按上一段的方向和长度外推一段（取上段长度 × ratio）
/// 大腿→小腿取 1.0，大臂→小臂取 0.9
func extendedPoints(_ s: Subject, chain: [JointID], ratio: [CGFloat]) -> [(JointID, CGPoint, Bool)] {
    // 返回 [(关节, 位置, 是否外推)]；只外推一次，外推出来的点可以在画面之外
    // …实现略…
}

enum Edge { case top, bottom, left, right }

struct CutHit { let edge: Edge; let nearJoint: JointID; let t: CGFloat } // t: 交点在该段上的参数 0…1

func limbCuts(_ s: Subject, cfg: Thresholds) -> [CutHit] {
    var hits: [CutHit] = []
    for chain in chains {
        let pts = extendedPoints(s, chain: chain, ratio: [1.0, 0.9])
        for i in 0..<(pts.count - 1) {
            let (ja, pa, _) = pts[i], (jb, pb, _) = pts[i + 1]
            // 一端在画面内、一端在画面外，才算被边缘切断
            guard inFrame(pa) != inFrame(pb), let (edge, t) = intersectFrame(pa, pb) else { continue }
            // 交点离段的哪一端近
            if t < cfg.jointZone      { hits.append(.init(edge: edge, nearJoint: ja, t: t)) }
            else if t > 1 - cfg.jointZone { hits.append(.init(edge: edge, nearJoint: jb, t: t)) }
            else if isShin(ja, jb)    { hits.append(.init(edge: edge, nearJoint: jb, t: t)) } // 小腿中段也算差
        }
    }
    return hits
}
// cfg.jointZone 默认 0.18（即离关节 18% 段长以内算"裁在关节"）
```

| 被切的位置 | 判定 | 动作（主选 / 备选） |
|---|---|---|
| 膝盖附近（底边） | `nearJoint ∈ {lKnee, rKnee}` | `lowerPhone`、`stepBack`（留出脚）/ `cropTighter`（裁到大腿中段） |
| 小腿中段 | `isShin` | 同上 |
| 脚踝（脚被切） | `nearJoint ∈ {lAnkle, rAnkle}` | `tilt(dy:+)` 或 `stepBack` |
| 手腕、手肘（侧边） | 交点在左右边 | `pan(dx:)` 往被切那侧移，或 `stepBack` |
| 大腿中段 | t ∈ [jointZone, 1−jointZone] | **合格，不报** |

- **严重度**：major。
- **id**：`limbCut.<边>.<关节>`。同一条边只报一个，按 膝盖 > 脚踝 > 手肘 > 手腕 取一个。
- **手臂例外**：手腕的置信度 < 0.5 时不报，因为手常常插兜或藏在身后，被误判为"出画"。

#### B3 `headroom.*`：头顶留白

| 景别 | 合格范围（头顶到画面上边，占画面高度） | 超出时的动作 |
|---|---|---|
| closeUp | 0.02 – 0.12 | 太多 → `tilt(dy:+)`、`stepForward` |
| halfBody | 0.04 – 0.18 | 同上 |
| fullBody | 0.04 – 0.20 | 太多 → `tilt(dy:+)`；太少 → `stepBack` |
| environmental | 不检查 | — |

严重度为 minor。头顶完全被切的情况由 B1 处理，这里只管留白是否过多或略少。

#### B4 `feet.floating`：脚悬空（显腿长）

- **前置条件**：景别为 fullBody，脚踝可见。
- **计算**：`footBottom = max(ankle.y) + 0.035 × 主体高度`（脚掌的估计长度），`gap = 1 − footBottom`。
- **判定**：`gap > 0.08` 时触发，`gap < 0.05` 时解除。
- **合并动作**：如果 `tilt.vertical` 同时生效，这两条合并为一个动作 `lowerPhone + holdVertical`，文案是"手机放低到腰部、保持竖直，让脚贴近底边"。也就是说，提示放低手机，而不是提示把镜头往下转。
- **严重度**：major。

### C. 位置与大小类

#### C1 `leadRoom`：视线前方留白

- **前置条件**：`|yaw| > 0.35`，景别不是 environmental。
- **计算**：以主体锚点为界，脸朝向那一侧的空间是 `front`，另一侧是 `back`。
- **判定**：`front / back < 1.2` 时触发，`> 1.5` 时解除。
- **目标**：把锚点移到 x = 1/3（朝右时）或 x = 2/3（朝左时）。
- **动作**：`pan(dx:)`，同时在 target 位置画目标圈。
- **严重度**：minor。

#### C2 `placement`：位置模糊区

- **前置条件**：正面（`|yaw| < 0.15`），且 C1 没有触发。
- **合格区**：居中 `|x − 0.5| < 0.05`，或者在三分线上 `|x − 1/3| < 0.06`、`|x − 2/3| < 0.06`。
- **判定**：锚点落在这几个合格区之间的"既不居中也不在三分线"区域。
- **动作**：`pan` 到最近的合格区。
- **严重度**：minor。很多新手画面"差点意思"就是这个原因，但这条提示不应该压过前面的问题。
- **锚点**：closeUp 和 halfBody 用 `nose.x`；fullBody 用两肩中点与两胯中点的平均 x；environmental 用掩码 bbox 中心。

#### C3 `scale`：主体大小

| 景别 | 合格范围（主体高度占画面高度） | 动作 |
|---|---|---|
| fullBody | 0.50 – 0.88 | 太小 → `stepForward`；太大 → `stepBack` |
| environmental | ≥ 0.12 | 太小 → `stepForward` |
| halfBody、closeUp | 不检查 | — |

严重度为 minor。

#### C4 `edge.crowd`：人太贴边

- **判定**：主体包围框距左右边缘 < 0.03，而且不属于 B2 的肢体裁切。
- **动作**：`pan` 往贴边的反方向移。
- **严重度**：minor。

### D. 无主体或多人

| 状态 | 处理 |
|---|---|
| 没有主体 | 只保留 A 类规则，提示"对准要拍的人" |
| 多人，组主体 | 跳过 B2、C1、C2；只跑 B1（任何一人被切头都报）、C3、C4 |
| 路人入画 | 这期不处理，放到后续版本 |

---

## 7. 仲裁器（HintArbiter）

### 7.1 每条 Finding 的状态机

```
           持续出现 ≥ enterDelay
 [absent] ─────────────────────▶ [eligible]
    ▲                                │ 被选中显示
    │ 消失 ≥ exitHold               ▼
    └───────────────────────── [shown] ──── 显示 > ignoreAfter 且 metric 没有改善
                                    │                    │
                                    │                    ▼
                                    │              [snoozed]（冷却 snoozeFor 秒，
                                    │               期间降级为只显示图标、不显示文字）
                                    ▼
                                 问题解决
                                    │
                                    ▼
                         显示 ✓ 并轻震（每条规则只震一次）
```

### 7.2 参数默认值

| 参数 | 默认值 | 说明 |
|---|---|---|
| `enterDelay` | critical 0.25 s / major 0.4 s / minor 0.7 s | 越严重的问题越早提示 |
| `exitHold` | 0.3 s | 问题消失后文字再保留一会儿，避免闪烁 |
| `minShow` | 1.2 s | 提示至少显示这么久，再允许被别的提示替换 |
| `ignoreAfter` | 5 s | 显示超过 5 秒且 metric 没有改善 10%，视为用户不想改 |
| `snoozeFor` | 20 s | 被忽略后的冷却时间 |
| `motionMute` | 角速度 > 1.2 rad/s | 手在快速移动时，只显示水平线，不显示文字 |
| `goodHold` | 0.6 s | 没有任何 finding 持续这么久，显示"可以拍 ✓" |

### 7.3 选哪一条显示

1. 先去掉 snoozed 的 finding。
2. 按 `severity` 从高到低排；同一严重度内，按固定顺序：`head.cut > level.roll > limbCut > feet.floating > tilt.vertical > scale > leadRoom > headroom > placement > edge.crowd`。
3. 如果当前显示的 finding 仍然存在且未满 `minShow`，保持不换；**但 critical 可以立即抢占**。
4. **合并规则**：`feet.floating` 与 `tilt.vertical` 合并为一条；同一边的多个 `limbCut` 合并为一条。

### 7.4 核心代码

```swift
public final class HintArbiter {
    struct Track { var firstSeen: TimeInterval; var lastSeen: TimeInterval
                   var shownAt: TimeInterval?; var metricAtShow: Double?
                   var snoozedUntil: TimeInterval = 0 }

    private var tracks: [String: Track] = [:]
    private(set) public var current: Finding?
    private var lastAllClear: TimeInterval?
    private let cfg: ArbiterConfig
    private let order: [String]
    public init(cfg: ArbiterConfig, order: [String]) { self.cfg = cfg; self.order = order }

    public enum Output { case hint(Finding), good, silent, none }

    public func update(_ findings: [Finding], t: TimeInterval, angularSpeed: Double) -> Output {
        let merged = merge(findings)
        let ids = Set(merged.map(\.id))

        // 1) 更新各条 finding 的跟踪状态
        for f in merged {
            var tr = tracks[f.id] ?? Track(firstSeen: t, lastSeen: t)
            tr.lastSeen = t
            tracks[f.id] = tr
        }
        tracks = tracks.filter { t - $0.value.lastSeen < cfg.exitHold || ids.contains($0.key) }

        // 2) 当前提示：显示太久且没有改善 → 进入冷却
        if let c = current, var tr = tracks[c.id], let s = tr.shownAt,
           let m0 = tr.metricAtShow, let now = merged.first(where: { $0.id == c.id }),
           t - s > cfg.ignoreAfter, now.metric > m0 * 0.9 {
            tr.snoozedUntil = t + cfg.snoozeFor; tr.shownAt = nil
            tracks[c.id] = tr; current = nil
        }

        // 3) 手在快速移动时静默
        if angularSpeed > cfg.motionMute { return .silent }

        // 4) 挑出符合显示条件的候选
        let eligible = merged.filter { f in
            guard let tr = tracks[f.id], t >= tr.snoozedUntil else { return false }
            return t - tr.firstSeen >= cfg.enterDelay(f.severity)
        }.sorted(by: rank)

        // 5) 全部合格 → 持续 goodHold 后显示"可以拍"
        guard let top = eligible.first else {
            if let c = current, let tr = tracks[c.id], t - tr.lastSeen < cfg.exitHold { return .hint(c) }
            current = nil
            if merged.isEmpty { lastAllClear = lastAllClear ?? t } else { lastAllClear = nil }
            if let a = lastAllClear, t - a >= cfg.goodHold { return .good }
            return .none
        }
        lastAllClear = nil

        // 6) 未满最短显示时间则不换；critical 可以抢占
        if let c = current, c.id != top.id, ids.contains(c.id),
           let s = tracks[c.id]?.shownAt, t - s < cfg.minShow,
           top.severity <= c.severity {
            return .hint(merged.first { $0.id == c.id }!)
        }

        if current?.id != top.id {
            tracks[top.id]?.shownAt = t
            tracks[top.id]?.metricAtShow = top.metric
        }
        current = top
        return .hint(top)
    }

    private func rank(_ a: Finding, _ b: Finding) -> Bool {
        if a.severity != b.severity { return a.severity > b.severity }
        return (order.firstIndex(of: a.rule) ?? .max) < (order.firstIndex(of: b.rule) ?? .max)
    }

    private func merge(_ fs: [Finding]) -> [Finding] {
        // feet.floating + tilt.vertical → "lowerAndVertical"；同一条边的多个 limbCut 只留优先级最高的
        // …实现略…
        fs
    }
}
```

---

## 8. 文案与 UI 映射

文案不写在规则里，单独放进 `Hints.strings`，按 **动作 + 原因** 两部分组织：

| Action | 主文案（帮拍者视角） | 副文案（原因，小字） |
|---|---|---|
| `rotate(clockwise: true)` | 手机顺时针转一点 | 画面歪了 |
| `holdVertical` | 手机拿竖直 | 不然楼和人会变形 |
| `lowerPhone` + `holdVertical` | 手机放到腰部、保持竖直 | 脚贴底边更显腿长 |
| `stepBack` | 退后一步 | 膝盖被切了 |
| `cropTighter` | 或者往上只拍到大腿 | （作为备选，用小字显示） |
| `pan(dx:)` | 镜头往左/右移一点 | 让人看的方向多留点空间 |
| `tilt(dy:)` | 镜头往上/下抬一点 | 头顶空太多 |

**视觉元素：**
- 水平线：始终显示，三色。
- 目标圈：有 `target` 时显示，同时画一个从当前锚点指向目标的箭头。
- 被切的关节：在关节位置闪一个红点，2 次后停止。
- 调试面板：显示所有 finding、各自状态、metric 和阈值，**只在开发版里有**。

---

## 9. 配置外置（Thresholds.json）

```json
{
  "version": 1,
  "level":   { "enterDeg": 2.5, "exitDeg": 1.0, "criticalDeg": 5.0 },
  "tilt":    { "enterDeg": 10, "exitDeg": 6 },
  "limbCut": { "jointZone": 0.18, "minWristConf": 0.5, "extendRatio": { "leg": 1.0, "arm": 0.9 } },
  "feet":    { "enterGap": 0.08, "exitGap": 0.05, "footLenRatio": 0.035 },
  "headroom": {
    "closeUp":  [0.02, 0.12],
    "halfBody": [0.04, 0.18],
    "fullBody": [0.04, 0.20]
  },
  "leadRoom":  { "minYaw": 0.35, "enterRatio": 1.2, "exitRatio": 1.5 },
  "placement": { "centerTol": 0.05, "thirdTol": 0.06 },
  "scale":     { "fullBody": [0.50, 0.88], "environmentalMin": 0.12 },
  "edge":      { "minMargin": 0.03 },
  "arbiter": {
    "enterDelay": { "critical": 0.25, "major": 0.4, "minor": 0.7 },
    "exitHold": 0.3, "minShow": 1.2, "ignoreAfter": 5, "snoozeFor": 20,
    "motionMute": 1.2, "goodHold": 0.6
  }
}
```

- 开发版支持在调试面板里实时修改阈值并立即生效。
- 上线后可以接远程配置，按版本号灰度下发。

---

## 10. 测试与评测

### 10.1 单元测试（CompositionKit，纯逻辑）

- 每条规则：用手工构造的 `Subject` 夹具覆盖"刚好合格 / 刚好触发 / 迟滞区间"三种情况。
- 几何：线段与画框求交、外推、坐标旋转，覆盖四种握持方向。
- 仲裁器：用脚本化的时间序列驱动（模拟 `t` 推进），断言防抖、抢占、冷却、合并、静默的行为。

### 10.2 离线评测（compose-eval，macOS 命令行）

```
compose-eval --images ./dataset --labels labels.json --config Thresholds.json --report out.html
```

- **数据集**：300–500 张旅拍人像。全身、半身、特写、环境人像各约 1/4，并包含横拍、多人、背光、侧身。
- **标注**：由 2 名摄影师独立标注每张图存在哪些问题（标签与规则 ID 一一对应）。只保留两人一致的标签。
- **指标**：每条规则的精确率和召回率。**上线门槛：精确率 ≥ 85%**（误报伤害信任，比漏报更严重）。召回率 ≥ 60% 即可。
- **报告**：HTML，逐张显示关节点、掩码、触发的规则，并把误报和漏报单独列出，方便调阈值。

### 10.3 时序评测（真机录制回放）

- 在真机上录制预览帧、IMU 数据、Vision 结果（可选），保存成 `.capturelog`。
- 回放到仲裁器，统计：每分钟提示切换次数（目标 < 8 次）、从出现问题到显示提示的延迟、"可以拍"的误报率。

### 10.4 性能（Instruments，目标 iPhone 12）

| 项目 | 目标 |
|---|---|
| 姿态估计（15 fps）耗时 | < 15 ms |
| 实例掩码（8 fps）耗时 | < 25 ms |
| MaskSummary + 全部规则 + 仲裁 | < 2 ms |
| 分析流水线总 CPU 占用 | < 35% |
| 连续使用 15 分钟后的发热状态 | 不进入 `.serious` |

发热时降频：`.fair` 时姿态降到 10 fps；`.serious` 时姿态 8 fps，掩码 4 fps。

---

## 11. 排期（1.5 人，约 6 周）

| 周 | 交付内容 |
|---|---|
| W1 | 采集管线（4:3 所见即所得）、坐标变换、握持方向、调试面板显示关节点和掩码 |
| W2 | SubjectTracker、MaskSummary、One Euro Filter、ShotType 和 Facing 分类器 |
| W3 | A 类和 B 类规则（含肢体线段求交）+ 单元测试 |
| W4 | C 类规则、仲裁器状态机、文案、UI 叠加 |
| W5 | compose-eval 命令行 + 标注数据集 + 第一轮阈值调整 |
| W6 | 真机录制回放、性能和发热优化、实地测试（2 个景区） |

---

## 12. 风险与待验证问题

| 风险 | 验证方式 | 备选方案 |
|---|---|---|
| Vision 姿态在长裙、背光、侧身时关节丢失或错位 | W2 用数据集统计关节可用率 | 裁切规则在关节置信度低时退化为只用掩码边缘判断 |
| 实例掩码在 8 fps 下跟不上快速移动 | 真机录制回放 | 中间帧用姿态包围框的位移做补偿 |
| 用户会不会照提示去改 | 埋点统计提示后的修正率 | 修正率低于 30% 的规则，下调优先级或者删掉 |
| 规则太保守，有意为之的创意构图被误报 | 让摄影师对误报做"有意构图"标注 | 增加"创意模式"开关，只保留 A 类和 B1 |
| 耳朵兜底的朝向方向判断不准 | W2 真机验证 | 改用 `VNDetectHumanBodyPose3DRequest` 估计身体朝向（iOS 17） |
