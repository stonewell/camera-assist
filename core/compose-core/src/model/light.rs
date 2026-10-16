use serde::{Deserialize, Serialize};

/// Categorized primary lighting direction on the subject.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum LightDirection {
    Front,
    Side,
    Backlit,
    Top,
    Overcast,
    Indoor,
    Unknown,
}

/// Character and timing of ambient light.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum LightQuality {
    Hard,
    Soft,
    GoldenHour,
    BlueHour,
    LowLight,
}

/// Fused lighting environment data.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LightContext {
    pub direction: LightDirection,
    pub quality: LightQuality,
    pub sun_azimuth_deg: Option<f32>,
    pub sun_elevation_deg: Option<f32>,
    pub face_to_bg_ratio: Option<f32>,
    pub ev: f32,
    pub confidence: f32,
}

impl LightContext {
    pub fn new(
        direction: LightDirection,
        quality: LightQuality,
        face_to_bg_ratio: Option<f32>,
        ev: f32,
        confidence: f32,
    ) -> Self {
        Self {
            direction,
            quality,
            sun_azimuth_deg: None,
            sun_elevation_deg: None,
            face_to_bg_ratio,
            ev,
            confidence,
        }
    }

    pub fn default_daylight() -> Self {
        Self {
            direction: LightDirection::Front,
            quality: LightQuality::Soft,
            sun_azimuth_deg: None,
            sun_elevation_deg: None,
            face_to_bg_ratio: Some(1.0),
            ev: 12.0,
            confidence: 0.8,
        }
    }
}
