use super::geometry::NormalizedRect;
use super::joint::{Joint, JointType};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Subject body facing orientation relative to camera.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Facing {
    Frontal,
    ThreeQuarterLeft,
    ThreeQuarterRight,
    ProfileLeft,
    ProfileRight,
    Back,
}

/// Photographic shot framing scale.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum ShotType {
    CloseUp,       // 特写 (头肩)
    HalfBody,      // 半身 (腰部以上)
    FullBody,      // 全身 (膝盖/脚底完整)
    Environmental, // 环境人像 (人物占画面比例较小)
}

/// Compact representation of human instance segmentation mask.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MaskSummary {
    pub top_y: f32,
    pub bottom_y: f32,
    pub head_cols: (f32, f32),  // (min_x, max_x)
    pub torso_cols: (f32, f32), // (min_x, max_x)
    pub leg_cols: (f32, f32),   // (min_x, max_x)
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
        }
    }
}

/// Detected person in frame.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Subject {
    pub id: u32,
    pub bounds: NormalizedRect,
    pub joints: HashMap<JointType, Joint>,
    pub facing: Facing,
    pub shot_type: ShotType,
    pub confidence: f32,
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

    pub fn with_mask(mut self, mask: MaskSummary) -> Self {
        self.mask_summary = Some(mask);
        self
    }

    pub fn get_joint(&self, joint_type: JointType) -> Option<&Joint> {
        self.joints.get(&joint_type)
    }

    pub fn is_joint_visible(&self, joint_type: JointType, min_conf: f32) -> bool {
        self.joints
            .get(&joint_type)
            .map(|j| j.is_reliable(min_conf))
            .unwrap_or(false)
    }
}
