//! UniFFI bindings for compose-core.
#![forbid(unsafe_code)]

uniffi::setup_scaffolding!();

use compose_core::{
    classify_facing, ArbiterOutput, Frame, HintArbiter, Joint, LightContext, Merger, RulesEngine,
    ShotClassifierState, ShotType, ThresholdConfig,
};
use std::sync::Mutex;
use thiserror::Error;

#[derive(Debug, Error, uniffi::Error)]
pub enum FfiError {
    #[error("Serialization error: {0}")]
    Serialization(String),
    #[error("Invalid configuration: {0}")]
    Config(String),
    #[error("Internal engine error: {0}")]
    Internal(String),
}

/// Output returned by LiveEngine on every analyzed frame.
#[derive(Debug, Clone, uniffi::Record)]
pub struct LiveOutputFfi {
    pub active_finding_id: Option<String>,
    pub hint_key: Option<String>,
    pub is_good_to_shoot: bool,
    pub raw_findings_count: u32,
}

#[derive(Debug)]
struct EngineRuntimeState {
    arbiter: HintArbiter,
    shot_classifier: ShotClassifierState,
}

/// Thread-safe LiveEngine instance exposed to iOS (Swift) via UniFFI.
#[derive(uniffi::Object)]
pub struct LiveEngine {
    backend: String,
    engine: RulesEngine,
    state: Mutex<EngineRuntimeState>,
}

impl std::fmt::Debug for LiveEngine {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("LiveEngine")
            .field("backend", &self.backend)
            .finish()
    }
}

#[uniffi::export]
impl LiveEngine {
    #[uniffi::constructor]
    pub fn new(config_json: String, backend: String) -> Result<Self, FfiError> {
        if config_json.is_empty() {
            return Err(FfiError::Config("Config JSON cannot be empty".into()));
        }

        let base_config: ThresholdConfig = serde_json::from_str(&config_json)
            .map_err(|e| FfiError::Config(format!("Invalid ThresholdConfig JSON: {e}")))?;
        let config = base_config.with_backend(&backend);
        let arbiter = HintArbiter::new(config.arbiter.clone());
        let engine = RulesEngine::new(config);

        Ok(Self {
            backend,
            engine,
            state: Mutex::new(EngineRuntimeState {
                arbiter,
                shot_classifier: ShotClassifierState::new(),
            }),
        })
    }

    /// Process a single frame and optional light context (passed as JSON for clean FFI boundary).
    pub fn step_json(
        &self,
        frame_json: String,
        light_json: Option<String>,
        t: f64,
    ) -> Result<LiveOutputFfi, FfiError> {
        let mut frame: Frame = serde_json::from_str(&frame_json)
            .map_err(|e| FfiError::Serialization(e.to_string()))?;

        let light: Option<LightContext> = match light_json {
            Some(s) if !s.is_empty() => {
                Some(serde_json::from_str(&s).map_err(|e| FfiError::Serialization(e.to_string()))?)
            }
            _ => None,
        };

        let mut state = self
            .state
            .lock()
            .map_err(|_| FfiError::Internal("Mutex poisoned".into()))?;

        // Enrich subjects with synthesized Neck/Root joints and automatic Facing / ShotType classification
        let config = self.engine.config();
        for subject in &mut frame.subjects {
            Joint::synthesize_neck_and_root(&mut subject.joints, 0.3);
            let (classified_facing, _) = classify_facing(subject, config);
            subject.facing = classified_facing;
            if subject.shot_type == ShotType::Unknown {
                subject.shot_type = state.shot_classifier.update(subject, t, config);
            }
        }

        let mut findings =
            self.engine
                .evaluate_with_active(&frame, light.as_ref(), state.arbiter.active_ids());

        // Boost focused rule within same severity tier
        if let Some(focus) = state.arbiter.focus_rule().map(|s| s.to_string()) {
            findings.sort_by(|a, b| {
                b.severity
                    .cmp(&a.severity)
                    .then_with(|| {
                        let a_focus = a.id == focus;
                        let b_focus = b.id == focus;
                        b_focus.cmp(&a_focus)
                    })
                    .then_with(|| Merger::priority_rank(&a.id).cmp(&Merger::priority_rank(&b.id)))
            });
        }

        let raw_findings_count = findings.len() as u32;
        let has_subject = !frame.subjects.is_empty();
        let arbiter_out = state.arbiter.update(
            t,
            findings.clone(),
            has_subject,
            frame.posture.angular_speed,
        );

        let (active_finding_id, hint_key, is_good_to_shoot) = match arbiter_out {
            ArbiterOutput::Silent => (None, None, false),
            ArbiterOutput::Good => (None, Some("good".to_string()), true),
            ArbiterOutput::Hint(f) => (Some(f.id), Some(f.hint_key), false),
            ArbiterOutput::None => {
                if let Some(first) = findings
                    .iter()
                    .find(|f| !state.arbiter.is_snoozed(&f.id, t))
                {
                    (Some(first.id.clone()), Some(first.hint_key.clone()), false)
                } else {
                    (None, Some("good".to_string()), true)
                }
            }
        };

        Ok(LiveOutputFfi {
            active_finding_id,
            hint_key,
            is_good_to_shoot,
            raw_findings_count,
        })
    }

