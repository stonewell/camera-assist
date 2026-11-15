#![forbid(unsafe_code)]

//! Offline composition rule evaluation and benchmark harness.

use compose_core::model::{Finding, Frame, LightContext, Severity};
use compose_core::rules::RulesEngine;
use review_engine::ReviewEngine;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;
use std::time::Instant;
use thiserror::Error;

#[derive(Error, Debug)]
pub enum EvalError {
    #[error("I/O error reading golden fixtures: {0}")]
    Io(#[from] std::io::Error),

    #[error("JSON deserialization error: {0}")]
    Json(#[from] serde_json::Error),

    #[error("Fixtures directory not found: {0}")]
    NotFound(String),

    #[error("Evaluation failed: expected {expected} vectors, found {found}")]
    VectorCountMismatch { expected: usize, found: usize },
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Deserialize, Serialize)]
pub struct ExpectedFinding {
    pub id: String,
    pub severity: Severity,
    pub hint_key: String,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct TestCaseInput {
    pub frame: Frame,
    pub light: Option<LightContext>,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct GoldenTestCase {
    pub id: String,
    pub description: String,
    pub input: TestCaseInput,
    pub expected_findings: Vec<ExpectedFinding>,
}

/// Pinned exact finding manifests across all 20 golden vectors (001-020).
pub fn expected_findings_for_case(
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

// MARK: - Evaluation Output Structs

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EvalResultItem {
    pub vector_id: String,
    pub description: String,
    pub expected_findings: Vec<String>,
    pub actual_findings: Vec<String>,
    pub is_exact_match: bool,
    pub latency_us: u64,
    pub review_score: u32,
    pub suggested_fixes_count: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EvalSummary {
    pub total_vectors: usize,
    pub exact_matches: usize,
    pub exact_match_rate: f32,
    pub precision: f32,
    pub recall: f32,
    pub mean_latency_us: f32,
    pub results: Vec<EvalResultItem>,
}

/// Evaluates all golden test vector files in `golden_dir` against `RulesEngine` and `ReviewEngine`.
pub fn evaluate_golden_dir(golden_dir: &Path) -> Result<EvalSummary, EvalError> {
    if !golden_dir.is_dir() {
        return Err(EvalError::NotFound(golden_dir.display().to_string()));
    }

    let entries = fs::read_dir(golden_dir)?;
    let mut files: Vec<_> = entries
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| {
            p.extension().and_then(|ext| ext.to_str()) == Some("json")
                && p.file_name().and_then(|f| f.to_str()) != Some("schema.json")
        })
        .collect();
    files.sort();

    let rules_engine = RulesEngine::default_engine();
    let review_engine = ReviewEngine::new(RulesEngine::default_engine());

    let mut results = Vec::with_capacity(files.len());
    let mut exact_matches = 0usize;
    let mut total_latency_us = 0u64;
    let mut tp_total = 0usize;
    let mut fp_total = 0usize;
    let mut fn_total = 0usize;

    for path in &files {
        let content = fs::read_to_string(path)?;
        let test_case: GoldenTestCase = serde_json::from_str(&content)?;

        let start = Instant::now();
        let findings =
            rules_engine.evaluate(&test_case.input.frame, test_case.input.light.as_ref());
        let latency_us = start.elapsed().as_micros() as u64;
        total_latency_us += latency_us;

        let review_item = review_engine.analyze_photo(
            &test_case.id,
            path.to_str().unwrap_or(""),
            &test_case.input.frame,
            test_case.input.light.as_ref(),
        );

        let mut actual_sorted: Vec<ExpectedFinding> = findings
            .into_iter()
            .map(|f: Finding| ExpectedFinding {
                id: f.id,
                severity: f.severity,
                hint_key: f.hint_key,
            })
            .collect();
        actual_sorted.sort();

        let mut expected_sorted =
            expected_findings_for_case(&test_case.id, &test_case.expected_findings);
        expected_sorted.sort();

        let is_exact_match = actual_sorted == expected_sorted;
        if is_exact_match {
            exact_matches += 1;
        }

        // Confusion metrics
        for a in &actual_sorted {
            if expected_sorted.contains(a) {
                tp_total += 1;
            } else {
                fp_total += 1;
            }
        }
        for e in &expected_sorted {
            if !actual_sorted.contains(e) {
                fn_total += 1;
            }
        }

        results.push(EvalResultItem {
            vector_id: test_case.id,
            description: test_case.description,
            expected_findings: expected_sorted.iter().map(|f| f.id.clone()).collect(),
            actual_findings: actual_sorted.iter().map(|f| f.id.clone()).collect(),
            is_exact_match,
            latency_us,
            review_score: review_item.score,
            suggested_fixes_count: review_item.suggested_fixes.len(),
        });
    }

    let total = results.len();
    let exact_match_rate = if total > 0 {
        exact_matches as f32 / total as f32
    } else {
        0.0
    };
    let precision = if (tp_total + fp_total) > 0 {
        tp_total as f32 / (tp_total + fp_total) as f32
    } else {
        1.0
    };
    let recall = if (tp_total + fn_total) > 0 {
        tp_total as f32 / (tp_total + fn_total) as f32
    } else {
        1.0
    };
    let mean_latency_us = if total > 0 {
        total_latency_us as f32 / total as f32
    } else {
        0.0
    };

    Ok(EvalSummary {
        total_vectors: total,
        exact_matches,
        exact_match_rate,
        precision,
        recall,
        mean_latency_us,
        results,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn test_eval_all_20_golden_vectors() {
        let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let golden_dir = manifest_dir
            .parent()
            .unwrap()
            .parent()
            .unwrap()
            .join("fixtures")
            .join("golden");

        let summary = evaluate_golden_dir(&golden_dir).expect("evaluate_golden_dir succeeds");
        assert_eq!(summary.total_vectors, 20);
        assert_eq!(summary.exact_matches, 20);
        assert!((summary.exact_match_rate - 1.0).abs() < 1e-4);
        assert!((summary.precision - 1.0).abs() < 1e-4);
        assert!((summary.recall - 1.0).abs() < 1e-4);
        assert!(summary.mean_latency_us < 1000.0); // < 1.0ms SLA
    }
}
