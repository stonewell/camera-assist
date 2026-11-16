#![forbid(unsafe_code)]

//! Photo Review, batch auto-fix generation, and non-destructive album culling engine.

use compose_core::model::{Finding, Frame, LightContext, Severity};
use compose_core::rules::RulesEngine;
use media_io::{compute_auto_crop, CropRect, StraightenTransform};
use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Error, Debug)]
pub enum ReviewError {
    #[error("Serialization error: {0}")]
    Serialization(#[from] serde_json::Error),

    #[error("Photo not found: {0}")]
    PhotoNotFound(String),
}

// MARK: - Auto-Fix Recipe

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum FixKind {
    Straighten,
    AutoCrop,
    RuleOfThirdsAlignment,
    HeadroomAdjustment,
    PerspectiveTilt,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AutoFixRecipe {
    pub id: String,
    pub kind: FixKind,
    pub description: String,
    pub straighten_angle_deg: Option<f32>,
    pub crop: Option<CropRect>,
    pub confidence: f32,
    pub is_applied: bool,
}

impl AutoFixRecipe {
    pub fn straighten(angle_deg: f32, confidence: f32) -> Self {
        let transform = StraightenTransform::from_angle(angle_deg);
        let inscribed = transform.inscribed_crop(1.0);
        Self {
            id: format!("straighten_{:.1}", angle_deg),
            kind: FixKind::Straighten,
            description: format!("旋转校正 {:.1}° 并消除黑边", angle_deg),
            straighten_angle_deg: Some(angle_deg),
            crop: Some(inscribed),
            confidence,
            is_applied: false,
        }
    }

    pub fn auto_crop(crop: CropRect, description: String, confidence: f32) -> Self {
        Self {
            id: format!("crop_{:.2}_{:.2}", crop.width, crop.height),
            kind: FixKind::AutoCrop,
            description,
            straighten_angle_deg: None,
            crop: Some(crop),
            confidence,
            is_applied: false,
        }
    }

    pub fn perspective_tilt(tilt_deg: f32, confidence: f32) -> Self {
        Self {
            id: format!("perspective_{:.1}", tilt_deg),
            kind: FixKind::PerspectiveTilt,
            description: format!("透视收敛倾斜校正 {:.1}°", tilt_deg),
            straighten_angle_deg: None,
            crop: None,
            confidence,
            is_applied: false,
        }
    }
}

// MARK: - Review Photo Item

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ReviewPhotoItem {
    pub photo_id: String,
    pub file_path: String,
    pub timestamp: f64,
    pub score: u32,
    pub is_culled: bool,
    pub findings: Vec<Finding>,
    pub suggested_fixes: Vec<AutoFixRecipe>,
    pub active_crop: Option<CropRect>,
    pub active_straighten_deg: Option<f32>,
}

impl ReviewPhotoItem {
    pub fn is_good(&self) -> bool {
        self.score >= 80 && self.findings.is_empty()
    }

    pub fn is_fixable(&self) -> bool {
        !self.suggested_fixes.is_empty()
    }
}

// MARK: - Trip / Batch Summary

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TripSummary {
    pub total_photos: usize,
    pub good_photos: usize,
    pub culled_photos: usize,
    pub fixable_photos: usize,
    pub average_score: f32,
}

// MARK: - Review Engine Configuration

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewConfig {
    pub keystone_min_converge_deg: f32,
}

impl Default for ReviewConfig {
    fn default() -> Self {
        Self {
            keystone_min_converge_deg: 3.0,
        }
    }
}

// MARK: - Review Engine

pub struct ReviewEngine {
    pub rules_engine: RulesEngine,
    pub config: ReviewConfig,
}

impl Default for ReviewEngine {
    fn default() -> Self {
        Self::new(RulesEngine::default_engine())
    }
}

impl ReviewEngine {
    pub fn new(rules_engine: RulesEngine) -> Self {
        let keystone_min_converge_deg = rules_engine.config().still.keystone_min_converge_deg;
        Self {
            rules_engine,
            config: ReviewConfig {
                keystone_min_converge_deg,
            },
        }
    }

    pub fn with_config(mut self, config: ReviewConfig) -> Self {
        self.config = config;
        self
    }

    /// Evaluates a still photo (alias for analyze_photo).
    pub fn evaluate_photo(
        &self,
        photo_id: &str,
        file_path: &str,
        frame: &Frame,
        light: Option<&LightContext>,
    ) -> ReviewPhotoItem {
        self.analyze_photo(photo_id, file_path, frame, light)
    }

    /// Evaluates a still photo with an explicit custom ReviewConfig.
    pub fn evaluate_photo_with_config(
        &self,
        photo_id: &str,
        file_path: &str,
        frame: &Frame,
        light: Option<&LightContext>,
        config: &ReviewConfig,
    ) -> ReviewPhotoItem {
        self.analyze_photo_with_config(photo_id, file_path, frame, light, config)
    }

    /// Evaluates a still frame photograph, generating composition findings, 0-100 score,
    /// and non-destructive auto-fix recipes.
    pub fn analyze_photo(
        &self,
        photo_id: &str,
        file_path: &str,
        frame: &Frame,
        light: Option<&LightContext>,
    ) -> ReviewPhotoItem {
        self.analyze_photo_with_config(photo_id, file_path, frame, light, &self.config)
    }

    /// Evaluates a still frame photograph with an explicit ReviewConfig.
    pub fn analyze_photo_with_config(
        &self,
        photo_id: &str,
        file_path: &str,
        frame: &Frame,
        light: Option<&LightContext>,
        config: &ReviewConfig,
    ) -> ReviewPhotoItem {
        let findings = self.rules_engine.evaluate(frame, light);
        let score = Self::calculate_score(&findings);

        let mut suggested_fixes = Vec::new();
        let thresholds = &self.rules_engine.config().still;

        // 1. Check Horizon Roll Straightening within auto-correctable limits
        let roll = frame.posture.roll_deg;
        let abs_roll = roll.abs();
        if abs_roll >= thresholds.tilt_min_deg && abs_roll <= thresholds.tilt_max_auto_deg {
            let straighten_angle = -roll;
            suggested_fixes.push(AutoFixRecipe::straighten(straighten_angle, 0.95));
        }

        // 2. Check Perspective Keystone Tilt Convergence
        let pitch = frame.posture.pitch_deg;
        let abs_pitch = pitch.abs();
        if abs_pitch >= config.keystone_min_converge_deg {
            suggested_fixes.push(AutoFixRecipe::perspective_tilt(pitch, 0.85));
        }

        // 3. Check Auto-Crop (Headroom, placement, floating feet)
        if let Some(crop) = compute_auto_crop(frame, &findings, thresholds) {
            suggested_fixes.push(AutoFixRecipe::auto_crop(
                crop,
                "优化构图主体留白与人物居中".to_string(),
                0.90,
            ));
        }

        ReviewPhotoItem {
            photo_id: photo_id.to_string(),
            file_path: file_path.to_string(),
            timestamp: frame.t,
            score,
            is_culled: false,
            findings,
            suggested_fixes,
            active_crop: None,
            active_straighten_deg: None,
        }
    }

    /// Derives an overall composition quality score (0..=100) based on severity deductions.
    pub fn calculate_score(findings: &[Finding]) -> u32 {
        let mut score: i32 = 100;
        for f in findings {
            let penalty = match f.severity {
                Severity::Good => 0,
                Severity::Minor => 10,
                Severity::Major => 25,
                Severity::Critical => 45,
            };
            score -= penalty;
        }
        score.clamp(0, 100) as u32
    }
}

// MARK: - Review Batch Store

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct ReviewBatchStore {
    pub photos: Vec<ReviewPhotoItem>,
}

impl ReviewBatchStore {
    pub fn new() -> Self {
        Self { photos: Vec::new() }
    }

    pub fn upsert(&mut self, item: ReviewPhotoItem) {
        if let Some(pos) = self.photos.iter().position(|p| p.photo_id == item.photo_id) {
            self.photos[pos] = item;
        } else {
            self.photos.push(item);
        }
    }

    pub fn apply_all_fixes(&mut self) {
        for photo in &mut self.photos {
            for fix in &mut photo.suggested_fixes {
                if let Some(angle) = fix.straighten_angle_deg {
                    photo.active_straighten_deg = Some(angle);
                }
                if let Some(crop) = fix.crop {
                    photo.active_crop = Some(crop);
                }
                fix.is_applied = true;
            }
        }
    }

    pub fn undo_all_fixes(&mut self) {
        for photo in &mut self.photos {
            photo.active_straighten_deg = None;
            photo.active_crop = None;
            for fix in &mut photo.suggested_fixes {
                fix.is_applied = false;
            }
        }
    }

    pub fn toggle_cull(&mut self, photo_id: &str) {
        if let Some(photo) = self.photos.iter_mut().find(|p| p.photo_id == photo_id) {
            photo.is_culled = !photo.is_culled;
        }
    }

    pub fn summarize(&self) -> TripSummary {
        let total = self.photos.len();
        if total == 0 {
            return TripSummary {
                total_photos: 0,
                good_photos: 0,
                culled_photos: 0,
                fixable_photos: 0,
                average_score: 0.0,
            };
        }

        let mut good_count = 0;
        let mut culled_count = 0;
        let mut fixable_count = 0;
        let mut score_sum = 0u64;

        for p in &self.photos {
            if p.is_good() {
                good_count += 1;
            }
            if p.is_culled {
                culled_count += 1;
            }
            if p.is_fixable() {
                fixable_count += 1;
            }
            score_sum += p.score as u64;
        }

        TripSummary {
            total_photos: total,
            good_photos: good_count,
            culled_photos: culled_count,
            fixable_photos: fixable_count,
            average_score: score_sum as f32 / total as f32,
        }
    }

    pub fn to_json(&self) -> Result<String, ReviewError> {
        Ok(serde_json::to_string_pretty(self)?)
    }

    pub fn from_json(json: &str) -> Result<Self, ReviewError> {
        Ok(serde_json::from_str(json)?)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use compose_core::model::{CameraIntrinsics, Posture};

    #[test]
    fn test_review_engine_straighten_generation() {
        let engine = ReviewEngine::default();
        let frame = Frame::new(0.0, Posture::new(3.5, 0.0))
            .with_intrinsics(CameraIntrinsics::new(24.0, 84.0));

        let item = engine.analyze_photo("p1", "IMG_0001.JPG", &frame, None);
        assert!(!item.findings.is_empty());
        assert!(item.score < 100);

        let fix = item
            .suggested_fixes
            .iter()
            .find(|f| f.kind == FixKind::Straighten);
        assert!(fix.is_some());
        let fix = fix.unwrap();
        assert!((fix.straighten_angle_deg.unwrap() - (-3.5)).abs() < 1e-4);
    }

    #[test]
    fn test_batch_store_apply_and_undo_all() {
        let mut store = ReviewBatchStore::new();
        let item = ReviewPhotoItem {
            photo_id: "p1".into(),
            file_path: "p1.jpg".into(),
            timestamp: 0.0,
            score: 75,
            is_culled: false,
            findings: vec![],
            suggested_fixes: vec![AutoFixRecipe::straighten(-2.5, 0.9)],
            active_crop: None,
            active_straighten_deg: None,
        };
        store.upsert(item.clone());

        store.apply_all_fixes();
        assert_eq!(store.photos[0].active_straighten_deg, Some(-2.5));
        assert!(store.photos[0].suggested_fixes[0].is_applied);

        store.undo_all_fixes();
        assert_eq!(store.photos[0].active_straighten_deg, None);
        assert!(!store.photos[0].suggested_fixes[0].is_applied);

        store.toggle_cull("p1");
        assert!(store.photos[0].is_culled);

        let summary = store.summarize();
        assert_eq!(summary.total_photos, 1);
        assert_eq!(summary.culled_photos, 1);
        assert_eq!(summary.fixable_photos, 1);
    }

    #[test]
    fn test_batch_store_json_roundtrip() {
        let mut store = ReviewBatchStore::new();
        store.upsert(ReviewPhotoItem {
            photo_id: "p1".into(),
            file_path: "p1.jpg".into(),
            timestamp: 10.0,
            score: 90,
            is_culled: false,
            findings: vec![],
            suggested_fixes: vec![],
            active_crop: None,
            active_straighten_deg: None,
        });

        let json = store.to_json().expect("to_json succeeds");
        let parsed = ReviewBatchStore::from_json(&json).expect("from_json succeeds");
        assert_eq!(parsed.photos.len(), 1);
        assert_eq!(parsed.photos[0].photo_id, "p1");
    }

    #[test]
    fn test_perspective_tilt_fix_and_keystone_config() {
        let engine = ReviewEngine::default();
        // Frame with pitch_deg = -5.0 (abs = 5.0 >= default keystone 3.0)
        let frame = Frame::new(0.0, Posture::new(0.0, -5.0))
            .with_intrinsics(CameraIntrinsics::new(24.0, 84.0));

        let item = engine.analyze_photo("p1", "IMG_0001.JPG", &frame, None);
        let tilt_fix = item
            .suggested_fixes
            .iter()
            .find(|f| f.kind == FixKind::PerspectiveTilt);
        assert!(tilt_fix.is_some());
        let tilt_fix = tilt_fix.unwrap();
        assert_eq!(tilt_fix.kind, FixKind::PerspectiveTilt);

        // When custom config requires keystone_min_converge_deg = 6.0:
        // 5.0 < 6.0 -> PerspectiveTilt should NOT be suggested
        let custom_config = ReviewConfig {
            keystone_min_converge_deg: 6.0,
        };
        let item_custom =
            engine.analyze_photo_with_config("p1", "IMG_0001.JPG", &frame, None, &custom_config);
        let tilt_fix_custom = item_custom
            .suggested_fixes
            .iter()
            .find(|f| f.kind == FixKind::PerspectiveTilt);
        assert!(tilt_fix_custom.is_none());

        // Mild pitch 1.5 < 3.0 -> no tilt fix
        let mild_frame = Frame::new(0.0, Posture::new(0.0, 1.5))
            .with_intrinsics(CameraIntrinsics::new(24.0, 84.0));
        let item_mild = engine.evaluate_photo("p2", "IMG_0002.JPG", &mild_frame, None);
        assert!(item_mild
            .suggested_fixes
            .iter()
            .find(|f| f.kind == FixKind::PerspectiveTilt)
            .is_none());
    }
}
