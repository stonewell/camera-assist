use super::{Rule, RuleContext};
use crate::model::{
    in_unit_frame, intersect_unit_frame, Action, Audience, Finding, JointType, NormalizedPoint,
    Severity, ShotType, Subject,
};

/// Rule B1: Head Crop Rule (Subject head cut off at top of screen)
/// Combines segmentation top-band head-zone verification with nose-neck geometric fallback.
#[derive(Debug, Default)]
pub struct HeadCropRule;

impl HeadCropRule {
    fn head_x_band(subject: &Subject) -> Option<(f32, f32)> {
        let nose = subject
            .joint_point(JointType::Nose, 0.3)
            .or_else(|| subject.joint_point(JointType::LeftEye, 0.3))
            .or_else(|| subject.joint_point(JointType::RightEye, 0.3))?;
        let half = (subject.bounds.width * 0.18).max(0.06);
        Some(((nose.x - half).max(0.0), (nose.x + half).min(1.0)))
    }

    fn bands_overlap(a: (f32, f32), b: (f32, f32)) -> bool {
        a.0 <= b.1 && b.0 <= a.1
    }

    fn neck_point(subject: &Subject) -> Option<NormalizedPoint> {
        if let Some(neck) = subject.joint_point(JointType::Neck, 0.3) {
            return Some(neck);
        }
        let ls = subject.joint_point(JointType::LeftShoulder, 0.3)?;
        let rs = subject.joint_point(JointType::RightShoulder, 0.3)?;
        Some(NormalizedPoint::new(
            (ls.x + rs.x) * 0.5,
            (ls.y + rs.y) * 0.5,
        ))
    }
}

