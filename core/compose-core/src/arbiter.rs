use crate::config::ArbiterThresholds;
use crate::merger::Merger;
use crate::model::{Finding, Severity};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};

/// Output of the temporal HintArbiter on each frame.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum ArbiterOutput {
    /// Display a single active composition hint.
    Hint(Finding),
    /// Composition is good to shoot (subject present and stable for >= good_hold).
    Good,
    /// Phone is moving rapidly (`angular_speed > motion_mute`); mute hints.
    Silent,
    /// No active hint and not yet in Good state (e.g., no subject or warming up).
    None,
}

#[derive(Debug, Clone)]
struct ActiveHint {
    finding: Finding,
    shown_since: f64,
    last_seen: f64,
}

/// Stateful temporal hint arbiter implementing the 7 anti-flicker mechanisms (§8.6).
#[derive(Debug, Clone)]
pub struct HintArbiter {
    config: ArbiterThresholds,
    focus_rule: Option<String>,
    current: Option<ActiveHint>,
    candidate_since: HashMap<String, f64>,
    snoozed_until: HashMap<String, f64>,
    good_since: Option<f64>,
    active_rule_ids: HashSet<String>,
}

impl Default for HintArbiter {
    fn default() -> Self {
        Self::new(ArbiterThresholds::default())
    }
}

impl HintArbiter {
    pub fn new(config: ArbiterThresholds) -> Self {
        Self {
            config,
            focus_rule: None,
            current: None,
            candidate_since: HashMap::new(),
            snoozed_until: HashMap::new(),
            good_since: None,
            active_rule_ids: HashSet::new(),
        }
    }

    pub fn set_focus_rule(&mut self, rule_id: Option<String>) {
        self.focus_rule = rule_id;
    }

    pub fn focus_rule(&self) -> Option<&str> {
        self.focus_rule.as_deref()
    }

    pub fn reset(&mut self) {
        self.current = None;
        self.candidate_since.clear();
        self.snoozed_until.clear();
        self.good_since = None;
        self.active_rule_ids.clear();
    }

    /// Returns the set of rule IDs currently active for hysteresis exit-threshold evaluation.
    pub fn active_ids(&self) -> &HashSet<String> {
        &self.active_rule_ids
    }

    /// Returns true if `rule_id` is currently snoozed at timestamp `t`.
    pub fn is_snoozed(&self, rule_id: &str, t: f64) -> bool {
        self.snoozed_until
            .get(rule_id)
            .map(|&until| until > t)
            .unwrap_or(false)
    }

    fn sync_active_ids(&mut self) {
        self.active_rule_ids.clear();
        if let Some(active) = &self.current {
            self.active_rule_ids.insert(active.finding.id.clone());
            if active.finding.id == "combo.lower_vertical" {
                self.active_rule_ids.insert("feet.floating".to_string());
                self.active_rule_ids.insert("tilt.vertical".to_string());
            }
        }
    }

    fn effective_enter_delay(&self, finding: &Finding) -> f64 {
        let base = match finding.severity {
            Severity::Critical => self.config.enter_delay.critical,
            Severity::Major => self.config.enter_delay.major,
            Severity::Minor | Severity::Good => self.config.enter_delay.minor,
        };
        if self.focus_rule.as_deref() == Some(finding.id.as_str()) {
            base * 0.5
        } else {
            base
        }
    }

