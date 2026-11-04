use crate::model::{Action, Audience, Finding, Severity};

/// Compound rule merger and priority sorter (§8.5 of Camera Assist Plan).
pub struct Merger;

impl Merger {
    /// Canonical priority rank within the same severity tier (lower number = higher priority).
    pub fn priority_rank(id: &str) -> u32 {
        match id {
            "crop.head" => 10,
            "lens.smudge" => 12,
            "light.low_light" => 15,
            "multi.occlusion" => 20,
            "crop.joint" => 30,
            "combo.lower_vertical" => 40,
            "feet.floating" => 50,
            "distance.distortion" => 55,
            "tilt.vertical" => 60,
            "tilt.level" => 70,
            "light.sun_in_frame" => 72,
            "light.backlit" => 74,
            "multi.unbalanced" => 80,
            "headroom.insufficient" | "headroom.excessive" | "headroom.allowance" => 90,
            "placement.lead_room" => 100,
            "placement.center" | "placement.thirds" => 110,
            "placement.scale" => 120,
            "light.harsh_top" => 123,
            "light.flat_front" => 124,
            "light.side_harsh" => 125,
            "edge.crowd" => 130,
            "distance.ultra_wide_edge" => 135,
            "distance.fill_range" => 140,
            _ => 500,
        }
    }

