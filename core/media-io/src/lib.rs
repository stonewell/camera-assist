#![forbid(unsafe_code)]

//! EXIF parsing models, non-destructive cropping, and perspective transformation math.

use compose_core::config::StillThresholds;
use compose_core::model::{CameraIntrinsics, ExposureSummary, Finding, Frame};
use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Error, Debug)]
pub enum MediaIoError {
    #[error("Invalid crop rectangle: width={width}, height={height}")]
    InvalidCrop { width: f32, height: f32 },

    #[error("Serialization error: {0}")]
    Serialization(#[from] serde_json::Error),
}

// MARK: - EXIF Metadata

/// Photographic capture metadata extracted from EXIF headers or video frame sample buffers.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ExifMetadata {
    pub focal_length_mm: f32,
    pub hfov_deg: f32,
    pub iso: f32,
    pub shutter_speed_sec: f32,
    pub ev: f32,
    pub orientation: u32,
    pub camera_make: Option<String>,
    pub camera_model: Option<String>,
}

impl ExifMetadata {
    pub fn new(
        focal_length_mm: f32,
        hfov_deg: f32,
        iso: f32,
        shutter_speed_sec: f32,
        ev: f32,
        orientation: u32,
    ) -> Self {
        Self {
            focal_length_mm,
            hfov_deg,
            iso,
            shutter_speed_sec,
            ev,
            orientation,
            camera_make: None,
            camera_model: None,
        }
    }

    pub fn to_camera_intrinsics(&self) -> CameraIntrinsics {
        CameraIntrinsics::new(self.focal_length_mm, self.hfov_deg)
    }

    pub fn to_exposure_summary(&self) -> ExposureSummary {
        ExposureSummary {
            iso: self.iso,
            shutter_speed_sec: self.shutter_speed_sec,
            ev: self.ev,
        }
    }
}

// MARK: - Non-Destructive Crop Rectangle

/// Normalized crop rectangle within normalized unit coordinate space [0.0, 1.0].
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
pub struct CropRect {
    pub x: f32,
    pub y: f32,
    pub width: f32,
    pub height: f32,
}

impl CropRect {
    pub fn new(x: f32, y: f32, width: f32, height: f32) -> Self {
        Self {
            x,
            y,
            width,
            height,
        }
    }

    /// Full frame unity crop.
    pub fn full() -> Self {
        Self {
            x: 0.0,
            y: 0.0,
            width: 1.0,
            height: 1.0,
        }
    }

    /// Clamps the crop rectangle to remain strictly within [0.0, 1.0] unit bounds.
    pub fn clamped(&self) -> Self {
        let x = self.x.clamp(0.0, 0.95);
        let y = self.y.clamp(0.0, 0.95);
        let width = self.width.clamp(0.05, 1.0 - x);
        let height = self.height.clamp(0.05, 1.0 - y);
        Self {
            x,
            y,
            width,
            height,
        }
    }

    /// Ratio of cropped image area preserved relative to the original frame area (0.0..=1.0).
    pub fn keep_ratio(&self) -> f32 {
        (self.width * self.height).clamp(0.0, 1.0)
    }

    /// Generates Adobe Camera Raw / XMP compatible sidecar XML snippet for non-destructive edits.
    pub fn to_xmp_sidecar(&self) -> String {
        let clamped = self.clamped();
        format!(
            r#"<x:xmpmeta xmlns:x="adobe:ns:meta/">
  <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
    <rdf:Description xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
      crs:CropTop="{top:.4}"
      crs:CropLeft="{left:.4}"
      crs:CropBottom="{bottom:.4}"
      crs:CropRight="{right:.4}"
      crs:HasCrop="True" />
  </rdf:RDF>
</x:xmpmeta>"#,
            top = clamped.y,
            left = clamped.x,
            bottom = clamped.y + clamped.height,
            right = clamped.x + clamped.width
        )
    }
}

// MARK: - Straighten & Inscribed Crop Transform

/// Rotational image straightening transform with automatic black-edge inscribed crop calculation.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct StraightenTransform {
    pub angle_deg: f32,
}

