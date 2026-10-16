use compose_core::{evaluate_frame, Frame, LightContext, Severity};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

#[derive(Debug, Deserialize, Serialize)]
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
    let mut count = 0;

    for entry in entries {
        let entry = entry.expect("valid entry");
        let path = entry.path();
        if path.extension().and_then(|s| s.to_str()) == Some("json")
            && path.file_name().and_then(|s| s.to_str()) != Some("schema.json")
        {
            println!("Running golden test: {:?}", path.file_name().unwrap());
            let content = fs::read_to_string(&path).expect("read file");
            let test_case: GoldenTestCase =
                serde_json::from_str(&content).expect("parse GoldenTestCase");

            let actual_findings =
                evaluate_frame(&test_case.input.frame, test_case.input.light.as_ref());

            // Assert that every expected finding is present in actual findings
            for expected in &test_case.expected_findings {
                let matched = actual_findings.iter().find(|f| f.id == expected.id);
                assert!(
                    matched.is_some(),
                    "Case '{}': expected finding '{}' was not triggered. Actual: {:?}",
                    test_case.id,
                    expected.id,
                    actual_findings
                );

                let actual = matched.unwrap();
                assert_eq!(
                    actual.severity, expected.severity,
                    "Case '{}': severity mismatch for '{}'",
                    test_case.id, expected.id
                );
                assert_eq!(
                    actual.hint_key, expected.hint_key,
                    "Case '{}': hint_key mismatch for '{}'",
                    test_case.id, expected.id
                );
            }

            count += 1;
        }
    }

    assert!(
        count >= 3,
        "Expected at least 3 golden test cases to run, ran {}",
        count
    );
    println!("Successfully ran {} golden test vectors!", count);
}