    /// Merges compound findings (e.g., `feet.floating` + `tilt.vertical` -> `combo.lower_vertical`),
    /// deduplicates redundant action findings (`crop.joint` or `distance.distortion` + `placement.scale` both asking to step back),
    /// deduplicates conflicting zoom suggestions (`distance.distortion` dropping `distance.ultra_wide_edge`),
    /// and sorts by severity + canonical rank.
    pub fn merge(mut findings: Vec<Finding>) -> Vec<Finding> {
        // 1. Merge `feet.floating` + `tilt.vertical` -> `combo.lower_vertical`
        let has_feet = findings.iter().any(|f| f.id == "feet.floating");
        let has_vertical = findings.iter().any(|f| f.id == "tilt.vertical");

        if has_feet && has_vertical {
            let feet_val = findings
                .iter()
                .find(|f| f.id == "feet.floating")
                .and_then(|f| f.value);
            let feet_target = findings
                .iter()
                .find(|f| f.id == "feet.floating")
                .and_then(|f| f.target);

            findings.retain(|f| f.id != "feet.floating" && f.id != "tilt.vertical");

            let mut combo = Finding::new(
                "combo.lower_vertical",
                Severity::Major,
                Audience::Photographer,
                Action::LowerPhone,
                "lower_and_vertical",
            )
            .with_secondary_action(Action::HoldVertical);

            if let (Some(v), Some(t)) = (feet_val, feet_target) {
                combo = combo.with_metrics(v, t);
            }
            findings.push(combo);
        }

        // 2. Deduplicate `placement.scale` if `crop.joint` or `distance.distortion` requests `StepBack`
        let has_joint_step_back = findings
            .iter()
            .any(|f| f.id == "crop.joint" && matches!(f.primary_action, Action::StepBack { .. }));
        let has_distortion = findings.iter().any(|f| f.id == "distance.distortion");

        if has_joint_step_back || has_distortion {
            findings.retain(|f| {
                !(f.id == "placement.scale" && matches!(f.primary_action, Action::StepBack { .. }))
            });
        }

        // 3. Deduplicate conflicting zoom hints:
        // If `distance.distortion` (Major, SwitchZoom 2.0) is present, retain only it and drop
        // `distance.ultra_wide_edge` (Minor, SwitchZoom 1.0) so contradictory zoom suggestions are not emitted in the same frame.
        if has_distortion {
            findings.retain(|f| f.id != "distance.ultra_wide_edge");
        }

        // 4. Sort by Severity (descending), then canonical priority rank (ascending)
        findings.sort_by(|a, b| {
            b.severity
                .cmp(&a.severity)
                .then_with(|| Self::priority_rank(&a.id).cmp(&Self::priority_rank(&b.id)))
        });

        findings
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_merge_feet_and_vertical_into_combo() {
        let f1 = Finding::new(
            "feet.floating",
            Severity::Major,
            Audience::Photographer,
            Action::LowerPhone,
            "lower_phone",
        )
        .with_metrics(0.22, 0.08);
        let f2 = Finding::new(
            "tilt.vertical",
            Severity::Major,
            Audience::Photographer,
            Action::HoldVertical,
            "hold_vertical",
        );

        let merged = Merger::merge(vec![f1, f2]);
        assert_eq!(merged.len(), 1);
        assert_eq!(merged[0].id, "combo.lower_vertical");
        assert_eq!(merged[0].hint_key, "lower_and_vertical");
        assert_eq!(merged[0].primary_action, Action::LowerPhone);
        assert_eq!(merged[0].secondary_action, Some(Action::HoldVertical));
    }

    #[test]
    fn test_multi_unbalanced_priority_rank() {
        assert_eq!(Merger::priority_rank("multi.unbalanced"), 80);
        assert!(Merger::priority_rank("multi.unbalanced") < Merger::priority_rank("edge.crowd"));
    }

    #[test]
    fn test_dedup_scale_when_joint_crop_present() {
        let f1 = Finding::new(
            "crop.joint",
            Severity::Major,
            Audience::Photographer,
            Action::StepBack { steps: 1 },
            "step_back",
        );
        let f2 = Finding::new(
            "placement.scale",
            Severity::Minor,
            Audience::Photographer,
            Action::StepBack { steps: 1 },
            "step_back",
        );

        let merged = Merger::merge(vec![f1, f2]);
        assert_eq!(merged.len(), 1);
        assert_eq!(merged[0].id, "crop.joint");
    }

    #[test]
    fn test_dedup_scale_when_distortion_present() {
        let f1 = Finding::new(
            "distance.distortion",
            Severity::Major,
            Audience::Photographer,
            Action::SwitchZoom { factor: 2.0 },
            "switch_zoom_step_back",
        );
        let f2 = Finding::new(
            "placement.scale",
            Severity::Minor,
            Audience::Photographer,
            Action::StepBack { steps: 1 },
            "step_back",
        );

        let merged = Merger::merge(vec![f1, f2]);
        assert_eq!(merged.len(), 1);
        assert_eq!(merged[0].id, "distance.distortion");
    }

    #[test]
    fn test_dedup_conflicting_zoom_hints() {
        let f_distortion = Finding::new(
            "distance.distortion",
            Severity::Major,
            Audience::Photographer,
            Action::SwitchZoom { factor: 2.0 },
            "switch_zoom_step_back",
        );
        let f_ultra_wide = Finding::new(
            "distance.ultra_wide_edge",
            Severity::Minor,
            Audience::Photographer,
            Action::SwitchZoom { factor: 1.0 },
            "switch_zoom_1x",
        );

        let merged = Merger::merge(vec![f_ultra_wide, f_distortion.clone()]);
        assert_eq!(merged.len(), 1);
        assert_eq!(merged[0].id, "distance.distortion");
        assert_eq!(merged[0].primary_action, Action::SwitchZoom { factor: 2.0 });
    }

    #[test]
    fn test_lighting_and_optics_priority_ranks() {
        assert_eq!(Merger::priority_rank("lens.smudge"), 12);
        assert_eq!(Merger::priority_rank("light.low_light"), 15);
        assert_eq!(Merger::priority_rank("distance.distortion"), 55);
        assert_eq!(Merger::priority_rank("light.sun_in_frame"), 72);
        assert_eq!(Merger::priority_rank("light.backlit"), 74);
        assert_eq!(Merger::priority_rank("light.harsh_top"), 123);
        assert_eq!(Merger::priority_rank("light.flat_front"), 124);
        assert_eq!(Merger::priority_rank("light.side_harsh"), 125);
        assert_eq!(Merger::priority_rank("distance.ultra_wide_edge"), 135);
        assert_eq!(Merger::priority_rank("distance.fill_range"), 140);

        // Within Minor severity, verify relative ranking
        let f_harsh = Finding::new(
            "light.harsh_top",
            Severity::Minor,
            Audience::Photographer,
            Action::MoveToShade,
            "move_to_shade",
        );
        let f_flat = Finding::new(
            "light.flat_front",
            Severity::Minor,
            Audience::Photographer,
            Action::TurnSubject { deg: 45.0 },
            "turn_subject_side",
        );
        let f_side = Finding::new(
            "light.side_harsh",
            Severity::Minor,
            Audience::Photographer,
            Action::TurnSubject { deg: 30.0 },
            "turn_face_to_light",
        );
        let f_edge = Finding::new(
            "distance.ultra_wide_edge",
            Severity::Minor,
            Audience::Photographer,
            Action::SwitchZoom { factor: 1.0 },
            "switch_zoom_1x",
        );

        let sorted = Merger::merge(vec![f_edge, f_side, f_flat, f_harsh]);
        assert_eq!(sorted[0].id, "light.harsh_top");
        assert_eq!(sorted[1].id, "light.flat_front");
        assert_eq!(sorted[2].id, "light.side_harsh");
        assert_eq!(sorted[3].id, "distance.ultra_wide_edge");
    }
}
