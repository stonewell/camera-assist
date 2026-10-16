use compose_core::{HintCatalog, ThresholdConfig};
use std::fs;
use std::path::PathBuf;

#[test]
fn test_threshold_config_deserialization() {
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let config_path = manifest_dir
        .parent()
        .expect("parent of compose-core")
        .parent()
        .expect("repo root")
        .join("shared")
        .join("config")
        .join("Thresholds.json");

    assert!(
        config_path.exists(),
        "Thresholds.json must exist at {:?}",
        config_path
    );

    let content = fs::read_to_string(&config_path).expect("read Thresholds.json");
    let config = ThresholdConfig::from_json_str(&content).expect("parse ThresholdConfig");

    assert_eq!(config.version, 1);
    assert_eq!(config.level.enter_deg, 2.5);
    assert_eq!(config.level.exit_deg, 1.0);
    assert_eq!(config.tilt.enter_deg, 10.0);
    assert_eq!(config.head.mask_top_eps, 0.005);
    assert_eq!(config.placement.center_tol, 0.05);
    assert_eq!(config.headroom.close_up, (0.02, 0.12));
}

#[test]
fn test_threshold_config_defaults() {
    let default_cfg = ThresholdConfig::default();
    assert_eq!(default_cfg.level.enter_deg, 2.5);
    assert_eq!(default_cfg.multi_subject.max_overlap_iou, 0.20);
}

#[test]
fn test_hint_catalogs() {
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let shared_hints_dir = manifest_dir
        .parent()
        .expect("parent of compose-core")
        .parent()
        .expect("repo root")
        .join("shared")
        .join("hints");

    // Test zh-Hans
    let zh_path = shared_hints_dir.join("zh-Hans.json");
    assert!(zh_path.exists(), "zh-Hans.json must exist");
    let zh_content = fs::read_to_string(&zh_path).expect("read zh-Hans");
    let zh_catalog = HintCatalog::from_json_str(&zh_content).expect("parse zh-Hans catalog");

    let rotate_cw = zh_catalog.get("rotate_cw").expect("rotate_cw exists");
    assert_eq!(rotate_cw.primary, "手机顺时针转一点");
    assert_eq!(rotate_cw.spoken, "手机顺时针转");
    assert_eq!(zh_catalog.primary_text("rotate_cw"), "手机顺时针转一点");

    // Test en
    let en_path = shared_hints_dir.join("en.json");
    assert!(en_path.exists(), "en.json must exist");
    let en_content = fs::read_to_string(&en_path).expect("read en");
    let en_catalog = HintCatalog::from_json_str(&en_content).expect("parse en catalog");

    let en_rotate_cw = en_catalog.get("rotate_cw").expect("rotate_cw exists");
    assert_eq!(en_rotate_cw.primary, "Rotate clockwise slightly");
    assert_eq!(en_rotate_cw.spoken, "Rotate clockwise");
}
