use super::optics::{is_low_light, usable_light};
use super::{Rule, RuleContext};
use crate::model::{
    Action, Audience, Finding, LightContext, LightDirection, LightQuality, Severity,
};

fn should_suppress_for_low_light(ctx: &RuleContext, light: &LightContext) -> bool {
    let was_low_light = ctx.previous_active.contains("light.low_light");
    let threshold = if was_low_light {
        ctx.config.light.ev.low_light + 0.5
    } else {
        ctx.config.light.ev.low_light
    };
    is_low_light(light, threshold)
}

/// Rule E1: Backlit Subject (Major warning when face is significantly darker than background or backlit hard light).
#[derive(Debug, Default)]
pub struct BacklitRule;

impl Rule for BacklitRule {
    fn id(&self) -> &'static str {
        "light.backlit"
    }

    fn evaluate(&self, ctx: &RuleContext) -> Option<Finding> {
        let _subject = ctx.frame.primary_subject()?;
        let light = usable_light(ctx.light, ctx.config.light.min_confidence)?;
        if should_suppress_for_low_light(ctx, light) {
            return None;
        }

        let was_active = ctx.previous_active.contains(self.id());
        let ratio_threshold = if was_active {
            ctx.config.light.backlit_face_ratio * 1.15
        } else {
            ctx.config.light.backlit_face_ratio
        };

        let ratio_triggered = light.face_to_bg_ratio.is_some_and(|r| r < ratio_threshold);
        let hard_backlit =
            light.direction == LightDirection::Backlit && light.quality == LightQuality::Hard;

        if ratio_triggered || hard_backlit {
            let mut finding = Finding::new(
                self.id(),
                Severity::Major,
                Audience::Photographer,
                Action::EnableFill,
                "enable_fill",
            );
            if let Some(r) = light.face_to_bg_ratio {
                finding = finding.with_metrics(r, ctx.config.light.backlit_face_ratio);
            }
            Some(finding)
        } else {
            None
        }
    }
}

/// Rule E2: Harsh Top Light (Minor warning for raccoon shadows from midday direct sun).
#[derive(Debug, Default)]
pub struct HarshTopRule;

impl Rule for HarshTopRule {
    fn id(&self) -> &'static str {
        "light.harsh_top"
    }

    fn evaluate(&self, ctx: &RuleContext) -> Option<Finding> {
        let _subject = ctx.frame.primary_subject()?;
        let light = usable_light(ctx.light, ctx.config.light.min_confidence)?;
        if should_suppress_for_low_light(ctx, light) {
            return None;
        }

        if light.quality != LightQuality::Hard {
            return None;
        }

        let is_top_dir = light.direction == LightDirection::Top;
        let is_top_elev = light
            .sun_elevation_deg
            .is_some_and(|e| e >= ctx.config.light.top_light_elevation);

        if is_top_dir || is_top_elev {
            let mut finding = Finding::new(
                self.id(),
                Severity::Minor,
                Audience::Photographer,
                Action::MoveToShade,
                "move_to_shade",
            );
            if let Some(elev) = light.sun_elevation_deg {
                finding = finding.with_metrics(elev, ctx.config.light.top_light_elevation);
            }
            Some(finding)
        } else {
            None
        }
    }
}

/// Rule E3: Flat Front Light (Minor suggestion to turn subject 45° for dimensionality).
#[derive(Debug, Default)]
pub struct FlatFrontRule;

impl Rule for FlatFrontRule {
    fn id(&self) -> &'static str {
        "light.flat_front"
    }

    fn evaluate(&self, ctx: &RuleContext) -> Option<Finding> {
        let _subject = ctx.frame.primary_subject()?;
        let light = usable_light(ctx.light, ctx.config.light.min_confidence)?;
        if should_suppress_for_low_light(ctx, light) {
            return None;
        }

        if light.quality != LightQuality::Hard || light.direction != LightDirection::Front {
            return None;
        }

        let is_not_top = !light
            .sun_elevation_deg
            .is_some_and(|e| e >= ctx.config.light.top_light_elevation);

        if is_not_top {
            let mut finding = Finding::new(
                self.id(),
                Severity::Minor,
                Audience::Photographer,
                Action::TurnSubject { deg: 45.0 },
                "turn_subject_side",
            );
            if let Some(elev) = light.sun_elevation_deg {
                finding = finding.with_metrics(elev, ctx.config.light.top_light_elevation);
            }
            Some(finding)
        } else {
            None
        }
    }
}

/// Rule E4: Harsh Side Light (Minor suggestion to face toward the light).
#[derive(Debug, Default)]
pub struct SideHarshRule;