    /// Step the arbiter with the current timestamp `t`, merged `findings`, `has_subject`, and `angular_speed`.
    pub fn update(
        &mut self,
        t: f64,
        mut findings: Vec<Finding>,
        has_subject: bool,
        angular_speed: f32,
    ) -> ArbiterOutput {
        // 1. Motion mute check
        if angular_speed > self.config.motion_mute {
            self.candidate_since.clear();
            self.good_since = None;
            return ArbiterOutput::Silent;
        }

        // 2. Expire old snoozes and filter snoozed findings
        self.snoozed_until.retain(|_, &mut until| until > t);
        findings.retain(|f| !self.snoozed_until.contains_key(&f.id));

        // 3. Re-sort findings with focus_rule boost within the same severity tier
        if let Some(focus) = &self.focus_rule {
            findings.sort_by(|a, b| {
                b.severity
                    .cmp(&a.severity)
                    .then_with(|| {
                        let a_focus = &a.id == focus;
                        let b_focus = &b.id == focus;
                        b_focus.cmp(&a_focus)
                    })
                    .then_with(|| Merger::priority_rank(&a.id).cmp(&Merger::priority_rank(&b.id)))
            });
        }

        // 4. Update candidate timers
        let present_ids: HashSet<String> = findings.iter().map(|f| f.id.clone()).collect();
        self.candidate_since
            .retain(|id, _| present_ids.contains(id));
        for f in &findings {
            self.candidate_since.entry(f.id.clone()).or_insert(t);
        }

        // 5. Evaluate existing active hint (ignore/snooze, preemption, exit hold, min show)
        if let Some(mut active) = self.current.take() {
            let still_present = findings.iter().find(|f| f.id == active.finding.id);

            if let Some(updated_finding) = still_present {
                active.finding = updated_finding.clone();
                active.last_seen = t;

                // Check ignore_after -> snooze
                if (t - active.shown_since) >= self.config.ignore_after {
                    let snoozed_id = active.finding.id.clone();
                    self.snoozed_until
                        .insert(snoozed_id.clone(), t + self.config.snooze_for);
                    self.candidate_since.remove(&snoozed_id);
                    findings.retain(|f| f.id != snoozed_id);
                } else {
                    // Check if a higher-priority finding can preempt
                    let can_preempt = findings.first().and_then(|top| {
                        if top.id == active.finding.id {
                            return None;
                        }
                        let top_since = self.candidate_since.get(&top.id).copied().unwrap_or(t);
                        let top_ready = (t - top_since) >= self.effective_enter_delay(top);
                        if !top_ready {
                            return None;
                        }
                        // Critical preempts anything immediately; otherwise wait for min_show
                        let min_shown = (t - active.shown_since) >= self.config.min_show;
                        if top.severity == Severity::Critical
                            || (min_shown && top.severity > active.finding.severity)
                        {
                            Some(top.clone())
                        } else {
                            None
                        }
                    });

                    if let Some(preempting) = can_preempt {
                        let out = ActiveHint {
                            finding: preempting.clone(),
                            shown_since: t,
                            last_seen: t,
                        };
                        self.current = Some(out);
                        self.sync_active_ids();
                        self.good_since = None;
                        return ArbiterOutput::Hint(preempting);
                    }

                    let out_finding = active.finding.clone();
                    self.current = Some(active);
                    self.sync_active_ids();
                    self.good_since = None;
                    return ArbiterOutput::Hint(out_finding);
                }
            } else {
                // Finding disappeared in raw evaluation: check exit_hold
                if (t - active.last_seen) < self.config.exit_hold {
                    let out_finding = active.finding.clone();
                    self.current = Some(active);
                    self.sync_active_ids();
                    self.good_since = None;
                    return ArbiterOutput::Hint(out_finding);
                }
                // Otherwise, exit_hold elapsed -> clear current active hint
            }
        }

        // 6. No current active hint: check if the highest-priority candidate has satisfied enter_delay
        for f in &findings {
            let since = self.candidate_since.get(&f.id).copied().unwrap_or(t);
            if (t - since) >= self.effective_enter_delay(f) {
                self.current = Some(ActiveHint {
                    finding: f.clone(),
                    shown_since: t,
                    last_seen: t,
                });
                self.sync_active_ids();
                self.good_since = None;
                return ArbiterOutput::Hint(f.clone());
            }
        }

        self.sync_active_ids();

        // 7. Check Good state when no findings exist and a subject is present
        if findings.is_empty() && has_subject {
            let since = *self.good_since.get_or_insert(t);
            if (t - since) >= self.config.good_hold {
                return ArbiterOutput::Good;
            }
        } else {
            self.good_since = None;
        }

        ArbiterOutput::None
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{Action, Audience};

    fn sample_finding(id: &str, severity: Severity) -> Finding {
        Finding::new(
            id,
            severity,
            Audience::Photographer,
            Action::TiltUp,
            "tilt_up",
        )
    }

    #[test]
    fn test_arbiter_enter_delay_and_exit_hold() {
        let mut arbiter = HintArbiter::default();
        let f = sample_finding("tilt.vertical", Severity::Major);

        // t = 0.0: candidate seen, waiting for Major enter_delay (0.40s)
        assert_eq!(
            arbiter.update(0.0, vec![f.clone()], true, 0.0),
            ArbiterOutput::None
        );
        assert_eq!(
            arbiter.update(0.2, vec![f.clone()], true, 0.0),
            ArbiterOutput::None
        );

        // t = 0.45: >= 0.4s -> enters Hint state
        assert_eq!(
            arbiter.update(0.45, vec![f.clone()], true, 0.0),
            ArbiterOutput::Hint(f.clone())
        );
        assert!(arbiter.active_ids().contains("tilt.vertical"));

        // t = 0.65: finding briefly drops out (< 0.30s exit_hold) -> still held
        assert_eq!(
            arbiter.update(0.65, vec![], true, 0.0),
            ArbiterOutput::Hint(f.clone())
        );

        // t = 0.80: 0.35s since last_seen (0.45) -> clears hint
        assert_eq!(arbiter.update(0.80, vec![], true, 0.0), ArbiterOutput::None);
        assert!(arbiter.active_ids().is_empty());
    }

    #[test]
    fn test_arbiter_snooze_and_good_hold() {
        let mut arbiter = HintArbiter::default();
        let f = sample_finding("tilt.vertical", Severity::Major);

        assert_eq!(
            arbiter.update(0.0, vec![f.clone()], true, 0.0),
            ArbiterOutput::None
        );
        assert_eq!(
            arbiter.update(0.5, vec![f.clone()], true, 0.0),
            ArbiterOutput::Hint(f.clone())
        );

        // Ignored for 5.0s (0.5 -> 5.6) -> snoozed
        assert_eq!(
            arbiter.update(5.6, vec![f.clone()], true, 0.0),
            ArbiterOutput::None
        );

        // With snoozed finding filtered out, good_hold (0.6s) leads to Good at t = 6.3
        assert_eq!(
            arbiter.update(6.3, vec![f.clone()], true, 0.0),
            ArbiterOutput::Good
        );
    }

    #[test]
    fn test_arbiter_motion_mute() {
        let mut arbiter = HintArbiter::default();
        let f = sample_finding("crop.head", Severity::Critical);
        assert_eq!(
            arbiter.update(1.0, vec![f], true, 1.5),
            ArbiterOutput::Silent
        );
    }
}
