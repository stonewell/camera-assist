use crate::model::{Action, Audience, Finding, Severity};

/// Compound rule merger and priority sorter (§8.5 of Camera Assist Plan).
pub struct Merger;

impl Merger {
    /// Canonical priority rank within the same severity tier (lower number = higher priority).
    pub fn priority_rank(id: &str) -> u32 {
        match id {
            "crop.head" => 10,
            "multi.occlusion" => 20,
            "crop.joint" => 30,
            "combo.lower_vertical" => 40,
            "feet.floating" => 50,
            "tilt.vertical" => 60,
            "tilt.level" => 70,
            "multi.balance" => 80,
            "headroom.insufficient" | "headroom.excessive" | "headroom.allowance" => 90,
            "placement.lead_room" => 100,
            "placement.center" | "placement.thirds" => 110,
            "placement.scale" => 120,
            "edge.crowd" => 130,
            _ => 500,
        }
    }

    /// Merges compound findings (e.g., `feet.floating` + `tilt.vertical` -> `combo.lower_vertical`),
    /// deduplicates redundant action findings (`crop.joint` + `placement.scale` both asking to step back),
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

        // 2. Deduplicate `placement.scale` if `crop.joint` already requests `StepBack`
        let has_joint_step_back = findings
            .iter()
            .any(|f| f.id == "crop.joint" && matches!(f.primary_action, Action::StepBack { .. }));
        if has_joint_step_back {
            findings.retain(|f| {
                !(f.id == "placement.scale" && matches!(f.primary_action, Action::StepBack { .. }))
            });
        }

        // 3. Sort by Severity (descending), then canonical priority rank (ascending)
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
}
