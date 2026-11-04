use super::{Rule, RuleContext};
use crate::config::DistanceThresholds;
use crate::model::{
    Action, Audience, CameraIntrinsics, Facing, Finding, JointType, Severity, ShotType, Subject,
};

/// Estimates subject distance from camera using eye IPD pinhole model.
pub fn estimate_distance_m(
    subject: &Subject,
    camera: &CameraIntrinsics,
    config: &DistanceThresholds,
) -> Option<f32> {
    if subject.facing != Facing::Frontal {
        return None;
    }

    let left_eye = subject.joints.get(&JointType::LeftEye)?;
    let right_eye = subject.joints.get(&JointType::RightEye)?;
    if left_eye.confidence < config.min_confidence || right_eye.confidence < config.min_confidence {
        return None;
    }

    let dx = (left_eye.point.x - right_eye.point.x).abs();
    if dx < 0.005 {
        return None;
    }

    if !(camera.hfov_deg.is_finite() && camera.hfov_deg >= 10.0 && camera.hfov_deg <= 170.0) {
        return None;
    }

    let hfov_rad = camera.hfov_deg.to_radians();
    let f_norm = 0.5 / (hfov_rad / 2.0).tan();
    let distance = config.ipd_m * f_norm / dx;
    Some(distance)
}

/// Rule F1: Facial Perspective Distortion (Major warning when shooting close-up or half-body too close on wide lens).
#[derive(Debug, Default)]
pub struct DistortionRule;

impl Rule for DistortionRule {
    fn id(&self) -> &'static str {
        "distance.distortion"
    }

    fn evaluate(&self, ctx: &RuleContext) -> Option<Finding> {
        let primary = ctx.frame.primary_subject()?;
        let zoom = ctx.frame.camera.focal_length_mm / 24.0;
        if zoom > ctx.config.distance.distortion.wide_max_zoom {
            return None;
        }

        let max_dist = match primary.shot_type {
            ShotType::CloseUp => ctx.config.distance.distortion.close_up_max_m,
            ShotType::HalfBody => ctx.config.distance.distortion.half_body_max_m,
            _ => return None,
        };

        let was_active = ctx.previous_active.contains(self.id());
        let threshold_dist = if was_active { max_dist * 1.1 } else { max_dist };

        let dist = estimate_distance_m(primary, &ctx.frame.camera, &ctx.config.distance)?;
        if dist < threshold_dist {
            let needed_m = (max_dist - dist).max(0.0);
            let steps = ((needed_m / ctx.config.distance.step_length_m).ceil() as i32).max(1);
            Some(
                Finding::new(
                    self.id(),
                    Severity::Major,
                    Audience::Photographer,
                    Action::SwitchZoom { factor: 2.0 },
                    "switch_zoom_step_back",
                )
                .with_secondary_action(Action::StepBack { steps })
                .with_metrics(dist, max_dist),
            )
        } else {
            None
        }
    }
}

/// Rule F2: Ultra-Wide Lens Edge Stretching (Minor suggestion to switch to 1x when subject is near frame edge).
#[derive(Debug, Default)]
pub struct UltraWideEdgeRule;

