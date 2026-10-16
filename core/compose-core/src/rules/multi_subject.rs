use super::{Rule, RuleContext};
use crate::model::{Action, Audience, Finding, Severity};

/// Rule D1: Multi-Subject Occlusion Rule (Avoid people blocking each other)
#[derive(Debug, Default)]
pub struct MultiSubjectOcclusionRule;

impl Rule for MultiSubjectOcclusionRule {
    fn id(&self) -> &'static str {
        "multi.occlusion"
    }

    fn evaluate(&self, ctx: &RuleContext) -> Option<Finding> {
        let subjects = &ctx.frame.subjects;
        if subjects.len() < 2 {
            return None;
        }

        let max_iou = ctx.config.multi_subject.max_overlap_iou;

        for i in 0..subjects.len() {
            for j in (i + 1)..subjects.len() {
                let iou = subjects[i].bounds.iou(&subjects[j].bounds);
                if iou > max_iou {
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

        None
    }
}

/// Rule D2: Multi-Subject Horizontal Balance Rule
#[derive(Debug, Default)]
pub struct MultiSubjectBalanceRule;

impl Rule for MultiSubjectBalanceRule {
    fn id(&self) -> &'static str {
        "multi.unbalanced"
    }

    fn evaluate(&self, ctx: &RuleContext) -> Option<Finding> {
        let subjects = &ctx.frame.subjects;
        if subjects.len() < 2 {
            return None;
        }

        let sum_x: f32 = subjects.iter().map(|s| s.bounds.center().x).sum();
        let avg_x = sum_x / (subjects.len() as f32);
        let tol = ctx.config.multi_subject.center_balance_tol;

        if (avg_x - 0.5).abs() > tol {
            let is_left = avg_x < 0.5;
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
}
