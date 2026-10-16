use serde::{Deserialize, Serialize};

/// Roll / Horizon leveling thresholds.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LevelThresholds {
    pub enter_deg: f32,
    pub exit_deg: f32,
    pub critical_deg: f32,
    pub ui_green_deg: f32,
}

impl Default for LevelThresholds {
    fn default() -> Self {
        Self {
            enter_deg: 2.5,
            exit_deg: 1.0,
            critical_deg: 5.0,
            ui_green_deg: 1.0,
        }
    }
}

/// Pitch / Vertical tilt thresholds.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TiltThresholds {
    pub enter_deg: f32,
    pub exit_deg: f32,
}

impl Default for TiltThresholds {
    fn default() -> Self {
        Self {
            enter_deg: 10.0,
            exit_deg: 6.0,
        }
    }
}

/// Head crop / boundary thresholds.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HeadThresholds {
    pub mask_top_eps: f32,
    pub head_zone_eye_multiple: f32,
    pub nose_neck_factor: f32,
}

impl Default for HeadThresholds {
    fn default() -> Self {
        Self {
            mask_top_eps: 0.005,
            head_zone_eye_multiple: 1.2,
            nose_neck_factor: 0.9,
        }
    }
}

/// Limb extension ratios for missing terminal joints.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ExtendRatioThresholds {
    pub leg: f32,
    pub arm: f32,
}

impl Default for ExtendRatioThresholds {
    fn default() -> Self {
        Self { leg: 1.0, arm: 0.9 }
    }
}

/// Limb & joint cutting thresholds.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LimbCutThresholds {
    #[serde(default = "default_joint_zone")]
    pub joint_zone: f32,
    #[serde(default = "default_min_wrist_conf")]
    pub min_wrist_conf: f32,
    #[serde(default)]
    pub extend_ratio: ExtendRatioThresholds,
}

fn default_joint_zone() -> f32 {
    0.18
}
fn default_min_wrist_conf() -> f32 {
    0.5
}

impl Default for LimbCutThresholds {
    fn default() -> Self {
        Self {
            joint_zone: 0.18,
            min_wrist_conf: 0.5,
            extend_ratio: ExtendRatioThresholds::default(),
        }
    }
}

/// Floating feet / bottom margin thresholds.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FeetThresholds {
    pub enter_gap: f32,
    pub exit_gap: f32,
    pub foot_len_ratio: f32,
}

impl Default for FeetThresholds {
    fn default() -> Self {
        Self {
            enter_gap: 0.08,
            exit_gap: 0.05,
            foot_len_ratio: 0.035,
        }
    }
}

/// Headroom tolerance range (min, max) per shot framing.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HeadroomThresholds {
    pub close_up: (f32, f32),
    pub half_body: (f32, f32),
    pub full_body: (f32, f32),
}

impl Default for HeadroomThresholds {
    fn default() -> Self {
        Self {
            close_up: (0.02, 0.12),
            half_body: (0.04, 0.18),
            full_body: (0.04, 0.20),
        }
    }
}

/// Lead-room thresholds for side-facing subjects.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LeadRoomThresholds {
    pub min_yaw: f32,
    pub enter_ratio: f32,
    pub exit_ratio: f32,
}

impl Default for LeadRoomThresholds {
    fn default() -> Self {
        Self {
            min_yaw: 0.35,
            enter_ratio: 1.2,
            exit_ratio: 1.5,
        }
    }
}

/// Placement and rule-of-thirds tolerances.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PlacementThresholds {
    pub frontal_max_yaw: f32,
    pub center_tol: f32,
    pub third_tol: f32,
}

impl Default for PlacementThresholds {
    fn default() -> Self {
        Self {
            frontal_max_yaw: 0.15,
            center_tol: 0.05,
            third_tol: 0.06,
        }
    }
}

/// Subject scale (height ratio in frame) thresholds.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ScaleThresholds {
    pub full_body: (f32, f32),
    pub environmental_min: f32,
}

impl Default for ScaleThresholds {
    fn default() -> Self {
        Self {
            full_body: (0.50, 0.88),
            environmental_min: 0.12,
        }
    }
}

/// Screen edge margin thresholds.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EdgeThresholds {
    pub min_margin: f32,
}

impl Default for EdgeThresholds {
    fn default() -> Self {
        Self { min_margin: 0.03 }
    }
}

/// Multi-subject balance and occlusion thresholds.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MultiSubjectThresholds {
    pub max_overlap_iou: f32,
    pub center_balance_tol: f32,
}

impl Default for MultiSubjectThresholds {
    fn default() -> Self {
        Self {
            max_overlap_iou: 0.20,
            center_balance_tol: 0.18,
        }
    }
}

/// ShotType classifier hysteresis thresholds.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ShotTypeThresholds {
    pub environmental_enter: f32,
    pub environmental_exit: f32,
    pub switch_hold: f64,
    pub ankle_lost_hold: f64,
}

impl Default for ShotTypeThresholds {
    fn default() -> Self {
        Self {
            environmental_enter: 0.30,
            environmental_exit: 0.36,
            switch_hold: 0.4,
            ankle_lost_hold: 0.5,
        }
    }
}

/// Arbiter enter delay per severity level.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ArbiterEnterDelay {
    pub critical: f64,
    pub major: f64,
    pub minor: f64,
}

impl Default for ArbiterEnterDelay {
    fn default() -> Self {
        Self {
            critical: 0.25,
            major: 0.40,
            minor: 0.70,
        }
    }
}

