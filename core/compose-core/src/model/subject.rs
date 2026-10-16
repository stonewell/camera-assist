use super::geometry::{NormalizedPoint, NormalizedRect};
use super::joint::{Joint, JointType};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Subject body facing orientation relative to camera.
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Facing {
    #[default]
    Frontal,
    ThreeQuarterLeft,
    ThreeQuarterRight,
    ProfileLeft,
    ProfileRight,
    Back,
}

/// Photographic shot framing scale.
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum ShotType {
    CloseUp, // 特写 (头肩)
    #[default]
    HalfBody, // 半身 (腰部以上)
    FullBody, // 全身 (膝盖/脚底完整)
    Environmental, // 环境人像 (人物占画面比例较小)
    Unknown, // 关节太少无法判定
}

fn default_bottom_y() -> f32 {
    1.0
}

fn default_confidence() -> f32 {
    1.0
}

/// Compact representation of human instance segmentation mask.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MaskSummary {
    pub top_y: f32,
    #[serde(default = "default_bottom_y")]
    pub bottom_y: f32,
    #[serde(default)]
    pub head_cols: (f32, f32), // (min_x, max_x)
    #[serde(default)]
    pub torso_cols: (f32, f32), // (min_x, max_x)
    #[serde(default)]
    pub leg_cols: (f32, f32), // (min_x, max_x)
    #[serde(default)]
    pub touches_top: bool,
    #[serde(default)]
    pub touches_bottom: bool,
    #[serde(default)]
    pub touches_left: bool,
    #[serde(default)]
    pub touches_right: bool,
}

impl MaskSummary {
    pub fn new(
        top_y: f32,
        bottom_y: f32,
        head_cols: (f32, f32),
        torso_cols: (f32, f32),
        leg_cols: (f32, f32),
    ) -> Self {
        Self {
            top_y,
            bottom_y,
            head_cols,
            torso_cols,
            leg_cols,
            touches_top: top_y <= 0.015,
            touches_bottom: bottom_y >= 0.985,
            touches_left: head_cols.0.min(torso_cols.0) <= 0.015
                && (head_cols.1 > 0.0 || torso_cols.1 > 0.0),
            touches_right: head_cols.1.max(torso_cols.1) >= 0.985,
        }
    }
}

/// Detected person in frame.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Subject {
    pub id: u32,
    pub bounds: NormalizedRect,
    #[serde(default)]
    pub joints: HashMap<JointType, Joint>,
    #[serde(default)]
    pub facing: Facing,
    #[serde(default)]
    pub shot_type: ShotType,
    #[serde(default = "default_confidence")]
    pub confidence: f32,
    #[serde(default)]
    pub is_group: bool,
    #[serde(default)]
    pub mask_summary: Option<MaskSummary>,
}

impl Subject {
    pub fn new(id: u32, bounds: NormalizedRect) -> Self {
        Self {
            id,
            bounds,
            joints: HashMap::new(),
            facing: Facing::Frontal,
            shot_type: ShotType::HalfBody,
            confidence: 1.0,
            is_group: false,
            mask_summary: None,
        }
    }

    pub fn with_joints(mut self, joints: HashMap<JointType, Joint>) -> Self {
        self.joints = joints;
        self
    }

    pub fn with_facing(mut self, facing: Facing) -> Self {
        self.facing = facing;
        self
    }

    pub fn with_shot_type(mut self, shot_type: ShotType) -> Self {
        self.shot_type = shot_type;
        self
    }

    pub fn with_group(mut self, is_group: bool) -> Self {
        self.is_group = is_group;
        self
    }

    pub fn with_mask(mut self, mask: MaskSummary) -> Self {
        self.mask_summary = Some(mask);
        self
    }

    pub fn get_joint(&self, joint_type: JointType) -> Option<&Joint> {
        self.joints.get(&joint_type)
    }

    pub fn joint_point(&self, joint_type: JointType, min_conf: f32) -> Option<NormalizedPoint> {
        self.joints
            .get(&joint_type)
            .filter(|j| j.is_reliable(min_conf))
            .map(|j| j.point)
    }

    pub fn is_joint_visible(&self, joint_type: JointType, min_conf: f32) -> bool {
        self.joints
            .get(&joint_type)
            .map(|j| j.is_reliable(min_conf))
            .unwrap_or(false)
    }
}
