#![forbid(unsafe_code)]

use compose_eval::{evaluate_golden_dir, EvalSummary};
use std::env;
use std::path::{Path, PathBuf};
use std::process::exit;

fn print_help() {
    println!(
        "Usage: compose-eval [OPTIONS]\n\n\
        Options:\n  \
          --self-test         Run full 20-vector golden test suite with self-test verification\n  \
          --golden-dir <DIR>  Path to golden vectors directory (default: fixtures/golden)\n  \
          --json              Output evaluation summary as JSON\n  \
          --help, -h          Print this help message"
    );
}

fn find_golden_dir(override_path: Option<&str>) -> PathBuf {
    if let Some(p) = override_path {
        return PathBuf::from(p);
    }

    let candidates = [
        PathBuf::from("fixtures/golden"),
        PathBuf::from("../fixtures/golden"),
        PathBuf::from("../../fixtures/golden"),
    ];

    for c in &candidates {
        if c.is_dir() {
            return c.clone();
        }
    }

    // Try relative to current exe
    if let Ok(exe) = env::current_exe() {
        if let Some(parent) = exe.parent() {
            let p = parent.join("../../fixtures/golden");
            if p.is_dir() {
                return p;
            }
        }
    }

    PathBuf::from("fixtures/golden")
}

fn print_table_summary(summary: &EvalSummary, golden_dir: &Path) {
    println!("==================================================================");
    println!(" Camera Assist: Offline Composition Rule & Review Evaluation");
    println!(" Golden Fixtures: {}", golden_dir.display());
    println!("==================================================================");
    println!(
        "{:<28} {:<8} {:<7} {:<8} {:<12}",
        "Vector ID", "Match", "Score", "Latency", "Fixes Count"
    );
    println!("------------------------------------------------------------------");

    for r in &summary.results {
        let match_str = if r.is_exact_match {
            "EXACT"
        } else {
            "MISMATCH"
        };
        println!(
            "{:<28} {:<8} {:<7} {:<6} µs {:<12}",
            r.vector_id, match_str, r.review_score, r.latency_us, r.suggested_fixes_count
        );
    }

    println!("------------------------------------------------------------------");
    println!(
        "Total: {} | Exact: {} ({:.1}%) | Precision: {:.1}% | Recall: {:.1}% | Mean Latency: {:.1} µs",
        summary.total_vectors,
        summary.exact_matches,
        summary.exact_match_rate * 100.0,
        summary.precision * 100.0,
        summary.recall * 100.0,
        summary.mean_latency_us
    );
    println!("==================================================================");
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let mut is_self_test = false;
    let mut output_json = false;
    let mut golden_dir_arg: Option<String> = None;

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--self-test" => is_self_test = true,
            "--json" => output_json = true,
            "--golden-dir" => {
                if i + 1 < args.len() {
                    golden_dir_arg = Some(args[i + 1].clone());
                    i += 1;
                }
            }
            "--help" | "-h" => {
                print_help();
                return;
            }
            _ => {}
        }
        i += 1;
    }

    let golden_dir = find_golden_dir(golden_dir_arg.as_deref());
    let summary = match evaluate_golden_dir(&golden_dir) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("[ERROR] Evaluation failed: {}", e);
            exit(1);
        }
    };

    if output_json {
        match serde_json::to_string_pretty(&summary) {
            Ok(j) => println!("{}", j),
            Err(e) => {
                eprintln!("[ERROR] JSON serialization failed: {}", e);
                exit(1);
            }
        }
    } else {
        print_table_summary(&summary, &golden_dir);
    }

    if is_self_test {
        if summary.total_vectors != 20 {
            eprintln!(
                "[FAIL] Self-test expected 20 vectors, found {}",
                summary.total_vectors
            );
            exit(1);
        }
        if summary.exact_matches != 20 || (summary.exact_match_rate - 1.0).abs() > 1e-4 {
            eprintln!(
                "[FAIL] Self-test expected 100% exact match, got {:.1}%",
                summary.exact_match_rate * 100.0
            );
            exit(1);
        }
        println!("[SUCCESS] Self-test passed: 20/20 golden vectors matched exact finding sets.");
    }
}
