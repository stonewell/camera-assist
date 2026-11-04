use compose_core::{evaluate_frame, Frame, LightContext, Severity};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

/// Expected number of golden test vectors in `fixtures/golden`.
/// Bump this constant when new vectors (e.g. 014+ for TASK-04) are added.
pub const EXPECTED_VECTORS: usize = 20;

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Deserialize, Serialize)]
struct ExpectedFinding {
    id: String,
    severity: Severity,
    hint_key: String,
}

#[derive(Debug, Deserialize, Serialize)]
struct GoldenTestCase {
    id: String,
    description: String,
    input: TestCaseInput,
    expected_findings: Vec<ExpectedFinding>,
}

#[derive(Debug, Deserialize, Serialize)]
struct TestCaseInput {
    frame: Frame,
    light: Option<LightContext>,
}

/// Manifest of expected findings per golden vector.
///
/// All 20 golden vectors (001-020) have their exact, complete finding sets pinned in this manifest
/// to enforce strict finding-set equality (TASK-02 & TASK-04).
fn expected_findings_for_case(
    case_id: &str,
    declared_in_fixture: &[ExpectedFinding],
) -> Vec<ExpectedFinding> {
    match case_id {
        "001_level_phone" => vec![ExpectedFinding {
            id: "tilt.level".into(),
            severity: Severity::Major,
            hint_key: "rotate_ccw".into(),
        }],
        "002_placement_center" => vec![
            ExpectedFinding {
                id: "headroom.excessive".into(),
                severity: Severity::Minor,
                hint_key: "tilt_down".into(),
            },
            ExpectedFinding {
                id: "placement.center".into(),
                severity: Severity::Minor,
                hint_key: "pan_right".into(),
            },
        ],
        "003_head_crop" => vec![ExpectedFinding {
            id: "crop.head".into(),
            severity: Severity::Critical,
            hint_key: "tilt_up".into(),
        }],
        "004_pitch_tilt" => vec![ExpectedFinding {
            id: "tilt.vertical".into(),
            severity: Severity::Major,
            hint_key: "hold_vertical".into(),
        }],
        "005_joint_wrist_crop" => vec![
            ExpectedFinding {
                id: "crop.joint".into(),
                severity: Severity::Major,
                hint_key: "step_back".into(),
            },
            ExpectedFinding {
                id: "placement.center".into(),
                severity: Severity::Minor,
                hint_key: "pan_left".into(),
            },
            ExpectedFinding {
                id: "edge.crowd".into(),
                severity: Severity::Minor,
                hint_key: "pan_left".into(),
            },
        ],
        "006_rule_of_thirds" => vec![
            ExpectedFinding {
                id: "headroom.excessive".into(),
                severity: Severity::Minor,
                hint_key: "tilt_down".into(),
            },
            ExpectedFinding {
                id: "placement.thirds".into(),
                severity: Severity::Minor,
                hint_key: "pan_left".into(),
            },
        ],
        "007_headroom_insufficient" => vec![ExpectedFinding {
            id: "headroom.insufficient".into(),
            severity: Severity::Minor,
            hint_key: "tilt_up".into(),
        }],
        "008_multi_subject_occlusion" => vec![ExpectedFinding {
            id: "multi.occlusion".into(),
            severity: Severity::Major,
            hint_key: "step_back".into(),
        }],
        "009_multi_subject_unbalanced" => vec![
            ExpectedFinding {
                id: "multi.unbalanced".into(),
                severity: Severity::Minor,
                hint_key: "pan_left".into(),
            },
            ExpectedFinding {
                id: "headroom.excessive".into(),
                severity: Severity::Minor,
                hint_key: "tilt_down".into(),
            },
            ExpectedFinding {
                id: "placement.center".into(),
                severity: Severity::Minor,
                hint_key: "pan_left".into(),
            },
        ],
        "010_good_to_shoot_fullbody" => vec![],
        "011_feet_floating" => vec![ExpectedFinding {
            id: "feet.floating".into(),
            severity: Severity::Major,
            hint_key: "lower_phone".into(),
        }],
        "012_limb_chain_cut" => vec![
            ExpectedFinding {
                id: "crop.joint".into(),
                severity: Severity::Major,
                hint_key: "step_back".into(),
            },
            ExpectedFinding {
                id: "placement.center".into(),
                severity: Severity::Minor,
                hint_key: "pan_right".into(),
            },
        ],
        "013_combo_lower_vertical" => vec![ExpectedFinding {
            id: "combo.lower_vertical".into(),
            severity: Severity::Major,
            hint_key: "lower_and_vertical".into(),
        }],
        "014_backlit" => vec![ExpectedFinding {
            id: "light.backlit".into(),
            severity: Severity::Major,
            hint_key: "enable_fill".into(),
        }],
        "015_low_light" => vec![ExpectedFinding {
            id: "light.low_light".into(),
            severity: Severity::Critical,
            hint_key: "use_night_mode".into(),
        }],
        "016_harsh_top" => vec![ExpectedFinding {
            id: "light.harsh_top".into(),
            severity: Severity::Minor,
            hint_key: "move_to_shade".into(),
        }],
        "017_flat_front" => vec![ExpectedFinding {
            id: "light.flat_front".into(),
            severity: Severity::Minor,
            hint_key: "turn_subject_side".into(),
        }],
        "018_side_harsh" => vec![ExpectedFinding {
            id: "light.side_harsh".into(),
            severity: Severity::Minor,
            hint_key: "turn_face_to_light".into(),
        }],
        "019_distortion" => vec![ExpectedFinding {
            id: "distance.distortion".into(),
            severity: Severity::Major,
            hint_key: "switch_zoom_step_back".into(),
        }],
        "020_ultra_wide_edge" => vec![ExpectedFinding {
            id: "distance.ultra_wide_edge".into(),
            severity: Severity::Minor,
            hint_key: "switch_zoom_1x".into(),
        }],
        _ => declared_in_fixture.to_vec(),
    }
}