/// HintArbiter state machine timing thresholds.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ArbiterThresholds {
    #[serde(default)]
    pub enter_delay: ArbiterEnterDelay,
    #[serde(default = "default_exit_hold")]
    pub exit_hold: f64,
    #[serde(default = "default_min_show")]
    pub min_show: f64,
    #[serde(default = "default_ignore_after")]
    pub ignore_after: f64,
    #[serde(default = "default_snooze_for")]
    pub snooze_for: f64,
    #[serde(default = "default_motion_mute")]
    pub motion_mute: f32,
    #[serde(default = "default_good_hold")]
    pub good_hold: f64,
}

fn default_exit_hold() -> f64 {
    0.3
}
fn default_min_show() -> f64 {
    1.2
}
fn default_ignore_after() -> f64 {
    5.0
}
fn default_snooze_for() -> f64 {
    20.0
}
fn default_motion_mute() -> f32 {
    1.2
}
fn default_good_hold() -> f64 {
    0.6
}

impl Default for ArbiterThresholds {
    fn default() -> Self {
        Self {
            enter_delay: ArbiterEnterDelay::default(),
            exit_hold: 0.3,
            min_show: 1.2,
            ignore_after: 5.0,
            snooze_for: 20.0,
            motion_mute: 1.2,
            good_hold: 0.6,
        }
    }
}

/// Backend-specific partial threshold overrides (e.g. "onnx" vs "vision").
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BackendOverridePatch {
    #[serde(default)]
    pub limb_cut: Option<LimbCutOverride>,
    #[serde(default)]
    pub head: Option<HeadOverride>,
}

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LimbCutOverride {
    pub min_wrist_conf: Option<f32>,
    pub joint_zone: Option<f32>,
}

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HeadOverride {
    pub nose_neck_factor: Option<f32>,
    pub mask_top_eps: Option<f32>,
}

/// Complete typed threshold configuration loaded from shared/config/Thresholds.json.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ThresholdConfig {
    #[serde(default = "default_version", deserialize_with = "deserialize_version")]
    pub version: u32,
    #[serde(default)]
    pub level: LevelThresholds,
    #[serde(default)]
    pub tilt: TiltThresholds,
    #[serde(default)]
    pub head: HeadThresholds,
    #[serde(default)]
    pub limb_cut: LimbCutThresholds,
    #[serde(default)]
    pub feet: FeetThresholds,
    #[serde(default)]
    pub headroom: HeadroomThresholds,
    #[serde(default)]
    pub lead_room: LeadRoomThresholds,
    #[serde(default)]
    pub placement: PlacementThresholds,
    #[serde(default)]
    pub scale: ScaleThresholds,
    #[serde(default)]
    pub edge: EdgeThresholds,
    #[serde(default)]
    pub multi_subject: MultiSubjectThresholds,
    #[serde(default)]
    pub shot_type: ShotTypeThresholds,
    #[serde(default)]
    pub arbiter: ArbiterThresholds,
    #[serde(default)]
    pub backend_overrides: std::collections::HashMap<String, BackendOverridePatch>,
}

fn default_version() -> u32 {
    1
}

fn deserialize_version<'de, D>(deserializer: D) -> Result<u32, D::Error>
where
    D: serde::Deserializer<'de>,
{
    #[derive(Deserialize)]
    #[serde(untagged)]
    enum VersionValue {
        Int(u32),
        Float(f64),
        Str(String),
    }

    match VersionValue::deserialize(deserializer)? {
        VersionValue::Int(v) => Ok(v),
        VersionValue::Float(v) => Ok(v as u32),
        VersionValue::Str(s) => Ok(s.parse::<f64>().map(|v| v as u32).unwrap_or(1)),
    }
}

impl Default for ThresholdConfig {
    fn default() -> Self {
        Self {
            version: 1,
            level: LevelThresholds::default(),
            tilt: TiltThresholds::default(),
            head: HeadThresholds::default(),
            limb_cut: LimbCutThresholds::default(),
            feet: FeetThresholds::default(),
            headroom: HeadroomThresholds::default(),
            lead_room: LeadRoomThresholds::default(),
            placement: PlacementThresholds::default(),
            scale: ScaleThresholds::default(),
            edge: EdgeThresholds::default(),
            multi_subject: MultiSubjectThresholds::default(),
            shot_type: ShotTypeThresholds::default(),
            arbiter: ArbiterThresholds::default(),
            backend_overrides: std::collections::HashMap::new(),
        }
    }
}

impl ThresholdConfig {
    pub fn from_json_str(json_str: &str) -> Result<Self, serde_json::Error> {
        serde_json::from_str(json_str)
    }

    /// Returns a copy of the config with backend-specific overrides applied (e.g., "onnx" or "vision").
    pub fn with_backend(mut self, backend: &str) -> Self {
        if let Some(patch) = self.backend_overrides.get(backend) {
            if let Some(lc) = &patch.limb_cut {
                if let Some(w) = lc.min_wrist_conf {
                    self.limb_cut.min_wrist_conf = w;
                }
                if let Some(jz) = lc.joint_zone {
                    self.limb_cut.joint_zone = jz;
                }
            }
            if let Some(hd) = &patch.head {
                if let Some(nnf) = hd.nose_neck_factor {
                    self.head.nose_neck_factor = nnf;
                }
                if let Some(eps) = hd.mask_top_eps {
                    self.head.mask_top_eps = eps;
                }
            }
        }
        self
    }
}
