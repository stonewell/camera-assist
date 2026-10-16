//! Core composition and lighting rule engine for Camera Assist.
//!
//! This crate is strictly platform-independent and `#![forbid(unsafe_code)]`.
#![forbid(unsafe_code)]

pub mod config;
pub mod hint;
pub mod model;
pub mod rules;

pub use config::*;
pub use hint::*;
pub use model::*;
pub use rules::*;

pub fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

/// Evaluates composition rules on a single frame using the default RulesEngine.
pub fn evaluate_frame(frame: &Frame, light: Option<&LightContext>) -> Vec<Finding> {
    let engine = RulesEngine::default_engine();
    engine.evaluate(frame, light)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    #[test]
    fn test_frame_serialization_roundtrip() {
        let mut joints = HashMap::new();
        joints.insert(
            JointType::Nose,
            Joint::new(JointType::Nose, NormalizedPoint::new(0.5, 0.2), 0.95),
        );
        joints.insert(
            JointType::LeftEye,
            Joint::new(JointType::LeftEye, NormalizedPoint::new(0.48, 0.19), 0.92),
        );

        let subject = Subject::new(1, NormalizedRect::new(0.3, 0.1, 0.4, 0.8))
            .with_joints(joints)
            .with_facing(Facing::Frontal)
            .with_shot_type(ShotType::HalfBody);

        let frame = Frame::new(100.5, Posture::new(2.5, -5.0)).with_subjects(vec![subject]);

        let json_str = serde_json::to_string_pretty(&frame).expect("serialize frame");
        assert!(json_str.contains("\"Nose\""));
        assert!(json_str.contains("\"Frontal\""));

        let deserialized: Frame = serde_json::from_str(&json_str).expect("deserialize frame");
        assert_eq!(frame, deserialized);
    }

    #[test]
    fn test_finding_creation() {
        let finding = Finding::new(
            "tilt.vertical",
            Severity::Major,
            Audience::Photographer,
            Action::HoldVertical,
            "hold_vertical",
        );

        assert_eq!(finding.severity, Severity::Major);
        assert!(!finding.is_critical());
    }
}
