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

/// Rule G2: Lens Smudge / Veil Glare Detection (Minor suggestion to clean lens when hazy glare is detected).
#[derive(Debug, Clone, Copy, Default)]
pub struct LensSmudgeRule {
    /// Optional simulated glare metrics (overexposed_pct, clipped_highlight_pct, mean_luma) for evaluation.
    pub simulated_glare: Option<(f32, f32, f32)>,
}

impl LensSmudgeRule {
    pub fn new() -> Self {
        Self {
            simulated_glare: None,
        }
    }

    pub fn with_simulated_glare(
        overexposed_pct: f32,
        clipped_highlight_pct: f32,
        mean_luma: f32,
    ) -> Self {
        Self {
            simulated_glare: Some((overexposed_pct, clipped_highlight_pct, mean_luma)),
        }
    }

    /// Evaluates whether the given veil glare metrics and lighting state constitute a lens smudge.
    pub fn is_smudge_condition(
        light: Option<&LightContext>,
        overexposed_pct: f32,
        clipped_highlight_pct: f32,
        mean_luma: f32,
    ) -> bool {
        let Some(light) = usable_light(light, 0.5) else {
            return false;
        };

        overexposed_pct >= 0.08
            && clipped_highlight_pct < 0.02
            && light.ev >= 6.0
            && light.confidence >= 0.5
            && (0.45..=0.72).contains(&mean_luma)
    }

    /// Evaluates lens smudge finding explicitly with provided frame veil glare measurements.
    pub fn evaluate_glare(
        &self,
        ctx: &RuleContext,
        overexposed_pct: f32,
        clipped_highlight_pct: f32,
        mean_luma: f32,
    ) -> Option<Finding> {
        if Self::is_smudge_condition(ctx.light, overexposed_pct, clipped_highlight_pct, mean_luma) {
            Some(
                Finding::new(
                    self.id(),
                    Severity::Minor,
                    Audience::Photographer,
                    Action::CleanLens,
                    "clean_lens",
                )
                .with_metrics(overexposed_pct, 0.08),
            )
        } else {
            None
        }
    }
}

impl Rule for LensSmudgeRule {
    fn id(&self) -> &'static str {
        "lens.smudge"
    }

    fn evaluate(&self, ctx: &RuleContext) -> Option<Finding> {
        let (overexposed_pct, clipped_highlight_pct, mean_luma) =
            self.simulated_glare.unwrap_or((0.0, 0.0, 0.5));
        self.evaluate_glare(ctx, overexposed_pct, clipped_highlight_pct, mean_luma)
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

    #[test]
    fn test_lens_smudge_rule() {
        let frame = Frame::new(1.0, Posture::ZERO);
        let config = ThresholdConfig::default();
        let prev = HashSet::new();

        let light = LightContext::new(LightDirection::Front, LightQuality::Soft, None, 8.0, 0.9);
        let ctx = RuleContext {
            frame: &frame,
            light: Some(&light),
            config: &config,
            previous_active: &prev,
        };

        // 1. Valid smudge glare: overexposed=0.10 >= 0.08, clipped=0.01 < 0.02, mean_luma=0.55
        let rule = LensSmudgeRule::with_simulated_glare(0.10, 0.01, 0.55);
        let finding = rule.evaluate(&ctx);
        assert!(finding.is_some());
        let f = finding.unwrap();
        assert_eq!(f.id, "lens.smudge");
        assert_eq!(f.severity, Severity::Minor);
        assert_eq!(f.primary_action, Action::CleanLens);
        assert_eq!(f.hint_key, "clean_lens");

        // 2. Insufficient overexposed pct (0.05 < 0.08)
        let rule_low_over = LensSmudgeRule::with_simulated_glare(0.05, 0.01, 0.55);
        assert!(rule_low_over.evaluate(&ctx).is_none());

        // 3. Too much hard highlight clip (0.04 >= 0.02)
        let rule_clipped = LensSmudgeRule::with_simulated_glare(0.10, 0.04, 0.55);
        assert!(rule_clipped.evaluate(&ctx).is_none());

        // 4. Low light EV (5.0 < 6.0)
        let light_dim =
            LightContext::new(LightDirection::Front, LightQuality::Soft, None, 5.0, 0.9);
        let ctx_dim = RuleContext {
            frame: &frame,
            light: Some(&light_dim),
            config: &config,
            previous_active: &prev,
        };
        assert!(rule.evaluate(&ctx_dim).is_none());

        // 5. Low confidence light
        let light_unconf =
            LightContext::new(LightDirection::Front, LightQuality::Soft, None, 8.0, 0.3);
        let ctx_unconf = RuleContext {
            frame: &frame,
            light: Some(&light_unconf),
            config: &config,
            previous_active: &prev,
        };
        assert!(rule.evaluate(&ctx_unconf).is_none());

        // 6. Mean luma out of bounds
        let rule_dark = LensSmudgeRule::with_simulated_glare(0.10, 0.01, 0.40);
        assert!(rule_dark.evaluate(&ctx).is_none());
        let rule_bright = LensSmudgeRule::with_simulated_glare(0.10, 0.01, 0.75);
        assert!(rule_bright.evaluate(&ctx).is_none());

        // 7. Default rule has no simulated glare -> returns None
        assert!(LensSmudgeRule::default().evaluate(&ctx).is_none());
    }
}
