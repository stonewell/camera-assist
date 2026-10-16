use serde::{Deserialize, Serialize};

/// Severity level of a composition or lighting finding.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
pub enum Severity {
    Good = 0,
    Minor = 1,
    Major = 2,
    Critical = 3,
}

/// Target audience of the instruction.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Audience {
    Photographer,
    Subject,
}

/// Specific physical or camera action suggested to resolve the finding.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum Action {
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
    Good,
}

/// A composition or lighting finding produced by the rule engine.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Finding {
    pub id: String,
    pub severity: Severity,
    pub audience: Audience,
    pub primary_action: Action,
    pub secondary_action: Option<Action>,
    pub hint_key: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub value: Option<f32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub target: Option<f32>,
}

impl Finding {
    pub fn new(
        id: impl Into<String>,
        severity: Severity,
        audience: Audience,
        primary_action: Action,
        hint_key: impl Into<String>,
    ) -> Self {
        Self {
            id: id.into(),
            severity,
            audience,
            primary_action,
            secondary_action: None,
            hint_key: hint_key.into(),
            value: None,
            target: None,
        }
    }

    pub fn with_secondary_action(mut self, action: Action) -> Self {
        self.secondary_action = Some(action);
        self
    }

    pub fn with_metrics(mut self, value: f32, target: f32) -> Self {
        self.value = Some(value);
        self.target = Some(target);
        self
    }

    pub fn is_critical(&self) -> bool {
        self.severity == Severity::Critical
    }
}
