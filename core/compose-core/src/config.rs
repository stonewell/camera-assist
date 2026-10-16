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

/// Limb & joint cutting thresholds.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LimbCutThresholds {
    pub joint_zone: f32,
    pub min_wrist_conf: f32,
}

impl Default for LimbCutThresholds {
    fn default() -> Self {
        Self {
            joint_zone: 0.18,
            min_wrist_conf: 0.5,
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

/// Complete typed threshold configuration loaded from shared/config/Thresholds.json.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ThresholdConfig {
    #[serde(default)]
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
    pub headroom: HeadroomThresholds,
    #[serde(default)]
    pub placement: PlacementThresholds,
    #[serde(default)]
    pub edge: EdgeThresholds,
    #[serde(default)]
    pub multi_subject: MultiSubjectThresholds,
}

impl Default for ThresholdConfig {
    fn default() -> Self {
        Self {
            version: 1,
            level: LevelThresholds::default(),
            tilt: TiltThresholds::default(),
            head: HeadThresholds::default(),
            limb_cut: LimbCutThresholds::default(),
            headroom: HeadroomThresholds::default(),
            placement: PlacementThresholds::default(),
            edge: EdgeThresholds::default(),
            multi_subject: MultiSubjectThresholds::default(),
        }
    }
}

impl ThresholdConfig {
    pub fn from_json_str(json_str: &str) -> Result<Self, serde_json::Error> {
        serde_json::from_str(json_str)
    }
}
