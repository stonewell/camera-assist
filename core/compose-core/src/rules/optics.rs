use super::{Rule, RuleContext};
use crate::model::{Action, Audience, Finding, LightContext, LightQuality, Severity};

/// Filters light context by confidence threshold.
pub fn usable_light(light: Option<&LightContext>, min_confidence: f32) -> Option<&LightContext> {
    light.filter(|l| l.confidence >= min_confidence)
}

/// Checks if current lighting is classified as low-light condition.
pub fn is_low_light(light: &LightContext, ev_threshold: f32) -> bool {
    light.quality == LightQuality::LowLight || light.ev < ev_threshold
}

/// Rule G1: Low Light Detection (Critical guidance when scene EV is below low-light threshold).
#[derive(Debug, Default)]
pub struct LowLightRule;

impl Rule for LowLightRule {
    fn id(&self) -> &'static str {
        "light.low_light"
    }

    fn evaluate(&self, ctx: &RuleContext) -> Option<Finding> {
        let light = usable_light(ctx.light, ctx.config.light.min_confidence)?;
        let was_active = ctx.previous_active.contains(self.id());
        let threshold = if was_active {
            ctx.config.light.ev.low_light + 0.5
        } else {
            ctx.config.light.ev.low_light
        };

        if is_low_light(light, threshold) {
            Some(
                Finding::new(
                    self.id(),
                    Severity::Critical,
                    Audience::Photographer,
                    Action::UseNightMode,
                    "use_night_mode",
                )
                .with_metrics(light.ev, ctx.config.light.ev.low_light),
            )
        } else {
            None
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::ThresholdConfig;
    use crate::model::{Frame, LightDirection, Posture};
    use std::collections::HashSet;

    #[test]
    fn test_low_light_no_subject() {
        let frame = Frame::new(1.0, Posture::ZERO);
        let light = LightContext::new(
            LightDirection::Unknown,
            LightQuality::LowLight,
            None,
            5.0,
            0.9,
        );
        let config = ThresholdConfig::default();
        let prev = HashSet::new();
        let ctx = RuleContext {
            frame: &frame,
            light: Some(&light),
            config: &config,
            previous_active: &prev,
        };

        let finding = LowLightRule.evaluate(&ctx);
        assert!(finding.is_some());
        let f = finding.unwrap();
        assert_eq!(f.id, "light.low_light");
        assert_eq!(f.severity, Severity::Critical);
        assert_eq!(f.hint_key, "use_night_mode");
        assert_eq!(f.primary_action, Action::UseNightMode);
    }

    #[test]
    fn test_low_light_missing_or_low_confidence() {
        let frame = Frame::new(1.0, Posture::ZERO);
        let config = ThresholdConfig::default();
        let prev = HashSet::new();

        // Missing light
        let ctx_none = RuleContext {
            frame: &frame,
            light: None,
            config: &config,
            previous_active: &prev,
        };
        assert!(LowLightRule.evaluate(&ctx_none).is_none());

        // Low confidence light
        let light_low_conf = LightContext::new(
            LightDirection::Front,
            LightQuality::LowLight,
            None,
            5.0,
            0.3,
        );
        let ctx_low = RuleContext {
            frame: &frame,
            light: Some(&light_low_conf),
            config: &config,
            previous_active: &prev,
        };
        assert!(LowLightRule.evaluate(&ctx_low).is_none());
    }

    #[test]
    fn test_low_light_hysteresis() {
        let frame = Frame::new(1.0, Posture::ZERO);
        let config = ThresholdConfig::default(); // low_light default = 7.0
        let light_at_7_2 =
            LightContext::new(LightDirection::Front, LightQuality::Soft, None, 7.2, 0.9);

        // Inactive: 7.2 >= 7.0 -> None
        let prev_empty = HashSet::new();
        let ctx_inactive = RuleContext {
            frame: &frame,
            light: Some(&light_at_7_2),
            config: &config,
            previous_active: &prev_empty,
        };
        assert!(LowLightRule.evaluate(&ctx_inactive).is_none());

        // Active: threshold is 7.0 + 0.5 = 7.5. 7.2 < 7.5 -> Still active
        let mut prev_active = HashSet::new();
        prev_active.insert("light.low_light".to_string());
        let ctx_active = RuleContext {
            frame: &frame,
            light: Some(&light_at_7_2),
            config: &config,
            previous_active: &prev_active,
        };
        assert!(LowLightRule.evaluate(&ctx_active).is_some());
    }
}
