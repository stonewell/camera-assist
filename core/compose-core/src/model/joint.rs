use super::geometry::NormalizedPoint;
use serde::{Deserialize, Serialize};

/// Standard COCO-17 human body joint types.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum JointType {
    Nose,
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
    LeftHip,
    RightHip,
    LeftKnee,
    RightKnee,
    LeftAnkle,
    RightAnkle,
}

impl JointType {
    pub const ALL: [Self; 17] = [
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
            Self::LeftShoulder
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
            Self::LeftHip
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
}
