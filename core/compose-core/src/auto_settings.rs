//! AutoSettingsPolicy: Automatic exposure compensation, night mode, zoom, and lighting recommendations.
//!
//! Provides smooth EV bias transitions (`bias_ramp_ev_per_sec`), night mode triggers,
//! fill light advice, and distortion-avoidance zoom suggestions.

use crate::config::AutoSettingsConfig;
use crate::model::{Frame, LightContext, LightDirection, LightQuality, ShotType};
use serde::{Deserialize, Serialize};

/// Output recommendation from `AutoSettingsPolicy`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AutoSettingsRecommendation {
    /// Target exposure value bias in EV (e.g. +0.7 for backlit, -0.3 for harsh front light).
    pub target_bias: f32,
    /// Current smoothed exposure bias in EV after applying the configured ramp rate.
    pub current_bias: f32,
    /// Whether night mode capture is recommended (EV < night_mode_min_ev).
    pub night_mode: bool,
    /// Recommended lens zoom factor (e.g. Some(2.0) for portrait distortion avoidance, Some(1.0) for ultra-wide edge).
    pub recommended_zoom: Option<f32>,
    /// Whether fill light / flash is recommended (backlit, close distance).
    pub fill_light: bool,
    /// Whether white balance should preserve warm tone (e.g. golden hour).
    pub keep_warm: bool,
}

/// State machine coordinating safe, non-destructive camera setting recommendations.
#[derive(Debug, Clone)]
pub struct AutoSettingsPolicy {
    config: AutoSettingsConfig,
    current_bias: f32,
    last_timestamp: Option<f64>,
    backlit_duration: f64,
    user_overridden: bool,
}

impl Default for AutoSettingsPolicy {
    fn default() -> Self {
        Self::with_default_config()
    }
}

impl AutoSettingsPolicy {
    /// Create a new policy with custom threshold configuration.
    pub fn new(config: AutoSettingsConfig) -> Self {
        Self {
            config,
            current_bias: 0.0,
            last_timestamp: None,
            backlit_duration: 0.0,
            user_overridden: false,
        }
    }

    /// Create policy with standard photographic default thresholds.
    pub fn with_default_config() -> Self {
        Self::new(AutoSettingsConfig::default())
    }

    pub fn config(&self) -> &AutoSettingsConfig {
        &self.config
    }

    pub fn config_mut(&mut self) -> &mut AutoSettingsConfig {
        &mut self.config
    }

    pub fn current_bias(&self) -> f32 {
        self.current_bias
    }

    pub fn set_current_bias(&mut self, bias: f32) {
        self.current_bias = bias;
    }

    pub fn user_overridden(&self) -> bool {
        self.user_overridden
    }

    pub fn set_user_overridden(&mut self, overridden: bool) {
        self.user_overridden = overridden;
    }

    /// Resets runtime state for a new capture session.
    pub fn reset(&mut self) {
        self.current_bias = 0.0;
        self.last_timestamp = None;
        self.backlit_duration = 0.0;
        self.user_overridden = false;
    }

    /// Determines target EV bias according to lighting conditions and backlight duration.
    pub fn determine_target_bias(
        &self,
        frame: &Frame,
        light: Option<&LightContext>,
        backlit_duration: f64,
    ) -> f32 {
        let Some(light) = light else {
            return 0.0;
        };

        if light.confidence < 0.5 {
            return 0.0;
        }

        // 1. Backlit condition: face darker than background or backlit direction
        let is_backlit = light.direction == LightDirection::Backlit
            || light.face_to_bg_ratio.is_some_and(|r| r < 0.45);
        if is_backlit {
            return if backlit_duration >= 1.0 {
                self.config.bias_backlit_max
            } else {
                self.config.bias_backlit
            };
        }

        // 2. Snow / High brightness scene (EV >= 15.0)
        if light.ev >= 15.0 {
            return self.config.bias_snow;
        }

        // 3. Overcast / diffused sky
        if light.direction == LightDirection::Overcast
            || (light.quality == LightQuality::Soft && light.ev <= 10.0 && light.ev >= 7.0)
        {
            return self.config.bias_overcast;
        }

        // 4. Direct harsh frontal light: slight negative bias to prevent blown out skin highlights
        if light.direction == LightDirection::Front && light.quality == LightQuality::Hard {
            return self.config.bias_front;
        }

        // 5. Normal lighting
        let _ = frame;
        0.0
    }

    /// Determines whether Night Mode should be recommended (scene EV < night_mode_min_ev).
    pub fn determine_night_mode(&self, light: Option<&LightContext>) -> bool {
        if let Some(light) = light {
            light.confidence >= 0.5
                && (light.ev < self.config.night_mode_min_ev
                    || light.quality == LightQuality::LowLight)
        } else {
            false
        }
    }

