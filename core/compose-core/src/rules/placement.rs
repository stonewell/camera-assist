use super::{Rule, RuleContext};
use crate::model::{Action, Audience, Facing, Finding, Severity, ShotType};

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
                let third_tol = if ctx.previous_active.contains("placement.thirds") {
                    ctx.config.placement.third_tol * 1.25
                } else {
                    ctx.config.placement.third_tol
                };
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
            ShotType::Unknown => None,
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
            ShotType::Unknown => return None,
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

/// Rule C3: Lead Room Rule (Gaze / facing direction breathing space)
#[derive(Debug, Default)]
pub struct LeadRoomRule;

impl Rule for LeadRoomRule {
    fn id(&self) -> &'static str {
        "placement.lead_room"
    }

    fn evaluate(&self, ctx: &RuleContext) -> Option<Finding> {
        let primary = ctx.frame.primary_subject()?;
        let cx = primary.bounds.center().x.clamp(0.01, 0.99);

        let (lead_space, back_space, pan_left) = match primary.facing {
            Facing::ProfileLeft | Facing::ThreeQuarterLeft => (cx, 1.0 - cx, true),
            Facing::ProfileRight | Facing::ThreeQuarterRight => (1.0 - cx, cx, false),
            Facing::Frontal | Facing::Back => return None,
        };

        let ratio = lead_space / back_space.max(0.01);
        let min_ratio = if ctx.previous_active.contains(self.id()) {
            ctx.config.lead_room.exit_ratio
        } else {
            ctx.config.lead_room.enter_ratio
        };

        if ratio < min_ratio {
            Some(
                Finding::new(
                    self.id(),
                    Severity::Minor,
                    Audience::Photographer,
                    if pan_left {
                        Action::PanLeft
                    } else {
                        Action::PanRight
                    },
                    if pan_left { "pan_left" } else { "pan_right" },
                )
                .with_metrics(ratio, min_ratio),
            )
        } else {
            None
        }
    }
}

/// Rule C4: Subject Scale Rule (Subject height ratio in frame for current ShotType)
#[derive(Debug, Default)]
pub struct ScaleRule;

impl Rule for ScaleRule {
    fn id(&self) -> &'static str {
        "placement.scale"
    }

    fn evaluate(&self, ctx: &RuleContext) -> Option<Finding> {
        let primary = ctx.frame.primary_subject()?;
        let h = primary.bounds.height;

        match primary.shot_type {
            ShotType::FullBody => {
                let (min_h, max_h) = ctx.config.scale.full_body;
                if h < min_h {
                    Some(
                        Finding::new(
                            self.id(),
                            Severity::Minor,
                            Audience::Photographer,
                            Action::StepForward { steps: 1 },
                            "step_forward",
                        )
                        .with_metrics(h, min_h),
                    )
                } else if h > max_h {
                    Some(
                        Finding::new(
                            self.id(),
                            Severity::Minor,
                            Audience::Photographer,
                            Action::StepBack { steps: 1 },
                            "step_back",
                        )
                        .with_metrics(h, max_h),
                    )
                } else {
                    None
                }
            }
            ShotType::Environmental => {
                let min_h = ctx.config.scale.environmental_min;
                if h < min_h {
                    Some(
                        Finding::new(
                            self.id(),
                            Severity::Minor,
                            Audience::Photographer,
                            Action::StepForward { steps: 1 },
                            "step_forward",
                        )
                        .with_metrics(h, min_h),
                    )
                } else {
                    None
                }
            }
            ShotType::CloseUp => {
                if h > 0.85 && ctx.frame.camera.focal_length_mm <= 28.0 {
                    Some(
                        Finding::new(
                            self.id(),
                            Severity::Minor,
                            Audience::Photographer,
                            Action::SwitchZoom { factor: 2.0 },
                            "switch_zoom_2x",
                        )
                        .with_metrics(h, 0.85),
                    )
                } else {
                    None
                }
            }
            ShotType::HalfBody | ShotType::Unknown => None,
        }
    }
}

/// Rule D1: Edge Crowd Rule (Subject bounding box or silhouette crowding horizontal edges)
#[derive(Debug, Default)]
pub struct EdgeCrowdRule;

impl Rule for EdgeCrowdRule {
    fn id(&self) -> &'static str {
        "edge.crowd"
    }

    fn evaluate(&self, ctx: &RuleContext) -> Option<Finding> {
        if ctx.frame.subjects.len() != 1 {
            return None;
        }
        let primary = ctx.frame.primary_subject()?;
        if primary.is_group {
            return None;
        }

        let min_margin = ctx.config.edge.min_margin;
        let (left_x, right_x) = if let Some(mask) = &primary.mask_summary {
            let lx = if mask.torso_cols != (0.0, 0.0) {
                mask.torso_cols.0
            } else {
                primary.bounds.min_x()
            };
            let rx = if mask.torso_cols != (0.0, 0.0) {
                mask.torso_cols.1
            } else {
                primary.bounds.max_x()
            };
            (lx, rx)
        } else {
            (primary.bounds.min_x(), primary.bounds.max_x())
        };

        let left_gap = left_x;
        let right_gap = 1.0 - right_x;

        if left_gap < min_margin && right_gap >= min_margin {
            Some(
                Finding::new(
                    self.id(),
                    Severity::Minor,
                    Audience::Photographer,
                    Action::PanLeft,
                    "pan_left",
                )
                .with_metrics(left_gap, min_margin),
            )
        } else if right_gap < min_margin && left_gap >= min_margin {
            Some(
                Finding::new(
                    self.id(),
                    Severity::Minor,
                    Audience::Photographer,
                    Action::PanRight,
                    "pan_right",
                )
                .with_metrics(right_gap, min_margin),
            )
        } else {
            None
        }
    }
}
