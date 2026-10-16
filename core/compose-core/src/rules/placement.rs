use super::{Rule, RuleContext};
use crate::model::{Action, Audience, Finding, Severity, ShotType};

/// Rule C1: Subject Placement Rule (Center framing & Rule of Thirds)
#[derive(Debug, Default)]
pub struct PlacementRule;

impl Rule for PlacementRule {
    fn id(&self) -> &'static str {
        "placement.center"
    }

    fn evaluate(&self, ctx: &RuleContext) -> Option<Finding> {
        let primary = ctx.frame.primary_subject()?;
        let center_x = primary.bounds.center().x;

        match primary.shot_type {
            ShotType::CloseUp | ShotType::HalfBody | ShotType::FullBody => {
                let tol = 0.15; // Centering tolerance
                if (center_x - 0.5).abs() > tol {
                    let is_left = center_x < 0.5;
                    Some(Finding::new(
                        self.id(),
                        Severity::Minor,
                        Audience::Photographer,
                        if is_left {
                            Action::PanLeft
                        } else {
                            Action::PanRight
                        },
                        if is_left { "pan_left" } else { "pan_right" },
                    ))
                } else {
                    None
                }
            }
            ShotType::Environmental => {
                // Rule of thirds check (closest line: 1/3 or 2/3)
                let third_tol = ctx.config.placement.third_tol;
                let dist_to_left_third = (center_x - 0.333).abs();
                let dist_to_right_third = (center_x - 0.667).abs();
                let min_dist = dist_to_left_third.min(dist_to_right_third);

                if min_dist > third_tol {
                    let move_left = center_x < 0.5;
                    Some(Finding::new(
                        "placement.thirds",
                        Severity::Minor,
                        Audience::Photographer,
                        if move_left {
                            Action::PanLeft
                        } else {
                            Action::PanRight
                        },
                        if move_left { "pan_left" } else { "pan_right" },
                    ))
                } else {
                    None
                }
            }
        }
    }
}

/// Rule C2: Headroom Rule (Upper screen margin allowance)
#[derive(Debug, Default)]
pub struct HeadroomRule;

impl Rule for HeadroomRule {
    fn id(&self) -> &'static str {
        "headroom.allowance"
    }

    fn evaluate(&self, ctx: &RuleContext) -> Option<Finding> {
        let primary = ctx.frame.primary_subject()?;

        // If head is completely cut off, HeadCropRule handles it with Critical priority
        let top_y = primary.bounds.min_y();
        if top_y <= 0.01 {
            return None;
        }

        let (min_hr, max_hr) = match primary.shot_type {
            ShotType::CloseUp => ctx.config.headroom.close_up,
            ShotType::HalfBody => ctx.config.headroom.half_body,
            ShotType::FullBody | ShotType::Environmental => ctx.config.headroom.full_body,
        };

        if top_y < min_hr {
            Some(Finding::new(
                "headroom.insufficient",
                Severity::Minor,
                Audience::Photographer,
                Action::TiltUp,
                "tilt_up",
            ))
        } else if top_y > max_hr {
            Some(Finding::new(
                "headroom.excessive",
                Severity::Minor,
                Audience::Photographer,
                Action::TiltDown,
                "tilt_down",
            ))
        } else {
            None
        }
    }
}
