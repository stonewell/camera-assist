//! UniFFI bindings for compose-core.
#![forbid(unsafe_code)]

uniffi::setup_scaffolding!();

use compose_core::{
    classify_facing, classify_shot_type, ArbiterOutput, Frame, HintArbiter, HintCatalog, Joint,
    LightContext, Merger, RulesEngine, ShotClassifierState, ShotType, ThresholdConfig,
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

/// Severity level for composition findings exposed to UniFFI.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum SeverityFfi {
    Good,
    Minor,
    Major,
    Critical,
}

impl From<compose_core::Severity> for SeverityFfi {
    fn from(s: compose_core::Severity) -> Self {
        match s {
            compose_core::Severity::Good => SeverityFfi::Good,
            compose_core::Severity::Minor => SeverityFfi::Minor,
            compose_core::Severity::Major => SeverityFfi::Major,
            compose_core::Severity::Critical => SeverityFfi::Critical,
        }
    }
}

/// Target audience of the instruction exposed to UniFFI.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum AudienceFfi {
    Photographer,
    Subject,
}

impl From<compose_core::Audience> for AudienceFfi {
    fn from(a: compose_core::Audience) -> Self {
        match a {
            compose_core::Audience::Photographer => AudienceFfi::Photographer,
            compose_core::Audience::Subject => AudienceFfi::Subject,
        }
    }
}

/// Photographic guidance action suggested by the engine exposed to UniFFI.
#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum ActionFfi {
    Rotate { deg: f32, clockwise: bool },
    HoldVertical,
    LowerPhone,
    StepBack { steps: i32 },
    StepForward { steps: i32 },
    PanLeft,
    PanRight,
    TiltUp,
    TiltDown,
    SwitchZoom { factor: f32 },
    EnableFill,
    CleanLens,
    MoveToShade,
    TurnSubject { deg: f32 },
    UseNightMode,
    Good,
}

impl From<compose_core::Action> for ActionFfi {
    fn from(a: compose_core::Action) -> Self {
        match a {
            compose_core::Action::Rotate { deg, clockwise } => ActionFfi::Rotate { deg, clockwise },
            compose_core::Action::HoldVertical => ActionFfi::HoldVertical,
            compose_core::Action::LowerPhone => ActionFfi::LowerPhone,
            compose_core::Action::StepBack { steps } => ActionFfi::StepBack { steps },
            compose_core::Action::StepForward { steps } => ActionFfi::StepForward { steps },
            compose_core::Action::PanLeft => ActionFfi::PanLeft,
            compose_core::Action::PanRight => ActionFfi::PanRight,
            compose_core::Action::TiltUp => ActionFfi::TiltUp,
            compose_core::Action::TiltDown => ActionFfi::TiltDown,
            compose_core::Action::SwitchZoom { factor } => ActionFfi::SwitchZoom { factor },
            compose_core::Action::EnableFill => ActionFfi::EnableFill,
            compose_core::Action::CleanLens => ActionFfi::CleanLens,
            compose_core::Action::MoveToShade => ActionFfi::MoveToShade,
            compose_core::Action::TurnSubject { deg } => ActionFfi::TurnSubject { deg },
            compose_core::Action::UseNightMode => ActionFfi::UseNightMode,
            compose_core::Action::Good => ActionFfi::Good,
        }
    }
}

/// Localized prompt strings exposed to UniFFI.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct HintItemFfi {
    pub primary: String,
    pub secondary: String,
    pub spoken: String,
}

impl From<compose_core::HintItem> for HintItemFfi {
    fn from(h: compose_core::HintItem) -> Self {
        Self {
            primary: h.primary,
            secondary: h.secondary,
            spoken: h.spoken,
        }
    }
}

impl From<&compose_core::HintItem> for HintItemFfi {
    fn from(h: &compose_core::HintItem) -> Self {
        Self {
            primary: h.primary.clone(),
            secondary: h.secondary.clone(),
            spoken: h.spoken.clone(),
        }
    }
}

