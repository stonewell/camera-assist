use super::{Rule, RuleContext};
use crate::model::{Action, Audience, Finding, JointType, Severity};

/// Rule B1: Head Crop Rule (Subject head cut off at top of screen)
#[derive(Debug, Default)]
pub struct HeadCropRule;

impl Rule for HeadCropRule {
    fn id(&self) -> &'static str {
        "crop.head"
    }

    fn evaluate(&self, ctx: &RuleContext) -> Option<Finding> {
        let primary = ctx.frame.primary_subject()?;

        let top_y = if let Some(mask) = &primary.mask_summary {
            mask.top_y
        } else {
            primary.bounds.min_y()
        };

        let eps = ctx.config.head.mask_top_eps.max(0.01);
        if top_y <= eps {
            Some(Finding::new(
                self.id(),
                Severity::Critical,
                Audience::Photographer,
                Action::TiltUp,
                "tilt_up",
            ))
        } else {
            None
        }
    }
}

/// Rule B2: Joint Crop Rule (Cutting off wrists or ankles at screen edges)
#[derive(Debug, Default)]
pub struct JointCropRule;

impl Rule for JointCropRule {
    fn id(&self) -> &'static str {
        "crop.joint"
    }

    fn evaluate(&self, ctx: &RuleContext) -> Option<Finding> {
        let primary = ctx.frame.primary_subject()?;
        let min_conf = ctx.config.limb_cut.min_wrist_conf;
        let edge_margin = ctx.config.edge.min_margin;

        let sensitive_joints = [
            JointType::LeftWrist,
            JointType::RightWrist,
            JointType::LeftAnkle,
            JointType::RightAnkle,
        ];

        for jt in sensitive_joints {
            if let Some(j) = primary.joints.get(&jt) {
                if j.confidence >= min_conf {
                    let pt = j.point;
                    let is_near_edge = pt.x < edge_margin
                        || pt.x > (1.0 - edge_margin)
                        || pt.y < edge_margin
                        || pt.y > (1.0 - edge_margin);

                    if is_near_edge {
                        return Some(Finding::new(
                            self.id(),
                            Severity::Major,
                            Audience::Photographer,
                            Action::StepBack { steps: 1 },
                            "step_back",
                        ));
                    }
                }
            }
        }

        None
    }
}
