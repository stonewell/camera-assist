# Spike #1: 画质盲测与快门时延评测规范与数据契约

> ## ⚠️ 数据可信度声明（2026-10-30 审计）
>
> **本文出现的所有量化数字均为 `SYNTHETIC_SELF_TEST`**：由 `scripts/evaluate-capture-quality.py` 硬编码 native/assist 两组理想化指标后自断言生成（见该脚本 `:19-53`），没有任何真实照片输入，**不构成真机 SLA 证据**。
>
> - 「97.8%」「84.5ms」「24MP 5712×4284」等数值只说明脚本中的阈值判断逻辑自洽，不代表本 App 在真机上的表现。
> - 真实结论必须在 iPhone（15/16 Pro）上实测：分辨率是否达到 **5712×4284（24MP）**、按压快门到 `didFinishProcessingPhoto` 的真实时延。
> - 在 TASK-02 完成前，无真实输入的门禁应输出 `SYNTHETIC_SELF_TEST`（当前脚本尚未输出该标记）；此类结果**不得**作为验收或发布依据。
> - 状态与执行顺序以 [`development-priorities.md`](development-priorities.md) 第 7、8 节为准。

## 1. 目标与背景

Camera Assist 取景器通过自建 `AVCaptureSession` 与 `AVCapturePhotoOutput` 采集照片。为消除自建相机画质弱于 iOS 原生系统相机的用户顾虑，必须通过严格的实拍双盲对比评测（Spike #1），确保成片质量达到原生相机的 95% 以上。

---

## 2. 核心量化指标 (Metrics)

| 指标维度 | 评估算法 / 测量方法 | 验收阈值 (SLA) | 优先级 |
|---|---|---|---|
| **成片分辨率** | 像素尺寸统计（宽 × 高） | 严格达到 24MP（5712 × 4284） | P0 |
| **画面清晰度** | 边缘锐度 / 灰度梯度方差比率 (Sharpness Ratio) | 自建管线 ≥ 原生相机的 **95.0%** | P0 |
| **快门时延** | 按压快门到 `didFinishProcessingPhoto` 回调耗时 | 平均延迟 **< 100 ms**（极值 < 200 ms） | P0 |
| **动态范围** | 高光溢出率与暗部噪点标准差对比 | 动态范围保真度 ≥ 原生相机的 **92.0%** | P1 |
| **色彩还原** | 24 色标准色卡实测色差 (Delta-E CIE2000) | 平均色差 $\Delta E < 3.5$ | P1 |

---

## 3. 评测执行流程

1. **同机同场景对拍**：
   - 固定三脚架，使用相同 iPhone 15/16 Pro 机型；
   - 分别使用 iOS 原生相机 24MP 模式与 `CaptureKit` 拍摄同视角测试样张；
2. **自动化脚本计算**：
   ```bash
   python3 scripts/evaluate-capture-quality.py --assist assist_photo.heic --native native_photo.heic
   ```
3. **输出评测裁定**：
   - 生成量化对比表格，只有当全部 P0 门禁为 PASS 时，方可准入发布。

> **现状标注（2026-10-30 审计）**：上面的 `--assist/--native` 对比路径目前只是占位实现（打印 `Comparing ...` 后直接返回 0），并未真正解码两张 HEIC 或计算清晰度/时延。真实评测需要先接入读图与指标计算（TASK-02）。

---

## 4. 自动化门禁的已知局限

| 项目 | 现状 | 影响 |
|---|---|---|
| `evaluate-capture-quality.py` | `--self-test` 使用**硬编码**的 native/assist 指标并自断言，输出恒为 PASS | 不能证明任何画质或时延能力 |
| 分辨率 | 脚本中写死 `5712 × 4284` | 真机是否输出 24MP 未验证 |
| 快门时延 | 脚本中写死 `84.5 ms` | 真机按压到回调的时延未测 |
| 动态范围 / 清晰度 | 脚本中写死 `97.8%` 比率 | 无真实样张，无盲测 |

**结论**：Spike #1 当前状态为「部分完成（仅合成自测）」。达成 P0 门禁需要在 iPhone 上用 `CaptureKit` 与系统相机同场景对拍，再由真实输入跑通评测脚本。

---

## 5. 复现命令

```bash
# 全量门禁（Rust/Swift/体积/模型/评测脚本等 10 步）
./scripts/verify-all.sh

# Spike #1 脚本自测
python3 scripts/evaluate-capture-quality.py --self-test
```

> 注意：`--self-test` **只验证脚本自身的阈值判断逻辑**（硬编码数据 + 自断言），不执行任何真实拍摄或图像分析，不是 Spike #1 的真机结论。
