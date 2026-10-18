use super::subject::Subject;
use serde::{Deserialize, Serialize};

/// Real-time IMU posture of the camera device.
#[derive(Debug, Default, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct Posture {
    #[serde(default)]
    pub roll_deg: f32, // 左右歪斜角：正数表示顺时针歪斜
    #[serde(default)]
    pub pitch_deg: f32, // 俯仰角：正数表示仰角，负数表示俯角
    #[serde(default)]
    pub elevation_deg: f32, // 地平线高度夹角
    #[serde(default)]
    pub angular_speed: f32, // 角速度 (rad/s)，用于快速晃动时静默提示
    #[serde(default)]
    pub is_flatish: bool, // |g.z| > 0.8，平放俯拍/仰拍时 roll 不可靠
}

impl Posture {
    pub const ZERO: Self = Self {
        roll_deg: 0.0,
        pitch_deg: 0.0,
        elevation_deg: 0.0,
        angular_speed: 0.0,
        is_flatish: false,
    };

    pub fn new(roll_deg: f32, pitch_deg: f32) -> Self {
        Self {
            roll_deg,
            pitch_deg,
            elevation_deg: pitch_deg,
            angular_speed: 0.0,
            is_flatish: false,
        }
    }

    pub fn with_motion(mut self, angular_speed: f32, is_flatish: bool) -> Self {
        self.angular_speed = angular_speed;
        self.is_flatish = is_flatish;
        self
    }
}

/// Optical characteristics of current camera lens.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct CameraIntrinsics {
    pub focal_length_mm: f32, // 等效 35mm 焦距
    pub hfov_deg: f32,        // 水平视场角
}

impl CameraIntrinsics {
    pub fn new(focal_length_mm: f32, hfov_deg: f32) -> Self {
        Self {
            focal_length_mm,
            hfov_deg,
        }
    }

    pub fn default_main_lens() -> Self {
        Self {
            focal_length_mm: 24.0,
            hfov_deg: 73.7,
        }
    }
}

impl Default for CameraIntrinsics {
    fn default() -> Self {
        Self::default_main_lens()
    }
}

/// Camera sensor exposure metrics.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct ExposureSummary {
    pub iso: f32,
    pub shutter_speed_sec: f32,
    pub ev: f32,
}

impl ExposureSummary {
    pub fn daylight() -> Self {
        Self {
            iso: 100.0,
            shutter_speed_sec: 1.0 / 500.0,
            ev: 12.0,
        }
    }
}

impl Default for ExposureSummary {
    fn default() -> Self {
        Self::daylight()
    }
}

/// A complete frame analyzed by the perception pipeline.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Frame {
    pub t: f64,
    #[serde(default)]
    pub subjects: Vec<Subject>,
    #[serde(default)]
    pub primary_subject_index: Option<usize>,
    pub posture: Posture,
    #[serde(default)]
    pub camera: CameraIntrinsics,
    #[serde(default)]
    pub exposure: ExposureSummary,
}

impl Frame {
    pub fn new(t: f64, posture: Posture) -> Self {
        Self {
            t,
            subjects: Vec::new(),
            primary_subject_index: None,
            posture,
            camera: CameraIntrinsics::default_main_lens(),
            exposure: ExposureSummary::daylight(),
        }
    }

    pub fn with_subjects(mut self, subjects: Vec<Subject>) -> Self {
        if !subjects.is_empty() {
            self.primary_subject_index = Some(0);
        }
        self.subjects = subjects;
        self
    }

    pub fn with_intrinsics(mut self, camera: CameraIntrinsics) -> Self {
        self.camera = camera;
        self
    }

    pub fn primary_subject(&self) -> Option<&Subject> {
        self.primary_subject_index
            .and_then(|idx| self.subjects.get(idx))
            .or_else(|| self.subjects.first())
    }
}