/// Complete composition finding record exposed to UniFFI.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct FindingFfi {
    pub id: String,
    pub severity: SeverityFfi,
    pub audience: AudienceFfi,
    pub primary_action: ActionFfi,
    pub secondary_action: Option<ActionFfi>,
    pub hint_key: String,
    pub hint: HintItemFfi,
    pub hint_text: String,
    pub value: Option<f32>,
    pub target: Option<f32>,
}

impl FindingFfi {
    pub fn from_finding(f: &compose_core::Finding, hints: &HintCatalog) -> Self {
        let hint_item = hints.resolve(&f.hint_key);
        let hint_text = hint_item.primary.clone();
        Self {
            id: f.id.clone(),
            severity: f.severity.into(),
            audience: f.audience.into(),
            primary_action: f.primary_action.clone().into(),
            secondary_action: f.secondary_action.clone().map(Into::into),
            hint_key: f.hint_key.clone(),
            hint: hint_item.into(),
            hint_text,
            value: f.value,
            target: f.target,
        }
    }
}

/// Output returned by LiveEngine on every analyzed frame.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct LiveOutputFfi {
    pub active_finding_id: Option<String>,
    pub severity: SeverityFfi,
    pub audience: Option<AudienceFfi>,
    pub primary_action: Option<ActionFfi>,
    pub secondary_action: Option<ActionFfi>,
    pub value: Option<f32>,
    pub target: Option<f32>,
    pub hint_key: Option<String>,
    pub hint: Option<HintItemFfi>,
    pub hint_text: Option<String>,
    pub is_good_to_shoot: bool,
    pub raw_findings_count: u32,
}

struct EngineRuntimeState {
    engine: RulesEngine,
    arbiter: HintArbiter,
    shot_classifier: ShotClassifierState,
    hints: HintCatalog,
}

/// Thread-safe LiveEngine instance exposed to iOS (Swift) via UniFFI.
#[derive(uniffi::Object)]
pub struct LiveEngine {
    backend: String,
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
        let hints = HintCatalog::default();