    /// Set a rule ID to prioritize / focus on (halves delay).
    pub fn set_focus(&self, rule_id: Option<String>) {
        if let Ok(mut state) = self.state.lock() {
            state.arbiter.set_focus_rule(rule_id);
        }
    }

    /// Get current active backend name ("vision" or "onnx").
    pub fn backend(&self) -> String {
        self.backend.clone()
    }

    /// Version string of the rule engine.
    pub fn version(&self) -> String {
        compose_core::version().to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_engine_lifecycle() {
        let engine = LiveEngine::new("{}".into(), "vision".into()).expect("create engine");
        assert_eq!(engine.backend(), "vision");
        assert_eq!(engine.version(), "0.1.0");

        engine.set_focus(Some("feet.floating".into()));

        let frame = Frame::new(1.0, compose_core::Posture::new(3.5, 0.0));
        let frame_json = serde_json::to_string(&frame).expect("serialize frame");

        let output = engine
            .step_json(frame_json, None, 1.0)
            .expect("step execution");

        assert_eq!(output.active_finding_id, Some("tilt.level".to_string()));
        assert_eq!(output.hint_key, Some("rotate_ccw".to_string()));
        assert!(!output.is_good_to_shoot);
    }

    #[test]
    fn test_engine_motion_mute_and_arbiter_exit_hold() {
        let engine = LiveEngine::new("{}".into(), "vision".into()).expect("create engine");

        let tilted = serde_json::to_string(&Frame::new(0.0, compose_core::Posture::new(3.5, 0.0)))
            .expect("serialize");
        let level = serde_json::to_string(&Frame::new(0.9, compose_core::Posture::new(0.0, 0.0)))
            .expect("serialize");

        // Feed tilted frames across Minor enter_delay (0.70s)
        let _ = engine.step_json(tilted.clone(), None, 0.0).unwrap();
        let out_active = engine.step_json(tilted, None, 0.75).unwrap();
        assert_eq!(out_active.active_finding_id, Some("tilt.level".to_string()));

        // At t=0.9 (within 0.30s exit_hold), a single level frame is still held by HintArbiter
        let out_held = engine.step_json(level.clone(), None, 0.9).unwrap();
        assert_eq!(out_held.active_finding_id, Some("tilt.level".to_string()));

        // At t=1.2 (past exit_hold), it clears to good
        let out_cleared = engine.step_json(level, None, 1.2).unwrap();
        assert_eq!(out_cleared.active_finding_id, None);
        assert!(out_cleared.is_good_to_shoot);
    }
}
