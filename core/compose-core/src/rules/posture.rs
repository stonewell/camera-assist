use super::{Rule, RuleContext};
use crate::model::{Action, Audience, Finding, Severity};

/// Rule A1: Level Phone (Roll angle check with hysteresis and flat-phone guard)
#[derive(Debug, Default)]
pub struct TiltRule;

impl Rule for TiltRule {
    fn id(&self) -> &'static str {
        "tilt.level"
    }

    fn evaluate(&self, ctx: &RuleContext) -> Option<Finding> {
        if ctx.frame.posture.is_flatish {
            return None;
        }

        let roll = ctx.frame.posture.roll_deg;
        let threshold = if ctx.previous_active.contains(self.id()) {
            ctx.config.level.exit_deg
        } else {
            ctx.config.level.enter_deg
        };

        if roll.abs() > threshold {
            let is_cw = roll > 0.0;
            let severity = if roll.abs() >= ctx.config.level.critical_deg {
                Severity::Critical
            } else {
                Severity::Major
            };

            Some(Finding::new(
                self.id(),
                severity,
                Audience::Photographer,
                Action::Rotate {
                    deg: roll.abs(),
                    clockwise: !is_cw,
                },
                if is_cw { "rotate_ccw" } else { "rotate_cw" },
            ))
        } else {
            None
        }
    }
}

/// Rule A2: Hold Vertical (Pitch angle / perspective distortion check with hysteresis)
#[derive(Debug, Default)]
pub struct PitchRule;

impl Rule for PitchRule {
    fn id(&self) -> &'static str {
        "tilt.vertical"
    }

    fn evaluate(&self, ctx: &RuleContext) -> Option<Finding> {
        let pitch = ctx.frame.posture.pitch_deg;
        let threshold = if ctx.previous_active.contains(self.id()) {
            ctx.config.tilt.exit_deg
        } else {
            ctx.config.tilt.enter_deg
        };

        if pitch.abs() > threshold {
            Some(Finding::new(
                self.id(),
                Severity::Major,
                Audience::Photographer,
                Action::HoldVertical,
                "hold_vertical",
            ))
        } else {
            None
        }
    }
}
