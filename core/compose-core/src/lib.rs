//! Core composition and lighting rule engine for Camera Assist.
//!
//! This crate is strictly platform-independent and `#![forbid(unsafe_code)]`.
#![forbid(unsafe_code)]

pub mod model;

pub use model::*;

pub fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

/// Baseline prototype rule evaluator.
/// Evaluates posture, crop, and placement rules on a single frame.
pub fn evaluate_frame(frame: &Frame, _light: Option<&LightContext>) -> Vec<Finding> {
    let mut findings = Vec::new();

    // Rule A: Level phone (roll threshold 2.5 deg)
    if frame.posture.roll_deg.abs() > 2.5 {
        let is_cw = frame.posture.roll_deg > 0.0;
        findings.push(Finding::new(
            "tilt.level",
            Severity::Major,
            Audience::Photographer,
            Action::Rotate {
                deg: frame.posture.roll_deg.abs(),
                clockwise: !is_cw,
            },
            if is_cw { "rotate_ccw" } else { "rotate_cw" },
        ));
    }

    // Rule B: Head crop (subject bounds or mask top near 0)
    if let Some(primary) = frame.primary_subject() {
        if primary.bounds.min_y() < 0.01 {
            findings.push(Finding::new(
                "crop.head",
                Severity::Critical,
                Audience::Photographer,
                Action::TiltUp,
                "tilt_up",
            ));
        }

        // Rule C: Placement (center deviation)
        let center_x = primary.bounds.center().x;
        if (center_x - 0.5).abs() > 0.15 {
            let is_left = center_x < 0.5;
            findings.push(Finding::new(
                "placement.center",
                Severity::Minor,
                Audience::Photographer,
                if is_left {
                    Action::PanLeft
                } else {
                    Action::PanRight
                },
                if is_left { "pan_left" } else { "pan_right" },
            ));
        }
    }

    findings
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
