use crate::config::ThresholdConfig;
use crate::model::{Facing, JointType, ShotType, Subject};

/// Computes normalized horizontal head yaw relative to shoulders:
/// `yaw = (nose.x - shoulder_mid.x) / shoulder_width`.
/// Positive values indicate facing toward the right side of the frame.
pub fn facing_yaw(subject: &Subject, min_conf: f32) -> Option<f32> {
    let nose = subject.joint_point(JointType::Nose, min_conf)?;
    let l_sh = subject.joint_point(JointType::LeftShoulder, min_conf)?;
    let r_sh = subject.joint_point(JointType::RightShoulder, min_conf)?;

    let width = (l_sh.x - r_sh.x).abs();
    if width <= 0.02 {
        let l_ear = subject.is_joint_visible(JointType::LeftEar, min_conf);
        let r_ear = subject.is_joint_visible(JointType::RightEar, min_conf);
        return match (l_ear, r_ear) {
            (true, false) => Some(-0.8),
            (false, true) => Some(0.8),
            _ => None,
        };
    }

    let mid_x = (l_sh.x + r_sh.x) * 0.5;
    Some((nose.x - mid_x) / width)
}

/// Classifies subject facing orientation and returns `(Facing, Option<yaw>)`.
/// Falls back to `subject.facing` when skeletal joints are sparse.
pub fn classify_facing(subject: &Subject, cfg: &ThresholdConfig) -> (Facing, Option<f32>) {
    if let Some(yaw) = facing_yaw(subject, 0.3) {
        let abs_yaw = yaw.abs();
        let facing = if abs_yaw < cfg.placement.frontal_max_yaw {
            Facing::Frontal
        } else if abs_yaw <= cfg.lead_room.min_yaw {
            if yaw < 0.0 {
                Facing::ThreeQuarterLeft
            } else {
                Facing::ThreeQuarterRight
            }
        } else if yaw < 0.0 {
            Facing::ProfileLeft
        } else {
            Facing::ProfileRight
        };
        return (facing, Some(yaw));
    }

    let fallback_yaw = match subject.facing {
        Facing::Frontal => Some(0.0),
        Facing::ThreeQuarterLeft => Some(-0.25),
        Facing::ThreeQuarterRight => Some(0.25),
        Facing::ProfileLeft => Some(-0.8),
        Facing::ProfileRight => Some(0.8),
        Facing::Back => None,
    };
    (subject.facing, fallback_yaw)
}

/// Single-frame stateless ShotType classifier.
/// Uses skeletal visibility and subject height when full-body/upper-body landmarks are present,
/// and preserves `subject.shot_type` when joints are sparse (e.g., synthetic fixtures).
pub fn classify_shot_type(subject: &Subject, cfg: &ThresholdConfig) -> ShotType {
    if subject.shot_type != ShotType::Unknown && subject.joints.len() <= 2 {
        return subject.shot_type;
    }

    if subject.bounds.height > 0.0 && subject.bounds.height < cfg.shot_type.environmental_enter {
        return ShotType::Environmental;
    }

    let min_conf = 0.3;
    let has_ankle = subject.is_joint_visible(JointType::LeftAnkle, min_conf)
        || subject.is_joint_visible(JointType::RightAnkle, min_conf);
    if has_ankle {
        return ShotType::FullBody;
    }

    let has_hip = subject.is_joint_visible(JointType::LeftHip, min_conf)
        || subject.is_joint_visible(JointType::RightHip, min_conf)
        || subject.is_joint_visible(JointType::Root, min_conf);
    if has_hip {
        return ShotType::HalfBody;
    }

    let has_shoulder = subject.is_joint_visible(JointType::LeftShoulder, min_conf)
        || subject.is_joint_visible(JointType::RightShoulder, min_conf);
    if has_shoulder {
        return if subject.shot_type == ShotType::Unknown {
            ShotType::CloseUp
        } else {
            subject.shot_type
        };
    }

    subject.shot_type
}

/// Stateful shot-type classifier with temporal hysteresis (`switch_hold = 0.4s`, `ankle_lost_hold = 0.5s`).
#[derive(Debug, Clone)]
pub struct ShotClassifierState {
    current: ShotType,
    pending: Option<(ShotType, f64)>,
    ankle_lost_since: Option<f64>,
}

impl Default for ShotClassifierState {
    fn default() -> Self {
        Self::new()
    }
}

