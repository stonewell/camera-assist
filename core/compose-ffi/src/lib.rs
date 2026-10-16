//! UniFFI bindings for compose-core.
#![forbid(unsafe_code)]

uniffi::setup_scaffolding!();

use compose_core::{Frame, LightContext};
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

/// Thread-safe LiveEngine instance exposed to iOS (Swift) via UniFFI.
#[derive(Debug, uniffi::Object)]
pub struct LiveEngine {
    backend: String,
    focus_rule: Mutex<Option<String>>,
}

#[uniffi::export]
impl LiveEngine {
    #[uniffi::constructor]
    pub fn new(config_json: String, backend: String) -> Result<Self, FfiError> {
        if config_json.is_empty() {
            return Err(FfiError::Config("Config JSON cannot be empty".into()));
        }

        Ok(Self {
            backend,
            focus_rule: Mutex::new(None),
        })
    }

    /// Process a single frame and optional light context (passed as JSON for clean FFI boundary).
    pub fn step_json(
        &self,
        frame_json: String,
        light_json: Option<String>,
        _t: f64,
    ) -> Result<LiveOutputFfi, FfiError> {
        let frame: Frame = serde_json::from_str(&frame_json)
            .map_err(|e| FfiError::Serialization(e.to_string()))?;

        let light: Option<LightContext> = match light_json {
            Some(s) if !s.is_empty() => {
                Some(serde_json::from_str(&s).map_err(|e| FfiError::Serialization(e.to_string()))?)
            }
            _ => None,
        };

        let findings = compose_core::evaluate_frame(&frame, light.as_ref());
        let is_good = findings.is_empty();
        let (active_id, hint_key) = if let Some(first) = findings.first() {
            (Some(first.id.clone()), Some(first.hint_key.clone()))
        } else {
            (None, Some("good".to_string()))
        };

        Ok(LiveOutputFfi {
            active_finding_id: active_id,
            hint_key,
            is_good_to_shoot: is_good,
            raw_findings_count: findings.len() as u32,
        })
    }

    /// Set a rule ID to prioritize / focus on (halves delay).
    pub fn set_focus(&self, rule_id: Option<String>) {
        if let Ok(mut lock) = self.focus_rule.lock() {
            *lock = rule_id;
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
}