    /// Determines recommended lens zoom factor based on lens optics and subject geometry.
    pub fn determine_zoom(&self, frame: &Frame) -> Option<f32> {
        let primary = frame.primary_subject()?;
        let zoom = frame.camera.focal_length_mm / 24.0;

        // Ultra-wide lens distortion at edges: recommend 1x
        if zoom < 0.95 {
            let center_x = primary.bounds.center().x;
            let margin = center_x.min(1.0 - center_x);
            if margin < 0.20 {
                return Some(1.0);
            }
        }

        // Wide lens shooting close-up or half-body: recommend 2x
        if zoom <= self.config.zoom_threshold {
            match primary.shot_type {
                ShotType::CloseUp | ShotType::HalfBody => return Some(2.0),
                _ => {}
            }
        }

        None
    }

    /// Determines whether fill light / flash is recommended.
    pub fn determine_fill_light(&self, frame: &Frame, light: Option<&LightContext>) -> bool {
        let Some(light) = light else {
            return false;
        };
        if light.confidence < 0.5 {
            return false;
        }

        let is_backlit = light.direction == LightDirection::Backlit
            || light.face_to_bg_ratio.is_some_and(|r| r < 0.45);
        if !is_backlit {
            return false;
        }

        // Fill light is effective within ~3 meters (approx bounds height >= 0.25)
        if let Some(primary) = frame.primary_subject() {
            primary.bounds.height >= 0.20
        } else {
            false
        }
    }

    /// Determines whether white balance should preserve warm temperature (golden hour).
    pub fn determine_keep_warm(&self, light: Option<&LightContext>) -> bool {
        if let Some(light) = light {
            light.confidence >= 0.5 && light.quality == LightQuality::GoldenHour
        } else {
            false
        }
    }

    /// Calculates smooth EV ramping given elapsed delta time `dt` in seconds.
    pub fn ramp_bias(&self, current: f32, target: f32, dt: f32) -> f32 {
        let dt = dt.clamp(0.0, 0.5); // Clamp dt to prevent huge leaps
        let max_step = self.config.bias_ramp_ev_per_sec * dt;
        let diff = target - current;
        let step = diff.clamp(-max_step, max_step);
        current + step
    }

    /// Evaluates current frame statelessly for a given current bias and dt.
    pub fn evaluate(
        &self,
        frame: &Frame,
        light: Option<&LightContext>,
        current_bias: f32,
        dt: f32,
    ) -> AutoSettingsRecommendation {
        let target_bias = self.determine_target_bias(frame, light, 0.0);
        let current_bias = self.ramp_bias(current_bias, target_bias, dt);
        let night_mode = self.determine_night_mode(light);
        let recommended_zoom = self.determine_zoom(frame);
        let fill_light = self.determine_fill_light(frame, light);
        let keep_warm = self.determine_keep_warm(light);

        AutoSettingsRecommendation {
            target_bias,
            current_bias,
            night_mode,
            recommended_zoom,
            fill_light,
            keep_warm,
        }
    }

