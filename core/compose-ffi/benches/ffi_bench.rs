use compose_core::{
    CameraIntrinsics, Facing, Frame, Joint, JointType, LightContext, LightDirection, LightQuality,
    MaskSummary, NormalizedPoint, NormalizedRect, Posture, ShotType, Subject,
};
use compose_ffi::LiveEngine;
use std::collections::HashMap;
use std::env;
use std::time::Instant;

fn build_mock_frame_json(t: f64) -> String {
    let mut joints = HashMap::new();
    let keypoints = [
        (JointType::Nose, 0.50, 0.18),
        (JointType::LeftEye, 0.48, 0.16),
        (JointType::RightEye, 0.52, 0.16),
        (JointType::LeftEar, 0.45, 0.17),
        (JointType::RightEar, 0.55, 0.17),
        (JointType::LeftShoulder, 0.42, 0.28),
        (JointType::RightShoulder, 0.58, 0.28),
        (JointType::LeftElbow, 0.38, 0.42),
        (JointType::RightElbow, 0.62, 0.42),
        (JointType::LeftWrist, 0.35, 0.55),
        (JointType::RightWrist, 0.65, 0.55),
        (JointType::LeftHip, 0.44, 0.52),
        (JointType::RightHip, 0.56, 0.52),
        (JointType::LeftKnee, 0.45, 0.72),
        (JointType::RightKnee, 0.55, 0.72),
        (JointType::LeftAnkle, 0.46, 0.90),
        (JointType::RightAnkle, 0.54, 0.90),
    ];

    for (jt, x, y) in keypoints {
        joints.insert(jt, Joint::new(jt, NormalizedPoint::new(x, y), 0.95));
    }

    let subject = Subject::new(1, NormalizedRect::new(0.35, 0.12, 0.30, 0.80))
        .with_facing(Facing::Frontal)
        .with_shot_type(ShotType::FullBody)
        .with_joints(joints)
        .with_mask(MaskSummary::new(
            0.12,
            0.92,
            (0.44, 0.56),
            (0.38, 0.62),
            (0.42, 0.58),
        ));

    let frame = Frame::new(t, Posture::new(1.8, -3.2))
        .with_intrinsics(CameraIntrinsics::new(26.0, 68.0))
        .with_subjects(vec![subject]);

    serde_json::to_string(&frame).expect("serialize mock frame")
}

fn build_mock_light_json() -> String {
    let light = LightContext::new(
        LightDirection::Front,
        LightQuality::Soft,
        Some(1.2),
        12.5,
        0.85,
    );
    serde_json::to_string(&light).expect("serialize mock light")
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let is_test = args.iter().any(|a| a == "--test");

    let iterations = if is_test { 1_000 } else { 10_000 };
    let warmup = if is_test { 100 } else { 1_000 };

    let engine = LiveEngine::new("{\"version\": \"1.0\"}".to_string(), "vision".to_string())
        .expect("instantiate LiveEngine");

    let light_json = build_mock_light_json();
    let frame_json = build_mock_frame_json(100.0);

    // Warmup
    for _ in 0..warmup {
        let output = engine
            .step_json(frame_json.clone(), Some(light_json.clone()), 100.0)
            .expect("step_json succeeds");
        std::hint::black_box(output);
    }

    // Benchmark loop
    let mut durations_ns = Vec::with_capacity(iterations);
    let total_start = Instant::now();

    for i in 0..iterations {
        let t = 100.0 + (i as f64) * 0.016;

        let iter_start = Instant::now();
        let output = engine
            .step_json(frame_json.clone(), Some(light_json.clone()), t)
            .expect("step_json succeeds");
        let elapsed = iter_start.elapsed();

        std::hint::black_box(output);
        durations_ns.push(elapsed.as_nanos() as f64);
    }

    let total_elapsed = total_start.elapsed();
    durations_ns.sort_by(|a, b| a.partial_cmp(b).unwrap());

    let count = durations_ns.len() as f64;
    let sum_ns: f64 = durations_ns.iter().sum();
    let mean_us = (sum_ns / count) / 1_000.0;
    let min_us = durations_ns.first().unwrap() / 1_000.0;
    let max_us = durations_ns.last().unwrap() / 1_000.0;
    let p50_us = durations_ns[(count * 0.50) as usize] / 1_000.0;
    let p90_us = durations_ns[(count * 0.90) as usize] / 1_000.0;
    let p99_us = durations_ns[(count * 0.99) as usize] / 1_000.0;

    println!("===============================================================");
    println!(" [compose-ffi] LiveEngine FFI Microbenchmark (Spike #22/R9) Results");
    println!("===============================================================");
    println!(
        " Mode:           {}",
        if is_test {
            "Test / Smoke"
        } else {
            "Full Benchmark"
        }
    );
    println!(" Iterations:     {}", iterations);
    println!(" Total Time:     {:.2?}", total_elapsed);
    println!(" Latency Metrics (JSON Deser + Rules Engine + UniFFI Return):");
    println!("   - Min:        {:8.3} μs", min_us);
    println!("   - Mean:       {:8.3} μs", mean_us);
    println!("   - P50:        {:8.3} μs", p50_us);
    println!("   - P90:        {:8.3} μs", p90_us);
    println!("   - P99:        {:8.3} μs", p99_us);
    println!("   - Max:        {:8.3} μs", max_us);
    println!(" Target Budget:  1000.000 μs (1.0 ms) per frame; 60fps frame interval is 16666.7 μs");
    println!("===============================================================");

    // Even with full JSON deserialization per frame, verify it is under 1.0 ms (1000 μs)
    assert!(
        mean_us < 1000.0,
        "FFI step_json latency too high! Mean was {:.3} μs (expected < 1000.0 μs)",
        mean_us
    );
    println!(
        "PASS: FFI microbenchmark passed with mean latency {:.3} μs!",
        mean_us
    );
}