impl StraightenTransform {
    pub fn from_angle(angle_deg: f32) -> Self {
        Self { angle_deg }
    }

    /// Computes the largest centered inscribed crop rectangle inside the rotated frame
    /// with the same aspect ratio so no black corner margins appear after rotation.
    pub fn inscribed_crop(&self, aspect_ratio: f32) -> CropRect {
        let rad = self.angle_deg.abs().to_radians();
        let sin_a = rad.sin();
        let cos_a = rad.cos();

        let r = if aspect_ratio > 0.01 {
            aspect_ratio
        } else {
            1.0
        };
        let aspect_term = if r >= 1.0 { r } else { 1.0 / r };

        // Scale factor: 1.0 / (cos(theta) + max(r, 1/r) * sin(theta))
        let denom = cos_a + aspect_term * sin_a;
        let scale = if denom > 0.001 {
            (1.0 / denom).clamp(0.1, 1.0)
        } else {
            1.0
        };

        let width = scale;
        let height = scale;
        let x = (1.0 - width) * 0.5;
        let y = (1.0 - height) * 0.5;

        CropRect::new(x, y, width, height).clamped()
    }
}

// MARK: - Keystone & Perspective Transform

/// Perspective correction transform for architectural keystone adjustment.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct KeystoneTransform {
    pub pitch_correction_deg: f32,
    pub yaw_correction_deg: f32,
}

impl KeystoneTransform {
    pub fn new(pitch_correction_deg: f32, yaw_correction_deg: f32) -> Self {
        Self {
            pitch_correction_deg,
            yaw_correction_deg,
        }
    }

    pub fn evaluate(&self) -> bool {
        self.pitch_correction_deg.abs() > 0.5 || self.yaw_correction_deg.abs() > 0.5
    }
}

// MARK: - Auto-Crop Computation