    /// Updates internal state with the latest analyzed frame and returns settings recommendations.
    pub fn update(
        &mut self,
        frame: &Frame,
        light: Option<&LightContext>,
    ) -> AutoSettingsRecommendation {
        let now = frame.t;
        let dt = if let Some(last_t) = self.last_timestamp {
            (now - last_t).max(0.0) as f32
        } else {
            0.0
        };
        self.last_timestamp = Some(now);

        // Update backlit persistence tracking
        let is_backlit = light.is_some_and(|l| {
            l.confidence >= 0.5
                && (l.direction == LightDirection::Backlit
                    || l.face_to_bg_ratio.is_some_and(|r| r < 0.45))
        });
        if is_backlit {
            self.backlit_duration += dt as f64;
        } else {
            self.backlit_duration = 0.0;
        }

        let target_bias = self.determine_target_bias(frame, light, self.backlit_duration);

        if !self.user_overridden {
            self.current_bias = self.ramp_bias(self.current_bias, target_bias, dt);
        }

        let night_mode = self.determine_night_mode(light);
        let recommended_zoom = self.determine_zoom(frame);
        let fill_light = self.determine_fill_light(frame, light);
        let keep_warm = self.determine_keep_warm(light);

        AutoSettingsRecommendation {
            target_bias,
            current_bias: self.current_bias,
            night_mode,
            recommended_zoom,
            fill_light,
            keep_warm,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{CameraIntrinsics, NormalizedRect, Posture, Subject};

    fn daylight_frame() -> Frame {
        let subject = Subject::new(1, NormalizedRect::new(0.35, 0.2, 0.3, 0.6))
            .with_shot_type(ShotType::HalfBody);
        Frame::new(0.0, Posture::ZERO)
            .with_intrinsics(CameraIntrinsics::new(24.0, 73.7))
            .with_subjects(vec![subject])
    }

    #[test]
    fn test_backlit_ramping_to_max() {
        let mut policy = AutoSettingsPolicy::with_default_config();
        let frame = daylight_frame();
        let backlit = LightContext::new(
            LightDirection::Backlit,
            LightQuality::Hard,
            Some(0.30),
            12.0,
            0.9,
        );

        // First frame at t=0: target is 0.7, dt=0 so current is 0.0
        let r0 = policy.update(&frame, Some(&backlit));
        assert_eq!(r0.target_bias, 0.7);
        assert_eq!(r0.current_bias, 0.0);
        assert!(r0.fill_light);

        // Frame at t=0.5: dt=0.5s -> bias advances by 0.5 * 1.0 EV/s = 0.5
        let frame_05 = Frame::new(0.5, Posture::ZERO).with_subjects(frame.subjects.clone());
        let r1 = policy.update(&frame_05, Some(&backlit));
        assert_eq!(r1.target_bias, 0.7);
        assert!((r1.current_bias - 0.5).abs() < 1e-4);

        // Frame at t=1.2: backlit duration >= 1.0s, target steps up to 1.3
        let frame_12 = Frame::new(1.2, Posture::ZERO).with_subjects(frame.subjects.clone());
        let r2 = policy.update(&frame_12, Some(&backlit));
        assert_eq!(r2.target_bias, 1.3);
        assert!(r2.current_bias > 0.5);
    }

    #[test]
    fn test_front_and_overcast_bias() {
        let policy = AutoSettingsPolicy::with_default_config();
        let frame = daylight_frame();

        // Front hard light -> bias -0.3
        let front = LightContext::new(
            LightDirection::Front,
            LightQuality::Hard,
            Some(1.0),
            14.0,
            0.9,
        );
        let bias_front = policy.determine_target_bias(&frame, Some(&front), 0.0);
        assert_eq!(bias_front, -0.3);

        // Overcast -> bias +0.3
        let overcast = LightContext::new(
            LightDirection::Overcast,
            LightQuality::Soft,
            Some(1.0),
            9.0,
            0.9,
        );
        let bias_overcast = policy.determine_target_bias(&frame, Some(&overcast), 0.0);
        assert_eq!(bias_overcast, 0.3);
    }

    #[test]
    fn test_night_mode_threshold() {
        let policy = AutoSettingsPolicy::with_default_config();

        // EV = 5.0 < 7.0 -> night mode true
        let low_light = LightContext::new(
            LightDirection::Unknown,
            LightQuality::LowLight,
            None,
            5.0,
            0.9,
        );
        assert!(policy.determine_night_mode(Some(&low_light)));

        // EV = 12.0 -> night mode false
        let normal = LightContext::new(LightDirection::Front, LightQuality::Soft, None, 12.0, 0.9);
        assert!(!policy.determine_night_mode(Some(&normal)));
    }

    #[test]
    fn test_zoom_recommendation() {
        let policy = AutoSettingsPolicy::with_default_config();

        // 24mm wide shooting half-body: recommends 2x
        let frame_wide = daylight_frame();
        assert_eq!(policy.determine_zoom(&frame_wide), Some(2.0));

        // 13mm ultra-wide with subject at edge: recommends 1x
        let edge_subject = Subject::new(1, NormalizedRect::new(0.02, 0.2, 0.2, 0.6));
        let frame_uw = Frame::new(0.0, Posture::ZERO)
            .with_intrinsics(CameraIntrinsics::new(13.0, 108.0))
            .with_subjects(vec![edge_subject]);
        assert_eq!(policy.determine_zoom(&frame_uw), Some(1.0));
    }

    #[test]
    fn test_user_override_and_reset() {
        let mut policy = AutoSettingsPolicy::with_default_config();
        let frame = daylight_frame();
        let backlit = LightContext::new(
            LightDirection::Backlit,
            LightQuality::Hard,
            Some(0.30),
            12.0,
            0.9,
        );

        policy.set_user_overridden(true);
        policy.set_current_bias(0.2);

        let frame_1 = Frame::new(1.0, Posture::ZERO).with_subjects(frame.subjects.clone());
        let r = policy.update(&frame_1, Some(&backlit));
        // Bias does not change when user overridden
        assert_eq!(r.current_bias, 0.2);

        policy.reset();
        assert_eq!(policy.current_bias(), 0.0);
        assert!(!policy.user_overridden());
    }
}