#[test]
fn test_all_golden_vectors() {
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let fixtures_dir = manifest_dir
        .parent()
        .expect("parent of compose-core")
        .parent()
        .expect("root repo")
        .join("fixtures")
        .join("golden");

    assert!(
        fixtures_dir.exists(),
        "Fixtures dir {:?} must exist",
        fixtures_dir
    );

    let entries = fs::read_dir(&fixtures_dir).expect("read fixtures dir");
    let mut vector_files: Vec<PathBuf> = entries
        .map(|entry| entry.expect("valid entry").path())
        .filter(|path| {
            path.extension().and_then(|s| s.to_str()) == Some("json")
                && path.file_name().and_then(|s| s.to_str()) != Some("schema.json")
        })
        .collect();
    vector_files.sort();

    // Assert exact expected vector count (TASK-02)
    assert_eq!(
        vector_files.len(),
        EXPECTED_VECTORS,
        "Expected exactly {} golden vector files in {:?}, found {}: {:?}",
        EXPECTED_VECTORS,
        fixtures_dir,
        vector_files.len(),
        vector_files
            .iter()
            .map(|p| p.file_name().unwrap())
            .collect::<Vec<_>>()
    );

    let mut count = 0;

    for path in &vector_files {
        let content = fs::read_to_string(path).expect("read file");
        let test_case: GoldenTestCase =
            serde_json::from_str(&content).expect("parse GoldenTestCase");

        let actual_findings =
            evaluate_frame(&test_case.input.frame, test_case.input.light.as_ref());

        let mut actual_sorted: Vec<ExpectedFinding> = actual_findings
            .into_iter()
            .map(|f| ExpectedFinding {
                id: f.id,
                severity: f.severity,
                hint_key: f.hint_key,
            })
            .collect();
        actual_sorted.sort();

        let mut expected_sorted =
            expected_findings_for_case(&test_case.id, &test_case.expected_findings);
        expected_sorted.sort();

        // Ensure every declared finding in the fixture JSON is represented
        for declared in &test_case.expected_findings {
            assert!(
                expected_sorted.contains(declared),
                "Case '{}': declared finding {:?} is missing from expected set",
                test_case.id,
                declared
            );
        }

        // Assert exact finding-set equality per golden vector (TASK-02)
        assert_eq!(
            actual_sorted,
            expected_sorted,
            "Case '{}' ({:?}): finding-set mismatch.\nExpected: {:#?}\nActual: {:#?}",
            test_case.id,
            path.file_name().unwrap(),
            expected_sorted,
            actual_sorted
        );

        count += 1;
    }

    assert_eq!(
        count, EXPECTED_VECTORS,
        "Expected exactly {} golden test cases to run, ran {}",
        EXPECTED_VECTORS, count
    );
    println!(
        "Successfully ran all {} golden test vectors with exact finding-set equality!",
        count
    );
}