/// Computes an optimal auto-crop rectangle addressing headroom, rule of thirds, or placement defects
/// while strictly honoring the minimum keep ratio threshold from configuration.
pub fn compute_auto_crop(
    frame: &Frame,
    findings: &[Finding],
    thresholds: &StillThresholds,
) -> Option<CropRect> {
    if findings.is_empty() {
        return None;
    }

    let primary_subject = frame.primary_subject()?;
    let box_b = primary_subject.bounds;

    let mut trim_top = 0.0f32;
    let mut trim_bottom = 0.0f32;
    let mut trim_left = 0.0f32;
    let mut trim_right = 0.0f32;
    let mut needs_crop = false;

    for f in findings {
        match f.id.as_str() {
            "headroom.excessive" | "headroom.tilt_down" | "headroom.insufficient" => {
                // Too much headroom: trim top empty space
                trim_top = (box_b.y * 0.5).clamp(0.05, 0.25);
                needs_crop = true;
            }
            "placement.rule_of_thirds" | "placement.thirds" | "placement.center" => {
                // Adjust horizontal crop to center or place subject near 1/3 line
                if box_b.x < 0.2 {
                    trim_right = 0.15;
                    needs_crop = true;
                } else if (box_b.x + box_b.width) > 0.8 {
                    trim_left = 0.15;
                    needs_crop = true;
                }
            }
            "feet.floating" | "pose.feet_floating" => {
                // Feet floating: trim bottom empty margin
                let bottom_y = box_b.y + box_b.height;
                if bottom_y < 0.85 {
                    trim_bottom = ((1.0 - bottom_y) * 0.6).clamp(0.05, 0.25);
                    needs_crop = true;
                }
            }
            _ => {}
        }
    }

    if !needs_crop {
        return None;
    }

    let crop_x = trim_left;
    let crop_y = trim_top;
    let crop_w = (1.0 - trim_left - trim_right).clamp(0.1, 1.0);
    let crop_h = (1.0 - trim_top - trim_bottom).clamp(0.1, 1.0);

    let mut rect = CropRect::new(crop_x, crop_y, crop_w, crop_h).clamped();

    // Honor crop_min_keep_ratio
    let min_keep = thresholds.crop_min_keep_ratio;
    if rect.keep_ratio() < min_keep {
        let current_ratio = rect.keep_ratio().max(0.01);
        let scale = (min_keep / current_ratio).sqrt();
        rect.width = (rect.width * scale).clamp(0.05, 1.0);
        rect.height = (rect.height * scale).clamp(0.05, 1.0);
        rect.x = rect.x.min(1.0 - rect.width).max(0.0);
        rect.y = rect.y.min(1.0 - rect.height).max(0.0);
        rect = rect.clamped();
    }

    Some(rect)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_crop_rect_clamping_and_keep_ratio() {
        let crop = CropRect::new(-0.2, 0.1, 1.5, 0.8);
        let clamped = crop.clamped();
        assert!(clamped.x >= 0.0);
        assert!(clamped.x + clamped.width <= 1.0);
        assert!(clamped.y + clamped.height <= 1.0);
        assert!(clamped.keep_ratio() <= 1.0);
        assert!(clamped.keep_ratio() > 0.0);
    }

    #[test]
    fn test_xmp_sidecar_generation() {
        let crop = CropRect::new(0.1, 0.1, 0.8, 0.8);
        let xmp = crop.to_xmp_sidecar();
        assert!(xmp.contains("crs:HasCrop=\"True\""));
        assert!(xmp.contains("crs:CropTop=\"0.1000\""));
    }

    #[test]
    fn test_straighten_inscribed_crop() {
        let straighten = StraightenTransform::from_angle(5.0);
        let crop = straighten.inscribed_crop(1.0);
        assert!(crop.keep_ratio() > 0.80);
        assert!(crop.keep_ratio() < 1.0);
        assert!((crop.x - crop.y).abs() < 1e-4); // centered square
    }

    #[test]
    fn test_compute_auto_crop_min_keep_ratio() {
        let frame = Frame::new(0.0, compose_core::model::Posture::new(0.0, 0.0))
            .with_subjects(vec![compose_core::model::Subject::new(
                1,
                compose_core::model::NormalizedRect::new(0.3, 0.4, 0.4, 0.4),
            )])
            .with_intrinsics(CameraIntrinsics::new(24.0, 84.0));
        let finding = Finding::new(
            "headroom.excessive",
            compose_core::model::Severity::Minor,
            compose_core::model::Audience::Photographer,
            compose_core::model::Action::TiltDown,
            "tilt_down",
        );
        let thresholds = StillThresholds::default();
        let auto_crop =
            compute_auto_crop(&frame, &[finding], &thresholds).expect("auto crop generated");
        assert!(auto_crop.keep_ratio() >= thresholds.crop_min_keep_ratio);
    }

    #[test]
    fn test_compute_auto_crop_headroom_and_feet_floating_combined() {
        let frame = Frame::new(0.0, compose_core::model::Posture::new(0.0, 0.0))
            .with_subjects(vec![compose_core::model::Subject::new(
                1,
                compose_core::model::NormalizedRect::new(0.3, 0.3, 0.4, 0.4),
            )])
            .with_intrinsics(CameraIntrinsics::new(24.0, 84.0));
        let findings = vec![
            Finding::new(
                "headroom.excessive",
                compose_core::model::Severity::Minor,
                compose_core::model::Audience::Photographer,
                compose_core::model::Action::TiltDown,
                "tilt_down",
            ),
            Finding::new(
                "feet.floating",
                compose_core::model::Severity::Major,
                compose_core::model::Audience::Photographer,
                compose_core::model::Action::LowerPhone,
                "lower_phone",
            ),
        ];
        let thresholds = StillThresholds {
            crop_min_keep_ratio: 0.65,
            ..Default::default()
        };
        let auto_crop =
            compute_auto_crop(&frame, &findings, &thresholds).expect("auto crop generated");
        assert!(auto_crop.keep_ratio() >= thresholds.crop_min_keep_ratio);
        assert!(auto_crop.y > 0.0);
        assert!(auto_crop.y + auto_crop.height <= 1.0);
        assert!(auto_crop.x + auto_crop.width <= 1.0);
    }
}