impl Rule for HeadCropRule {
    fn id(&self) -> &'static str {
        "crop.head"
    }

    fn evaluate(&self, ctx: &RuleContext) -> Option<Finding> {
        let primary = ctx.frame.primary_subject()?;
        let eps = ctx.config.head.mask_top_eps.max(0.01);

        let triggered = if let Some(mask) = &primary.mask_summary {
            let touches_top = mask.touches_top || mask.top_y <= eps;
            if touches_top {
                if mask.head_cols != (0.0, 0.0) {
                    if let Some(head_band) = Self::head_x_band(primary) {
                        Self::bands_overlap(mask.head_cols, head_band)
                    } else {
                        true
                    }
                } else {
                    true
                }
            } else {
                false
            }
        } else if let (Some(nose), Some(neck)) = (
            primary.joint_point(JointType::Nose, 0.4),
            Self::neck_point(primary),
        ) {
            let top_est = nose.y - ctx.config.head.nose_neck_factor * (neck.y - nose.y).abs();
            top_est <= eps || primary.bounds.min_y() <= eps
        } else {
            primary.bounds.min_y() <= eps
        };

        if triggered {
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
/// Checks 3-joint limb chains (segment intersection + missing-terminal extrapolation)
/// as well as terminal joint proximity to screen edges.
#[derive(Debug, Default)]
pub struct JointCropRule;

impl JointCropRule {
    fn chain_cut(
        subject: &Subject,
        chain: [JointType; 3],
        min_prox_conf: f32,
        min_term_conf: f32,
        extend_ratio: f32,
    ) -> bool {
        let p0 = match subject.joint_point(chain[0], min_prox_conf) {
            Some(p) => p,
            None => return false,
        };
        let p1 = match subject.joint_point(chain[1], min_prox_conf) {
            Some(p) => p,
            None => return false,
        };

        // Check proximal segment intersection with unit frame
        if intersect_unit_frame(p0, p1).is_some() {
            return true;
        }

        if let Some(p2) = subject.joint_point(chain[2], min_term_conf) {
            if intersect_unit_frame(p1, p2).is_some() {
                return true;
            }
        } else if in_unit_frame(p0) && in_unit_frame(p1) {
            // Terminal joint missing while proximal joints are inside frame: extrapolate
            let dx = p1.x - p0.x;
            let dy = p1.y - p0.y;
            let p2_est = NormalizedPoint::new(p1.x + extend_ratio * dx, p1.y + extend_ratio * dy);
            if intersect_unit_frame(p1, p2_est).is_some() {
                return true;
            }
        }

        false
    }
}

impl Rule for JointCropRule {
    fn id(&self) -> &'static str {
        "crop.joint"
    }

    fn evaluate(&self, ctx: &RuleContext) -> Option<Finding> {
        let primary = ctx.frame.primary_subject()?;
        let min_prox = 0.45;
        let min_term = ctx.config.limb_cut.min_wrist_conf;
        let arm_extend = ctx.config.limb_cut.extend_ratio.arm;
        let leg_extend = ctx.config.limb_cut.extend_ratio.leg;
        let edge_margin = ctx.config.edge.min_margin;

        let arm_chains = [
            [
                JointType::LeftShoulder,
                JointType::LeftElbow,
                JointType::LeftWrist,
            ],
            [
                JointType::RightShoulder,
                JointType::RightElbow,
                JointType::RightWrist,
            ],
        ];

        for chain in arm_chains {
            if Self::chain_cut(primary, chain, min_prox, min_term, arm_extend) {
                return Some(Finding::new(
                    self.id(),
                    Severity::Major,
                    Audience::Photographer,
                    Action::StepBack { steps: 1 },
                    "step_back",
                ));
            }
        }

        // Leg chains are evaluated only when not an intentional HalfBody or CloseUp crop
        if !matches!(primary.shot_type, ShotType::HalfBody | ShotType::CloseUp) {
            let leg_chains = [
                [
                    JointType::LeftHip,
                    JointType::LeftKnee,
                    JointType::LeftAnkle,
                ],
                [
                    JointType::RightHip,
                    JointType::RightKnee,
                    JointType::RightAnkle,
                ],
            ];
            for chain in leg_chains {
                if Self::chain_cut(primary, chain, min_prox, min_term, leg_extend) {
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

        // Fallback: terminal joint directly in the boundary margin band
        let sensitive_joints = [
            JointType::LeftWrist,
            JointType::RightWrist,
            JointType::LeftAnkle,
            JointType::RightAnkle,
        ];

        for jt in sensitive_joints {
            if matches!(primary.shot_type, ShotType::HalfBody | ShotType::CloseUp)
                && matches!(jt, JointType::LeftAnkle | JointType::RightAnkle)
            {
                continue;
            }
            if let Some(j) = primary.joints.get(&jt) {
                if j.confidence >= min_term {
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

/// Rule B3: Feet Floating Rule (Excessive empty space below subject's feet in full-body shots)
#[derive(Debug, Default)]
pub struct FeetFloatingRule;

impl Rule for FeetFloatingRule {
    fn id(&self) -> &'static str {
        "feet.floating"
    }

    fn evaluate(&self, ctx: &RuleContext) -> Option<Finding> {
        let primary = ctx.frame.primary_subject()?;
        if primary.shot_type != ShotType::FullBody {
            return None;
        }

        let left_ankle = primary.joint_point(JointType::LeftAnkle, 0.3);
        let right_ankle = primary.joint_point(JointType::RightAnkle, 0.3);
        let max_ankle_y = match (left_ankle, right_ankle) {
            (Some(l), Some(r)) => l.y.max(r.y),
            (Some(l), None) => l.y,
            (None, Some(r)) => r.y,
            (None, None) => return None,
        };

        let mut foot_y =
            (max_ankle_y + ctx.config.feet.foot_len_ratio * primary.bounds.height).min(1.0);
        if let Some(mask) = &primary.mask_summary {
            if mask.bottom_y > max_ankle_y && mask.bottom_y <= 1.0 {
                foot_y = foot_y.max(mask.bottom_y);
            }
        }

        let bottom_gap = (1.0 - foot_y).max(0.0);
        let threshold = if ctx.previous_active.contains(self.id()) {
            ctx.config.feet.exit_gap
        } else {
            ctx.config.feet.enter_gap
        };

        if bottom_gap > threshold {
            Some(
                Finding::new(
                    self.id(),
                    Severity::Major,
                    Audience::Photographer,
                    Action::LowerPhone,
                    "lower_phone",
                )
                .with_metrics(bottom_gap, ctx.config.feet.exit_gap),
            )
        } else {
            None
        }
    }
}