impl Rule for SideHarshRule {
    fn id(&self) -> &'static str {
        "light.side_harsh"
    }

    fn evaluate(&self, ctx: &RuleContext) -> Option<Finding> {
        let _subject = ctx.frame.primary_subject()?;
        let light = usable_light(ctx.light, ctx.config.light.min_confidence)?;
        if should_suppress_for_low_light(ctx, light) {
            return None;
        }

        if light.quality != LightQuality::Hard || light.direction != LightDirection::Side {
            return None;
        }

        let is_side_harsh = light
            .sun_elevation_deg
            .is_some_and(|e| e > ctx.config.light.side_harsh_elevation);

        if is_side_harsh {
            let mut finding = Finding::new(
                self.id(),
                Severity::Minor,
                Audience::Photographer,
                Action::TurnSubject { deg: 30.0 },
                "turn_face_to_light",
            );
            if let Some(elev) = light.sun_elevation_deg {
                finding = finding.with_metrics(elev, ctx.config.light.side_harsh_elevation);
            }
            Some(finding)
        } else {
            None
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::ThresholdConfig;
    use crate::model::{Frame, NormalizedRect, Posture, Subject};
    use std::collections::HashSet;

    fn test_frame_with_subject() -> Frame {
        let subject = Subject::new(1, NormalizedRect::new(0.35, 0.15, 0.3, 0.7));
        Frame::new(1.0, Posture::ZERO).with_subjects(vec![subject])
    }

    #[test]
    fn test_lighting_requires_subject() {
        let empty_frame = Frame::new(1.0, Posture::ZERO);
        let light = LightContext::new(
            LightDirection::Backlit,
            LightQuality::Hard,
            Some(0.3),
            14.0,
            0.9,
        );
        let config = ThresholdConfig::default();
        let prev = HashSet::new();
        let ctx = RuleContext {
            frame: &empty_frame,
            light: Some(&light),
            config: &config,
            previous_active: &prev,
        };

        assert!(BacklitRule.evaluate(&ctx).is_none());
        assert!(HarshTopRule.evaluate(&ctx).is_none());
        assert!(FlatFrontRule.evaluate(&ctx).is_none());
        assert!(SideHarshRule.evaluate(&ctx).is_none());
    }

    #[test]
    fn test_lighting_suppressed_when_low_light() {
        let frame = test_frame_with_subject();
        // ev = 5.0 is below low_light threshold (7.0)
        let light = LightContext::new(
            LightDirection::Backlit,
            LightQuality::Hard,
            Some(0.3),
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

        assert!(BacklitRule.evaluate(&ctx).is_none());
        assert!(HarshTopRule.evaluate(&ctx).is_none());
        assert!(FlatFrontRule.evaluate(&ctx).is_none());
        assert!(SideHarshRule.evaluate(&ctx).is_none());
    }

    #[test]
    fn test_backlit_rule_and_hysteresis() {
        let frame = test_frame_with_subject();
        let config = ThresholdConfig::default(); // ratio = 0.45
        let prev_empty = HashSet::new();

        // Ratio 0.40 < 0.45 triggers
        let light_040 = LightContext::new(
            LightDirection::Side,
            LightQuality::Soft,
            Some(0.40),
            12.0,
            0.9,
        );
        let ctx_040 = RuleContext {
            frame: &frame,
            light: Some(&light_040),
            config: &config,
            previous_active: &prev_empty,
        };
        let f = BacklitRule.evaluate(&ctx_040);
        assert!(f.is_some());
        assert_eq!(f.unwrap().id, "light.backlit");

        // Ratio 0.48 >= 0.45: inactive does not trigger
        let light_048 = LightContext::new(
            LightDirection::Side,
            LightQuality::Soft,
            Some(0.48),
            12.0,
            0.9,
        );
        let ctx_inactive = RuleContext {
            frame: &frame,
            light: Some(&light_048),
            config: &config,
            previous_active: &prev_empty,
        };
        assert!(BacklitRule.evaluate(&ctx_inactive).is_none());

        // But with hysteresis: 0.45 * 1.15 = 0.5175. 0.48 < 0.5175 triggers
        let mut prev_active = HashSet::new();
        prev_active.insert("light.backlit".to_string());
        let ctx_active = RuleContext {
            frame: &frame,
            light: Some(&light_048),
            config: &config,
            previous_active: &prev_active,
        };
        assert!(BacklitRule.evaluate(&ctx_active).is_some());
    }

    #[test]
    fn test_harsh_top_and_flat_front_and_side_harsh() {
        let frame = test_frame_with_subject();
        let config = ThresholdConfig::default();
        let prev = HashSet::new();

        // Harsh top: Hard + elevation 70
        let mut light_top =
            LightContext::new(LightDirection::Top, LightQuality::Hard, None, 14.0, 0.9);
        light_top.sun_elevation_deg = Some(70.0);
        let ctx_top = RuleContext {
            frame: &frame,
            light: Some(&light_top),
            config: &config,
            previous_active: &prev,
        };
        let f_top = HarshTopRule.evaluate(&ctx_top);
        assert!(f_top.is_some());
        assert_eq!(f_top.unwrap().hint_key, "move_to_shade");

        // Flat front: Hard + Front + elevation 40
        let mut light_front =
            LightContext::new(LightDirection::Front, LightQuality::Hard, None, 14.0, 0.9);
        light_front.sun_elevation_deg = Some(40.0);
        let ctx_front = RuleContext {
            frame: &frame,
            light: Some(&light_front),
            config: &config,
            previous_active: &prev,
        };
        let f_front = FlatFrontRule.evaluate(&ctx_front);
        assert!(f_front.is_some());
        assert_eq!(f_front.unwrap().hint_key, "turn_subject_side");

        // Side harsh: Hard + Side + elevation 35 (> 20)
        let mut light_side =
            LightContext::new(LightDirection::Side, LightQuality::Hard, None, 14.0, 0.9);
        light_side.sun_elevation_deg = Some(35.0);
        let ctx_side = RuleContext {
            frame: &frame,
            light: Some(&light_side),
            config: &config,
            previous_active: &prev,
        };
        let f_side = SideHarshRule.evaluate(&ctx_side);
        assert!(f_side.is_some());
        assert_eq!(f_side.unwrap().hint_key, "turn_face_to_light");
    }
}
