use super::geometry::NormalizedPoint;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Human body joint types (17 COCO keypoints + Neck and Root from Vision).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum JointType {
    Nose,
    Neck,
    LeftEye,
    RightEye,
    LeftEar,
    RightEar,
    LeftShoulder,
    RightShoulder,
    LeftElbow,
    RightElbow,
    LeftWrist,
    RightWrist,
    Root,
    LeftHip,
    RightHip,
    LeftKnee,
    RightKnee,
    LeftAnkle,
    RightAnkle,
}

impl JointType {
    pub const ALL: [Self; 19] = [
        Self::Nose,
        Self::Neck,
        Self::LeftEye,
        Self::RightEye,
        Self::LeftEar,
        Self::RightEar,
        Self::LeftShoulder,
        Self::RightShoulder,
        Self::LeftElbow,
        Self::RightElbow,
        Self::LeftWrist,
        Self::RightWrist,
        Self::Root,
        Self::LeftHip,
        Self::RightHip,
        Self::LeftKnee,
        Self::RightKnee,
        Self::LeftAnkle,
        Self::RightAnkle,
    ];

    pub const COCO_17: [Self; 17] = [
        Self::Nose,
        Self::LeftEye,
        Self::RightEye,
        Self::LeftEar,
        Self::RightEar,
        Self::LeftShoulder,
        Self::RightShoulder,
        Self::LeftElbow,
        Self::RightElbow,
        Self::LeftWrist,
        Self::RightWrist,
        Self::LeftHip,
        Self::RightHip,
        Self::LeftKnee,
        Self::RightKnee,
        Self::LeftAnkle,
        Self::RightAnkle,
    ];

    pub fn is_facial(&self) -> bool {
        matches!(
            self,
            Self::Nose | Self::LeftEye | Self::RightEye | Self::LeftEar | Self::RightEar
        )
    }

    pub fn is_upper_body(&self) -> bool {
        matches!(
            self,
            Self::Neck
                | Self::LeftShoulder
                | Self::RightShoulder
                | Self::LeftElbow
                | Self::RightElbow
                | Self::LeftWrist
                | Self::RightWrist
        )
    }

    pub fn is_lower_body(&self) -> bool {
        matches!(
            self,
            Self::Root
                | Self::LeftHip
                | Self::RightHip
                | Self::LeftKnee
                | Self::RightKnee
                | Self::LeftAnkle
                | Self::RightAnkle
        )
    }
}

/// A detected joint with position and detection confidence.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct Joint {
    pub joint_type: JointType,
    pub point: NormalizedPoint,
    pub confidence: f32,
}

impl Joint {
    pub fn new(joint_type: JointType, point: NormalizedPoint, confidence: f32) -> Self {
        Self {
            joint_type,
            point,
            confidence: confidence.clamp(0.0, 1.0),
        }
    }

    pub fn is_reliable(&self, threshold: f32) -> bool {
        self.confidence >= threshold
    }

    /// Synthesize a midpoint joint (e.g., Neck from shoulders, Root from hips).
    pub fn midpoint(joint_type: JointType, a: &Joint, b: &Joint) -> Self {
        Self {
            joint_type,
            point: NormalizedPoint::new(
                (a.point.x + b.point.x) * 0.5,
                (a.point.y + b.point.y) * 0.5,
            ),
            confidence: a.confidence.min(b.confidence),
        }
    }

    /// Populates missing `Neck` and `Root` joints from shoulders and hips when both sides are reliable.
    pub fn synthesize_neck_and_root(joints: &mut HashMap<JointType, Joint>, min_conf: f32) {
        if !joints.contains_key(&JointType::Neck) {
            if let (Some(l), Some(r)) = (
                joints.get(&JointType::LeftShoulder),
                joints.get(&JointType::RightShoulder),
            ) {
                if l.is_reliable(min_conf) && r.is_reliable(min_conf) {
                    let neck = Self::midpoint(JointType::Neck, l, r);
                    joints.insert(JointType::Neck, neck);
                }
            }
        }
        if !joints.contains_key(&JointType::Root) {
            if let (Some(l), Some(r)) = (
                joints.get(&JointType::LeftHip),
                joints.get(&JointType::RightHip),
            ) {
                if l.is_reliable(min_conf) && r.is_reliable(min_conf) {
                    let root = Self::midpoint(JointType::Root, l, r);
                    joints.insert(JointType::Root, root);
                }
            }
        }
    }
}