        Ok(Self {
            backend,
            state: Mutex::new(EngineRuntimeState {
                engine,
                arbiter,
                shot_classifier: ShotClassifierState::new(),
                hints,
            }),
        })
    }

    /// Reconfigures thresholds and arbiter dynamically at runtime.
    pub fn reload_config(&self, config_json: String) -> Result<(), FfiError> {
        if config_json.is_empty() {
            return Err(FfiError::Config("Config JSON cannot be empty".into()));
        }

        let base_config: ThresholdConfig = serde_json::from_str(&config_json)
            .map_err(|e| FfiError::Config(format!("Invalid ThresholdConfig JSON: {e}")))?;
        let config = base_config.with_backend(&self.backend);

        let mut state = self
            .state
            .lock()
            .map_err(|_| FfiError::Internal("Mutex poisoned".into()))?;

        state.arbiter.set_config(config.arbiter.clone());
        state.engine = RulesEngine::new(config);
        Ok(())
    }

    /// One-shot composition analysis for still captures, bypassing temporal arbitration.
    pub fn analyze_still(
        &self,
        frame_json: String,
        light_json: Option<String>,
    ) -> Result<Vec<FindingFfi>, FfiError> {
        let mut frame: Frame = serde_json::from_str(&frame_json)
            .map_err(|e| FfiError::Serialization(e.to_string()))?;

        let light: Option<LightContext> = match light_json {
            Some(s) if !s.is_empty() => {
                Some(serde_json::from_str(&s).map_err(|e| FfiError::Serialization(e.to_string()))?)
            }
            _ => None,
        };

        let state = self
            .state
            .lock()
            .map_err(|_| FfiError::Internal("Mutex poisoned".into()))?;

        let config = state.engine.config();
        for subject in &mut frame.subjects {
            Joint::synthesize_neck_and_root(&mut subject.joints, 0.3);
            let (classified_facing, _) = classify_facing(subject, config);
            subject.facing = classified_facing;
            if subject.shot_type == ShotType::Unknown {
                subject.shot_type = classify_shot_type(subject, config);
            }
        }

        let findings = state.engine.evaluate(&frame, light.as_ref());
        let findings_ffi = findings
            .iter()
            .map(|f| FindingFfi::from_finding(f, &state.hints))
            .collect();

        Ok(findings_ffi)
    }

    /// Resets arbiter state and temporal history.
    pub fn reset(&self) {
        if let Ok(mut state) = self.state.lock() {
            state.arbiter.reset();
            state.shot_classifier = ShotClassifierState::new();
        }
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

        let EngineRuntimeState {
            ref engine,
            ref mut arbiter,
            ref mut shot_classifier,
            ref hints,
        } = *state;

        // Enrich subjects with synthesized Neck/Root joints and automatic Facing / ShotType classification
        let config = engine.config();
        for subject in &mut frame.subjects {
            Joint::synthesize_neck_and_root(&mut subject.joints, 0.3);
            let (classified_facing, _) = classify_facing(subject, config);
            subject.facing = classified_facing;
            if subject.shot_type == ShotType::Unknown {
                subject.shot_type = shot_classifier.update(subject, t, config);
            }
        }

        let mut findings =
            engine.evaluate_with_active(&frame, light.as_ref(), arbiter.active_ids());

        // Boost focused rule within same severity tier
        if let Some(focus) = arbiter.focus_rule().map(|s| s.to_string()) {
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
        let arbiter_out = arbiter.update(
            t,
            findings.clone(),
            has_subject,
            frame.posture.angular_speed,
        );

        match arbiter_out {
            ArbiterOutput::Silent => Ok(LiveOutputFfi {
                active_finding_id: None,
                severity: SeverityFfi::Good,
                audience: None,
                primary_action: None,
                secondary_action: None,
                value: None,
                target: None,
                hint_key: None,
                hint: None,
                hint_text: None,
                is_good_to_shoot: false,
                raw_findings_count,
            }),
            ArbiterOutput::Good => {
                let hint_item = hints.resolve("good");
                let hint_text = hint_item.primary.clone();
                Ok(LiveOutputFfi {
                    active_finding_id: None,
                    severity: SeverityFfi::Good,
                    audience: Some(AudienceFfi::Photographer),
                    primary_action: Some(ActionFfi::Good),
                    secondary_action: None,
                    value: None,
                    target: None,
                    hint_key: Some("good".to_string()),
                    hint: Some(hint_item.into()),
                    hint_text: Some(hint_text),
                    is_good_to_shoot: true,
                    raw_findings_count,
                })
            }
            ArbiterOutput::Hint(f) => {
                let hint_item = hints.resolve(&f.hint_key);
                let hint_text = hint_item.primary.clone();
                Ok(LiveOutputFfi {
                    active_finding_id: Some(f.id.clone()),
                    severity: f.severity.into(),
                    audience: Some(f.audience.into()),
                    primary_action: Some(f.primary_action.clone().into()),
                    secondary_action: f.secondary_action.clone().map(Into::into),
                    value: f.value,
                    target: f.target,
                    hint_key: Some(f.hint_key.clone()),
                    hint: Some(hint_item.into()),
                    hint_text: Some(hint_text),
                    is_good_to_shoot: false,
                    raw_findings_count,
                })
            }
            ArbiterOutput::None => {
                if let Some(first) = findings.iter().find(|f| !arbiter.is_snoozed(&f.id, t)) {
                    let hint_item = hints.resolve(&first.hint_key);
                    let hint_text = hint_item.primary.clone();
                    Ok(LiveOutputFfi {
                        active_finding_id: Some(first.id.clone()),
                        severity: first.severity.into(),
                        audience: Some(first.audience.into()),
                        primary_action: Some(first.primary_action.clone().into()),
                        secondary_action: first.secondary_action.clone().map(Into::into),
                        value: first.value,
                        target: first.target,
                        hint_key: Some(first.hint_key.clone()),
                        hint: Some(hint_item.into()),
                        hint_text: Some(hint_text),
                        is_good_to_shoot: false,
                        raw_findings_count,
                    })
                } else {
                    let hint_item = hints.resolve("good");
                    let hint_text = hint_item.primary.clone();
                    Ok(LiveOutputFfi {
                        active_finding_id: None,
                        severity: SeverityFfi::Good,
                        audience: Some(AudienceFfi::Photographer),
                        primary_action: Some(ActionFfi::Good),
                        secondary_action: None,
                        value: None,
                        target: None,
                        hint_key: Some("good".to_string()),
                        hint: Some(hint_item.into()),
                        hint_text: Some(hint_text),
                        is_good_to_shoot: true,
                        raw_findings_count,
                    })
                }
            }
        }
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
        assert_eq!(output.severity, SeverityFfi::Major);
        assert_eq!(output.audience, Some(AudienceFfi::Photographer));
        assert_eq!(
            output.primary_action,
            Some(ActionFfi::Rotate {
                deg: 3.5,
                clockwise: false
            })
        );
        assert_eq!(output.secondary_action, None);
        assert_eq!(output.value, Some(3.5));
        assert_eq!(output.target, Some(0.0));
        assert!(output.hint.is_some());
        assert_eq!(
            output.hint_text,
            Some(output.hint.as_ref().unwrap().primary.clone())
        );
        assert!(!output.is_good_to_shoot);
        assert_eq!(output.raw_findings_count, 1);
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
        assert_eq!(out_cleared.severity, SeverityFfi::Good);
        assert_eq!(out_cleared.primary_action, Some(ActionFfi::Good));
        assert_eq!(out_cleared.hint_key, Some("good".to_string()));
    }

    #[test]
    fn test_reload_config() {
        let engine = LiveEngine::new("{}".into(), "vision".into()).expect("create engine");
        // Empty config fails
        assert!(engine.reload_config("".into()).is_err());
        // Malformed config fails
        assert!(engine.reload_config("invalid json".into()).is_err());
        // Valid custom config succeeds
        let valid = engine.reload_config(r#"{"version": 1}"#.into());
        assert!(valid.is_ok());
    }

    #[test]
    fn test_analyze_still() {
        let engine = LiveEngine::new("{}".into(), "vision".into()).expect("create engine");
        let frame = Frame::new(0.0, compose_core::Posture::new(3.5, 0.0));
        let frame_json = serde_json::to_string(&frame).expect("serialize frame");

        let findings = engine
            .analyze_still(frame_json, None)
            .expect("analyze still");
        assert_eq!(findings.len(), 1);
        let f = &findings[0];
        assert_eq!(f.id, "tilt.level");
        assert_eq!(f.severity, SeverityFfi::Major);
        assert_eq!(f.audience, AudienceFfi::Photographer);
        assert_eq!(
            f.primary_action,
            ActionFfi::Rotate {
                deg: 3.5,
                clockwise: false
            }
        );
        assert_eq!(f.hint_key, "rotate_ccw");
        assert!(!f.hint.primary.is_empty());
        assert_eq!(f.hint_text, f.hint.primary);
        assert_eq!(f.value, Some(3.5));
        assert_eq!(f.target, Some(0.0));
    }

    #[test]
    fn test_reset() {
        let engine = LiveEngine::new("{}".into(), "vision".into()).expect("create engine");
        let frame = Frame::new(0.0, compose_core::Posture::new(3.5, 0.0));
        let frame_json = serde_json::to_string(&frame).expect("serialize frame");

        let _ = engine.step_json(frame_json.clone(), None, 0.0).unwrap();
        let _ = engine.step_json(frame_json, None, 0.75).unwrap();

        // Reset state
        engine.reset();

        // After reset, previous active state is cleared
        let level = serde_json::to_string(&Frame::new(0.0, compose_core::Posture::new(0.0, 0.0)))
            .expect("serialize");
        let out = engine.step_json(level, None, 0.0).unwrap();
        assert_eq!(out.active_finding_id, None);
    }
}
