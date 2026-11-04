//! Core composition and lighting rule engine for Camera Assist.
//!
//! This crate is strictly platform-independent and `#![forbid(unsafe_code)]`.
#![forbid(unsafe_code)]

pub mod arbiter;
pub mod classify;
pub mod config;
pub mod hint;
pub mod merger;
pub mod model;
pub mod rules;

pub use arbiter::*;
pub use classify::*;
pub use config::*;
pub use hint::*;
pub use merger::*;
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

    #[test]
    fn test_vectors_014_to_020_exact_match() {
        use std::fs;
        use std::path::PathBuf;

        #[derive(serde::Deserialize)]
        struct ExpectedFinding {
            id: String,
            severity: Severity,
            hint_key: String,
        }

        #[derive(serde::Deserialize)]
        struct GoldenTestCase {
            id: String,
            input: TestCaseInput,
            expected_findings: Vec<ExpectedFinding>,
        }

        #[derive(serde::Deserialize)]
        struct TestCaseInput {
            frame: Frame,
            light: Option<LightContext>,
        }

        let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let fixtures_dir = manifest_dir
            .parent()
            .unwrap()
            .parent()
            .unwrap()
            .join("fixtures")
            .join("golden");

        let target_files = [
            "014_backlit.json",
            "015_low_light.json",
            "016_harsh_top.json",
            "017_flat_front.json",
            "018_side_harsh.json",
            "019_distortion.json",
            "020_ultra_wide_edge.json",
        ];

        for filename in target_files {
            let path = fixtures_dir.join(filename);
            let content = fs::read_to_string(&path).expect("read vector file");
            let test_case: GoldenTestCase =
                serde_json::from_str(&content).expect("parse GoldenTestCase");

            let actual = evaluate_frame(&test_case.input.frame, test_case.input.light.as_ref());
            assert_eq!(
                actual.len(),
                test_case.expected_findings.len(),
                "Case '{}': finding count mismatch. Expected {:?}, got {:?}",
                test_case.id,
                test_case
                    .expected_findings
                    .iter()
                    .map(|f| &f.id)
                    .collect::<Vec<_>>(),
                actual.iter().map(|f| &f.id).collect::<Vec<_>>()
            );

            for (act, exp) in actual.iter().zip(test_case.expected_findings.iter()) {
                assert_eq!(act.id, exp.id, "Case '{}': id mismatch", test_case.id);
                assert_eq!(
                    act.severity, exp.severity,
                    "Case '{}': severity mismatch",
                    test_case.id
                );
                assert_eq!(
                    act.hint_key, exp.hint_key,
                    "Case '{}': hint_key mismatch",
                    test_case.id
                );
            }
        }
    }
}
