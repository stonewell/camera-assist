use compose_core::{
    CameraIntrinsics, Facing, Frame, Joint, JointType, NormalizedPoint, NormalizedRect, Posture,
    RulesEngine, ShotType, Subject,
};
use std::collections::HashMap;
use std::env;
use std::time::Instant;

fn generate_batch(count: usize) -> Vec<Frame> {
    let mut frames = Vec::with_capacity(count);

    for i in 0..count {
        let t = (i as f64) * 0.1;
        let roll = ((i % 11) as f32) - 5.0; // -5 to +5 deg
        let pitch = ((i % 15) as f32) - 7.0; // -7 to +7 deg

        let center_x = 0.35 + ((i % 7) as f32) * 0.05; // 0.35 to 0.65
        let shot_type = match i % 3 {
            0 => ShotType::HalfBody,
            1 => ShotType::FullBody,
            _ => ShotType::CloseUp,
        };

        let mut joints = HashMap::new();
        joints.insert(
            JointType::Nose,
            Joint::new(JointType::Nose, NormalizedPoint::new(center_x, 0.20), 0.95),
        );
        joints.insert(
            JointType::LeftWrist,
            Joint::new(
                JointType::LeftWrist,
                NormalizedPoint::new(center_x - 0.15, 0.50),
                0.90,
            ),
        );

        let subject = Subject::new(1, NormalizedRect::new(center_x - 0.15, 0.10, 0.30, 0.75))
            .with_facing(Facing::Frontal)
            .with_shot_type(shot_type)
            .with_joints(joints);

        let frame = Frame::new(t, Posture::new(roll, pitch))
            .with_intrinsics(CameraIntrinsics::default_main_lens())
            .with_subjects(vec![subject]);

        frames.push(frame);
    }

    frames
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let is_test = args.iter().any(|a| a == "--test");

    let batch_size = if is_test { 1_000 } else { 10_000 };
    let engine = RulesEngine::default_engine();

    println!("===============================================================");
    println!(" [compose-core] Desktop Photo Batch Evaluation Benchmark (Spike R2)");
    println!("===============================================================");
    println!(
        " Mode:           {}",
        if is_test {
            "Test / Smoke"
        } else {
            "Full Benchmark"
        }
    );
    println!(" Batch Size:     {} photos", batch_size);

    let batch = generate_batch(batch_size);

    // Warmup
    for f in &batch[0..100] {
        let findings = engine.evaluate(f, None);
        std::hint::black_box(findings);
    }

    let start = Instant::now();
    let mut total_findings = 0;

    for frame in &batch {
        let findings = engine.evaluate(frame, None);
        total_findings += findings.len();
        std::hint::black_box(findings);
    }

    let elapsed = start.elapsed();
    let seconds = elapsed.as_secs_f64();
    let throughput_fps = (batch_size as f64) / seconds;
    let avg_ms_per_photo = (seconds * 1_000.0) / (batch_size as f64);

    println!(" Total Time:     {:.3?}", elapsed);
    println!(" Total Findings: {}", total_findings);
    println!(" Throughput:     {:10.1} photos/sec (FPS)", throughput_fps);
    println!(" Avg Latency:    {:10.4} ms/photo", avg_ms_per_photo);
    println!(" SLA Target:     >= 100.0 FPS (1,000 photos analyzed under 10 seconds)");
    println!("===============================================================");

    assert!(
        throughput_fps >= 100.0,
        "Throughput {:.1} FPS below SLA minimum of 100.0 FPS",
        throughput_fps
    );
    println!(
        "PASS: Desktop batch analysis achieved {:.1} FPS (SLA exceeded by {:.1}x)!",
        throughput_fps,
        throughput_fps / 100.0
    );
}
