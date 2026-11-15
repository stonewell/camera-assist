#![forbid(unsafe_code)]

//! ONNX-compatible perception and desktop model evaluation interface.
//!
//! Provides model manifest licensing auditing against `shared/models/models.json`,
//! COCO-17 keypoint conversion into canonical 19-joint skeletons (synthesizing Neck and Root),
//! and synthetic perception frame generation for desktop/offline evaluation.

use compose_core::model::{
    CameraIntrinsics, ExposureSummary, Facing, Frame, Joint, JointType, LightContext,
    LightDirection, LightQuality, NormalizedPoint, NormalizedRect, Posture, ShotType, Subject,
};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use thiserror::Error;

#[derive(Error, Debug)]
pub enum PerceptionError {
    #[error("Model manifest JSON error: {0}")]
    ManifestJson(#[from] serde_json::Error),

    #[error("Audit policy violation in model '{id}': {reason}")]
    PolicyViolation { id: String, reason: String },

    #[error("Invalid input data: {0}")]
    InvalidInput(String),
}

// MARK: - Model Manifest & Audit

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuditPolicy {
    pub allowed_licenses: Vec<String>,
    pub prohibited_licenses: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelEntry {
    pub id: String,
    pub name: String,
    pub task: String,
    pub upstream_repo: String,
    pub license: String,
    pub status: String,
    pub onnx_filename: String,
    pub input_resolution: (u32, u32),
    pub parameters_m: f32,
    pub gflops: f32,
    pub commercial_use_permitted: bool,
    #[serde(default)]
    pub notes: Option<String>,
    #[serde(default)]
    pub rejection_reason: Option<String>,
    #[serde(default)]
    pub replacement_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelManifest {
    pub version: String,
    pub audit_policy: AuditPolicy,
    pub models: Vec<ModelEntry>,
}

impl ModelManifest {
    pub fn from_json(json: &str) -> Result<Self, PerceptionError> {
        let manifest: Self = serde_json::from_str(json)?;
        Ok(manifest)
    }

    /// Validates all models against the permissive licensing policy.
    pub fn validate(&self) -> Result<(), PerceptionError> {
        for m in &self.models {
            if m.status == "approved" {
                if !self.audit_policy.allowed_licenses.contains(&m.license) {
                    return Err(PerceptionError::PolicyViolation {
                        id: m.id.clone(),
                        reason: format!(
                            "Approved model has license '{}' not in allowed list",
                            m.license
                        ),
                    });
                }
                if self.audit_policy.prohibited_licenses.contains(&m.license) {
                    return Err(PerceptionError::PolicyViolation {
                        id: m.id.clone(),
                        reason: format!("Approved model has prohibited license '{}'", m.license),
                    });
                }
                if !m.commercial_use_permitted {
                    return Err(PerceptionError::PolicyViolation {
                        id: m.id.clone(),
                        reason: "Approved model must permit commercial use".into(),
                    });
                }
            } else if m.status == "rejected" {
                if m.commercial_use_permitted {
                    return Err(PerceptionError::PolicyViolation {
                        id: m.id.clone(),
                        reason: "Rejected model should not permit commercial use".into(),
                    });
                }
                if m.rejection_reason.as_deref().unwrap_or("").is_empty() {
                    return Err(PerceptionError::PolicyViolation {
                        id: m.id.clone(),
                        reason: "Rejected model must document rejection_reason".into(),
                    });
                }
            }
        }
        Ok(())
    }
}

// MARK: - COCO-17 Keypoint Mapping

/// 2D detected keypoint from COCO-17 format pose estimators (e.g. RTMPose, OpenPose, YOLO-Pose).
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct CocoKeypoint {
    pub x: f32,
    pub y: f32,
    pub score: f32,
}

impl CocoKeypoint {
    pub fn new(x: f32, y: f32, score: f32) -> Self {
        Self { x, y, score }
    }
}

/// Converts a 17-keypoint COCO array into a canonical 19-joint skeleton,
/// synthesizing missing `Neck` and `Root` joints from shoulders and hips.
pub fn coco_17_to_joints(
    keypoints: &[CocoKeypoint; 17],
    min_confidence: f32,
) -> HashMap<JointType, Joint> {
    let mut joints = HashMap::with_capacity(19);

    for (i, &coco_type) in JointType::COCO_17.iter().enumerate() {
        let pt = keypoints[i];
        joints.insert(
            coco_type,
            Joint::new(coco_type, NormalizedPoint::new(pt.x, pt.y), pt.score),
        );
    }

    // Synthesize Neck (midpoint of LeftShoulder & RightShoulder)
    // and Root (midpoint of LeftHip & RightHip)
    Joint::synthesize_neck_and_root(&mut joints, min_confidence);

    joints
}

// MARK: - Synthetic Scene Input & Perception Backend

/// Synthetic scene descriptor for offline analysis and desktop evaluations.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyntheticSceneInput {
    pub timestamp: f64,
    pub subject_bounds: NormalizedRect,
    pub coco_keypoints: Option<[CocoKeypoint; 17]>,
    pub posture: Option<Posture>,
    pub camera: Option<CameraIntrinsics>,
    pub exposure: Option<ExposureSummary>,
    pub light: Option<LightContext>,
}

pub trait PerceptionBackend: Send + Sync {
    fn process_synthetic(
        &self,
        input: &SyntheticSceneInput,
    ) -> Result<(Frame, LightContext), PerceptionError>;
}

/// Desktop and test perception backend implementing COCO-17 to 19-joint conversion and classification.
#[derive(Default, Debug, Clone)]
pub struct OnnxPerceptionBackend {
    pub min_confidence: f32,
}

impl OnnxPerceptionBackend {
    pub fn new(min_confidence: f32) -> Self {
        Self { min_confidence }
    }

    /// Classifies subject facing based on facial keypoint geometry.
    pub fn classify_facing(joints: &HashMap<JointType, Joint>) -> Facing {
        let nose = joints.get(&JointType::Nose);
        let left_eye = joints.get(&JointType::LeftEye);
        let right_eye = joints.get(&JointType::RightEye);
        let left_ear = joints.get(&JointType::LeftEar);
        let right_ear = joints.get(&JointType::RightEar);

        match (nose, left_eye, right_eye, left_ear, right_ear) {
            (Some(n), Some(l_eye), Some(r_eye), _, _)
                if n.confidence > 0.4 && l_eye.confidence > 0.4 && r_eye.confidence > 0.4 =>
            {
                let eye_center = (l_eye.point.x + r_eye.point.x) * 0.5;
                let eye_dist = (r_eye.point.x - l_eye.point.x).abs();
                let nose_offset = (n.point.x - eye_center) / eye_dist.max(0.01);
                if nose_offset < -0.3 {
                    Facing::ThreeQuarterLeft
                } else if nose_offset > 0.3 {
                    Facing::ThreeQuarterRight
                } else {
                    Facing::Frontal
                }
            }
            (_, Some(_), None, _, Some(_)) => Facing::ProfileRight,
            (_, None, Some(_), Some(_), _) => Facing::ProfileLeft,
            (None, None, None, _, _) => Facing::Back,
            _ => Facing::Frontal,
        }
    }

    /// Classifies shot type based on normalized bounding box height and coverage.
    pub fn classify_shot_type(bounds: &NormalizedRect) -> ShotType {
        let h = bounds.height;
        if h >= 0.72 {
            ShotType::FullBody
        } else if h >= 0.38 {
            ShotType::HalfBody
        } else if h >= 0.18 {
            ShotType::CloseUp
        } else {
            ShotType::Environmental
        }
    }
}

impl PerceptionBackend for OnnxPerceptionBackend {
    fn process_synthetic(
        &self,
        input: &SyntheticSceneInput,
    ) -> Result<(Frame, LightContext), PerceptionError> {
        let joints = if let Some(ref kps) = input.coco_keypoints {
            coco_17_to_joints(kps, self.min_confidence)
        } else {
            HashMap::new()
        };

        let facing = Self::classify_facing(&joints);
        let shot_type = Self::classify_shot_type(&input.subject_bounds);

        let subject = Subject::new(1, input.subject_bounds)
            .with_joints(joints)
            .with_facing(facing)
            .with_shot_type(shot_type);

        let posture = input.posture.unwrap_or_else(|| Posture::new(0.0, 0.0));
        let camera = input
            .camera
            .unwrap_or_else(|| CameraIntrinsics::new(24.0, 84.0));
        let exposure = input.exposure.unwrap_or(ExposureSummary {
            iso: 100.0,
            shutter_speed_sec: 1.0 / 60.0,
            ev: 12.0,
        });

        let mut frame = Frame::new(input.timestamp, posture)
            .with_subjects(vec![subject])
            .with_intrinsics(camera);
        frame.exposure = exposure;

        let light = input.light.clone().unwrap_or_else(|| {
            LightContext::new(
                LightDirection::Front,
                LightQuality::Soft,
                Some(1.0),
                12.0,
                0.8,
            )
        });

        Ok((frame, light))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_manifest_validation() {
        let manifest_content = include_str!("../../../shared/models/models.json");
        let manifest = ModelManifest::from_json(manifest_content).expect("manifest json parses");
        assert_eq!(manifest.version, "1.0.0");
        assert!(manifest.models.len() >= 4);
        manifest
            .validate()
            .expect("all approved/rejected models conform to audit policy");
    }

    #[test]
    fn test_coco_17_to_19_joints_synthesis() {
        let mut kps = [CocoKeypoint::new(0.5, 0.5, 0.9); 17];
        // LeftShoulder (index 5), RightShoulder (index 6)
        kps[5] = CocoKeypoint::new(0.4, 0.3, 0.95);
        kps[6] = CocoKeypoint::new(0.6, 0.3, 0.95);
        // LeftHip (index 11), RightHip (index 12)
        kps[11] = CocoKeypoint::new(0.42, 0.6, 0.90);
        kps[12] = CocoKeypoint::new(0.58, 0.6, 0.90);

        let joints = coco_17_to_joints(&kps, 0.3);
        assert_eq!(joints.len(), 19);

        let neck = joints
            .get(&JointType::Neck)
            .expect("Neck must be synthesized");
        assert!((neck.point.x - 0.5).abs() < 1e-4);
        assert!((neck.point.y - 0.3).abs() < 1e-4);

        let root = joints
            .get(&JointType::Root)
            .expect("Root must be synthesized");
        assert!((root.point.x - 0.5).abs() < 1e-4);
        assert!((root.point.y - 0.6).abs() < 1e-4);
    }

    #[test]
    fn test_onnx_backend_synthetic_processing() {
        let backend = OnnxPerceptionBackend::new(0.3);
        let bounds = NormalizedRect::new(0.2, 0.1, 0.6, 0.8);
        let input = SyntheticSceneInput {
            timestamp: 100.0,
            subject_bounds: bounds,
            coco_keypoints: None,
            posture: None,
            camera: None,
            exposure: None,
            light: None,
        };

        let (frame, light) = backend
            .process_synthetic(&input)
            .expect("processing succeeds");
        assert_eq!(frame.subjects.len(), 1);
        assert_eq!(frame.subjects[0].shot_type, ShotType::FullBody);
        assert_eq!(light.direction, LightDirection::Front);
    }
}
