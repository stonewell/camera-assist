# Spike #1: 画质盲测与快门时延评测规范与数据契约

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