impl Rule for UltraWideEdgeRule {
    fn id(&self) -> &'static str {
        "distance.ultra_wide_edge"
    }

    fn evaluate(&self, ctx: &RuleContext) -> Option<Finding> {
        let primary = ctx.frame.primary_subject()?;
        let zoom = ctx.frame.camera.focal_length_mm / 24.0;
        if zoom >= 0.95 {
            return None;
        }

        let center_x = primary.bounds.center().x;
        let margin = center_x.min(1.0 - center_x);

        if margin < ctx.config.distance.ultra_wide_edge {
            Some(
                Finding::new(
                    self.id(),
                    Severity::Minor,
                    Audience::Photographer,
                    Action::SwitchZoom { factor: 1.0 },
                    "switch_zoom_1x",
                )
                .with_metrics(margin, ctx.config.distance.ultra_wide_edge),
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
    use crate::model::{Frame, Joint, NormalizedPoint, NormalizedRect, Posture};
    use std::collections::{HashMap, HashSet};

    #[test]
    fn test_distance_estimate_pinhole_formula() {
        let mut joints = HashMap::new();
        joints.insert(
            JointType::LeftEye,
            Joint::new(JointType::LeftEye, NormalizedPoint::new(0.47, 0.25), 0.95),
        );
        joints.insert(
            JointType::RightEye,
            Joint::new(JointType::RightEye, NormalizedPoint::new(0.53, 0.25), 0.95),
        );

        let subject = Subject::new(1, NormalizedRect::new(0.35, 0.15, 0.3, 0.7))
            .with_joints(joints)
            .with_facing(Facing::Frontal)
            .with_shot_type(ShotType::HalfBody);

        let camera = CameraIntrinsics::new(24.0, 73.7);
        let config = DistanceThresholds::default();

        let dist = estimate_distance_m(&subject, &camera, &config);
        assert!(dist.is_some());
        let d = dist.unwrap();
        // Target: ≈ 0.70m (0.7005m)
        assert!((d - 0.70).abs() < 0.02, "Expected ~0.70m, got {d}");
    }

    #[test]
    fn test_distance_estimate_edge_cases() {
        let camera = CameraIntrinsics::new(24.0, 73.7);
        let config = DistanceThresholds::default();

        // Non-frontal
        let subject_side = Subject::new(1, NormalizedRect::new(0.35, 0.15, 0.3, 0.7))
            .with_facing(Facing::ProfileLeft);
        assert!(estimate_distance_m(&subject_side, &camera, &config).is_none());

        // Missing eye
        let mut joints = HashMap::new();
        joints.insert(
            JointType::LeftEye,
            Joint::new(JointType::LeftEye, NormalizedPoint::new(0.47, 0.25), 0.95),
        );
        let subject_one_eye = Subject::new(1, NormalizedRect::new(0.35, 0.15, 0.3, 0.7))
            .with_joints(joints)
            .with_facing(Facing::Frontal);
        assert!(estimate_distance_m(&subject_one_eye, &camera, &config).is_none());

        // Low confidence eye
        let mut joints_low_conf = HashMap::new();
        joints_low_conf.insert(
            JointType::LeftEye,
            Joint::new(JointType::LeftEye, NormalizedPoint::new(0.47, 0.25), 0.4),
        );
        joints_low_conf.insert(
            JointType::RightEye,
            Joint::new(JointType::RightEye, NormalizedPoint::new(0.53, 0.25), 0.95),
        );
        let subject_low_conf = Subject::new(1, NormalizedRect::new(0.35, 0.15, 0.3, 0.7))
            .with_joints(joints_low_conf)
            .with_facing(Facing::Frontal);
        assert!(estimate_distance_m(&subject_low_conf, &camera, &config).is_none());

        // Invalid camera HFOV (non-finite or outside [10.0, 170.0])
        let mut joints_valid = HashMap::new();
        joints_valid.insert(
            JointType::LeftEye,
            Joint::new(JointType::LeftEye, NormalizedPoint::new(0.47, 0.25), 0.95),
        );
        joints_valid.insert(
            JointType::RightEye,
            Joint::new(JointType::RightEye, NormalizedPoint::new(0.53, 0.25), 0.95),
        );
        let subject_valid = Subject::new(1, NormalizedRect::new(0.35, 0.15, 0.3, 0.7))
            .with_joints(joints_valid)
            .with_facing(Facing::Frontal);

        let cam_nan = CameraIntrinsics::new(24.0, f32::NAN);
        assert!(estimate_distance_m(&subject_valid, &cam_nan, &config).is_none());

        let cam_too_narrow = CameraIntrinsics::new(24.0, 5.0);
        assert!(estimate_distance_m(&subject_valid, &cam_too_narrow, &config).is_none());

        let cam_too_wide = CameraIntrinsics::new(24.0, 175.0);
        assert!(estimate_distance_m(&subject_valid, &cam_too_wide, &config).is_none());
    }

    #[test]
    fn test_distortion_rule_and_hysteresis() {
        let mut joints = HashMap::new();
        // dx = 0.06 -> dist ≈ 0.70m
        joints.insert(
            JointType::LeftEye,
            Joint::new(JointType::LeftEye, NormalizedPoint::new(0.47, 0.25), 0.95),
        );
        joints.insert(
            JointType::RightEye,
            Joint::new(JointType::RightEye, NormalizedPoint::new(0.53, 0.25), 0.95),
        );

        let subject = Subject::new(1, NormalizedRect::new(0.35, 0.15, 0.3, 0.7))
            .with_joints(joints)
            .with_facing(Facing::Frontal)
            .with_shot_type(ShotType::HalfBody); // HalfBody max_m is 1.5m

        let frame = Frame::new(1.0, Posture::ZERO).with_subjects(vec![subject]);
        let config = ThresholdConfig::default();
        let prev = HashSet::new();

        let ctx = RuleContext {
            frame: &frame,
            light: None,
            config: &config,
            previous_active: &prev,
        };

        let finding = DistortionRule.evaluate(&ctx);
        assert!(finding.is_some());
        let f = finding.unwrap();
        assert_eq!(f.id, "distance.distortion");
        assert_eq!(f.severity, Severity::Major);
        assert_eq!(f.hint_key, "switch_zoom_step_back");
        assert_eq!(f.primary_action, Action::SwitchZoom { factor: 2.0 });
    }

    #[test]
    fn test_ultra_wide_edge_rule() {
        // Ultra-wide lens: 13mm (< 24mm * 0.95 = 22.8mm)
        let camera = CameraIntrinsics::new(13.0, 108.0);
        // Subject at edge: x=0.02, w=0.20 -> center_x = 0.12 < 0.20
        let subject = Subject::new(1, NormalizedRect::new(0.02, 0.2, 0.2, 0.6));
        let frame = Frame::new(1.0, Posture::ZERO)
            .with_intrinsics(camera)
            .with_subjects(vec![subject]);
        let config = ThresholdConfig::default();
        let prev = HashSet::new();

        let ctx = RuleContext {
            frame: &frame,
            light: None,
            config: &config,
            previous_active: &prev,
        };

        let finding = UltraWideEdgeRule.evaluate(&ctx);
        assert!(finding.is_some());
        let f = finding.unwrap();
        assert_eq!(f.id, "distance.ultra_wide_edge");
        assert_eq!(f.severity, Severity::Minor);
        assert_eq!(f.hint_key, "switch_zoom_1x");
        assert_eq!(f.primary_action, Action::SwitchZoom { factor: 1.0 });
    }
}
