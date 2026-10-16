pub mod crop;
pub mod multi_subject;
pub mod placement;
pub mod posture;

use crate::config::ThresholdConfig;
use crate::model::{Finding, Frame, LightContext};

pub use crop::{HeadCropRule, JointCropRule};
pub use multi_subject::{MultiSubjectBalanceRule, MultiSubjectOcclusionRule};
pub use placement::{HeadroomRule, PlacementRule};
pub use posture::{PitchRule, TiltRule};

/// Context passed to each rule for single-frame evaluation.
pub struct RuleContext<'a> {
    pub frame: &'a Frame,
    pub light: Option<&'a LightContext>,
    pub config: &'a ThresholdConfig,
}

/// Abstract contract for a single composition rule.
pub trait Rule: Send + Sync {
    fn id(&self) -> &'static str;
    fn evaluate(&self, ctx: &RuleContext) -> Option<Finding>;
}

/// Comprehensive modular composition rule engine.
pub struct RulesEngine {
    rules: Vec<Box<dyn Rule>>,
    config: ThresholdConfig,
}

impl Default for RulesEngine {
    fn default() -> Self {
        Self::default_engine()
    }
}

impl RulesEngine {
    /// Create a new RulesEngine with custom threshold configuration.
    pub fn new(config: ThresholdConfig) -> Self {
        let mut engine = Self {
            rules: Vec::new(),
            config,
        };
        engine.register_default_rules();
        engine
    }

    /// Create default engine with standard photographic thresholds.
    pub fn default_engine() -> Self {
        Self::new(ThresholdConfig::default())
    }

    fn register_default_rules(&mut self) {
        // High priority: Critical errors (crops, tilts)
        self.rules.push(Box::new(HeadCropRule));
        self.rules.push(Box::new(TiltRule));
        self.rules.push(Box::new(PitchRule));
        self.rules.push(Box::new(JointCropRule));
        self.rules.push(Box::new(MultiSubjectOcclusionRule));

        // Framing & Placement
        self.rules.push(Box::new(PlacementRule));
        self.rules.push(Box::new(HeadroomRule));
        self.rules.push(Box::new(MultiSubjectBalanceRule));
    }

    pub fn add_rule<R: Rule + 'static>(&mut self, rule: R) {
        self.rules.push(Box::new(rule));
    }

    pub fn config(&self) -> &ThresholdConfig {
        &self.config
    }

    /// Evaluate all registered rules on the current frame.
    pub fn evaluate(&self, frame: &Frame, light: Option<&LightContext>) -> Vec<Finding> {
        let ctx = RuleContext {
            frame,
            light,
            config: &self.config,
        };

        let mut findings = Vec::new();
        for rule in &self.rules {
            if let Some(f) = rule.evaluate(&ctx) {
                findings.push(f);
            }
        }

        findings.sort_by_key(|b| std::cmp::Reverse(b.severity));

        findings
    }
}