impl ShotClassifierState {
    pub fn new() -> Self {
        Self {
            current: ShotType::HalfBody,
            pending: None,
            ankle_lost_since: None,
        }
    }

    pub fn update(&mut self, subject: &Subject, t: f64, cfg: &ThresholdConfig) -> ShotType {
        let min_conf = 0.3;
        let has_ankle = subject.is_joint_visible(JointType::LeftAnkle, min_conf)
            || subject.is_joint_visible(JointType::RightAnkle, min_conf);

        if has_ankle {
            self.ankle_lost_since = None;
        } else if self.current == ShotType::FullBody {
            let lost_t = *self.ankle_lost_since.get_or_insert(t);
            if t - lost_t < cfg.shot_type.ankle_lost_hold {
                return ShotType::FullBody;
            }
        }

        // Environmental hysteresis
        let raw = if self.current == ShotType::Environmental {
            if subject.bounds.height <= cfg.shot_type.environmental_exit {
                ShotType::Environmental
            } else {
                classify_shot_type(subject, cfg)
            }
        } else {
            classify_shot_type(subject, cfg)
        };

        if raw == self.current {
            self.pending = None;
            return self.current;
        }

        match self.pending {
            Some((cand, since)) if cand == raw => {
                if t - since >= cfg.shot_type.switch_hold {
                    self.current = raw;
                    self.pending = None;
                }
            }
            _ => {
                self.pending = Some((raw, t));
            }
        }

        self.current
    }

    pub fn reset(&mut self) {
        self.current = ShotType::HalfBody;
        self.pending = None;
        self.ankle_lost_since = None;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{Joint, NormalizedPoint, NormalizedRect};
    use std::collections::HashMap;

    #[test]
    fn test_facing_yaw_classification() {
        let cfg = ThresholdConfig::default();
        let mut joints = HashMap::new();
        joints.insert(
            JointType::LeftShoulder,
            Joint::new(JointType::LeftShoulder, NormalizedPoint::new(0.4, 0.3), 0.9),
        );
        joints.insert(
            JointType::RightShoulder,
            Joint::new(
                JointType::RightShoulder,
                NormalizedPoint::new(0.6, 0.3),
                0.9,
            ),
        );
        // Nose shifted right -> facing right
        joints.insert(
            JointType::Nose,
            Joint::new(JointType::Nose, NormalizedPoint::new(0.59, 0.2), 0.95),
        );

        let subj = Subject::new(1, NormalizedRect::new(0.3, 0.1, 0.4, 0.8)).with_joints(joints);
        let (facing, yaw) = classify_facing(&subj, &cfg);
        assert_eq!(facing, Facing::ProfileRight);
        assert!((yaw.unwrap() - 0.45).abs() < 1e-4);
    }

    #[test]
    fn test_shot_classifier_hysteresis() {
        let cfg = ThresholdConfig::default();
        let mut state = ShotClassifierState::new();

        let mut full_joints = HashMap::new();
        full_joints.insert(
            JointType::Nose,
            Joint::new(JointType::Nose, NormalizedPoint::new(0.5, 0.2), 0.9),
        );
        full_joints.insert(
            JointType::LeftShoulder,
            Joint::new(JointType::LeftShoulder, NormalizedPoint::new(0.4, 0.3), 0.9),
        );
        full_joints.insert(
            JointType::RightShoulder,
            Joint::new(
                JointType::RightShoulder,
                NormalizedPoint::new(0.6, 0.3),
                0.9,
            ),
        );
        full_joints.insert(
            JointType::LeftAnkle,
            Joint::new(JointType::LeftAnkle, NormalizedPoint::new(0.45, 0.9), 0.9),
        );

        let subj = Subject::new(1, NormalizedRect::new(0.3, 0.1, 0.4, 0.8))
            .with_shot_type(ShotType::Unknown)
            .with_joints(full_joints);

        // At t=0.0, starts pending switch to FullBody
        assert_eq!(state.update(&subj, 0.0, &cfg), ShotType::HalfBody);
        // At t=0.2 (< 0.4s switch_hold), still HalfBody
        assert_eq!(state.update(&subj, 0.2, &cfg), ShotType::HalfBody);
        // At t=0.45 (>= 0.4s switch_hold), switches to FullBody
        assert_eq!(state.update(&subj, 0.45, &cfg), ShotType::FullBody);
    }
}
