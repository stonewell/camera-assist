pub mod crop;
pub mod distance;
pub mod lighting;
pub mod multi_subject;
pub mod optics;
pub mod placement;
pub mod posture;

use crate::config::ThresholdConfig;
use crate::merger::Merger;
use crate::model::{Finding, Frame, LightContext};
use std::collections::HashSet;

pub use crop::{FeetFloatingRule, HeadCropRule, JointCropRule};
pub use distance::{estimate_distance_m, DistortionRule, UltraWideEdgeRule};
pub use lighting::{BacklitRule, FlatFrontRule, HarshTopRule, SideHarshRule};
pub use multi_subject::{MultiSubjectBalanceRule, MultiSubjectOcclusionRule};
pub use optics::{is_low_light, usable_light, LowLightRule};
pub use placement::{EdgeCrowdRule, HeadroomRule, LeadRoomRule, PlacementRule, ScaleRule};
pub use posture::{PitchRule, TiltRule};

/// Context passed to each rule for single-frame evaluation.
pub struct RuleContext<'a> {
    pub frame: &'a Frame,
    pub light: Option<&'a LightContext>,
    pub config: &'a ThresholdConfig,
    pub previous_active: &'a HashSet<String>,
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
        // High priority: Critical & Major errors (crops, tilts, feet, occlusion, low-light, distortion)
        self.rules.push(Box::new(HeadCropRule));
        self.rules.push(Box::new(TiltRule));
        self.rules.push(Box::new(PitchRule));
        self.rules.push(Box::new(JointCropRule));
        self.rules.push(Box::new(FeetFloatingRule));
        self.rules.push(Box::new(MultiSubjectOcclusionRule));
        self.rules.push(Box::new(LowLightRule));
        self.rules.push(Box::new(DistortionRule));
        self.rules.push(Box::new(BacklitRule));

        // Framing, Placement, Scale, Edge margins & Lighting suggestions
        self.rules.push(Box::new(PlacementRule));
        self.rules.push(Box::new(HeadroomRule));
        self.rules.push(Box::new(LeadRoomRule));
        self.rules.push(Box::new(ScaleRule));
        self.rules.push(Box::new(EdgeCrowdRule));
        self.rules.push(Box::new(MultiSubjectBalanceRule));
        self.rules.push(Box::new(HarshTopRule));
        self.rules.push(Box::new(FlatFrontRule));
        self.rules.push(Box::new(SideHarshRule));
        self.rules.push(Box::new(UltraWideEdgeRule));
    }

    pub fn add_rule<R: Rule + 'static>(&mut self, rule: R) {
        self.rules.push(Box::new(rule));
    }

    pub fn config(&self) -> &ThresholdConfig {
        &self.config
    }

    /// Evaluate all registered rules on the current frame without prior hysteresis state.
    pub fn evaluate(&self, frame: &Frame, light: Option<&LightContext>) -> Vec<Finding> {
        let empty = HashSet::new();
        self.evaluate_with_active(frame, light, &empty)
    }

    /// Evaluate all registered rules on the current frame with hysteresis state from `previous_active`,
    /// followed by compound rule merging and canonical priority sorting.
    pub fn evaluate_with_active(
        &self,
        frame: &Frame,
        light: Option<&LightContext>,
        previous_active: &HashSet<String>,
    ) -> Vec<Finding> {
        let ctx = RuleContext {
            frame,
            light,
            config: &self.config,
            previous_active,
        };

        let mut findings = Vec::new();
        for rule in &self.rules {
            if let Some(f) = rule.evaluate(&ctx) {
                findings.push(f);
            }
        }

        Merger::merge(findings)
    }
}
