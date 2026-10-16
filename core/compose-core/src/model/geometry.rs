use serde::{Deserialize, Serialize};

/// A 2D point with normalized coordinates in range [0.0, 1.0].
/// (0.0, 0.0) is top-left, (1.0, 1.0) is bottom-right.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct NormalizedPoint {
    pub x: f32,
    pub y: f32,
}

impl NormalizedPoint {
    pub const ZERO: Self = Self { x: 0.0, y: 0.0 };

    pub fn new(x: f32, y: f32) -> Self {
        Self { x, y }
    }

    pub fn distance_to(&self, other: &Self) -> f32 {
        let dx = self.x - other.x;
        let dy = self.y - other.y;
        (dx * dx + dy * dy).sqrt()
    }

    pub fn clamp(&self) -> Self {
        Self {
            x: self.x.clamp(0.0, 1.0),
            y: self.y.clamp(0.0, 1.0),
        }
    }
}

/// A 2D bounding box with normalized coordinates in range [0.0, 1.0].
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct NormalizedRect {
    pub x: f32,
    pub y: f32,
    pub width: f32,
    pub height: f32,
}

impl NormalizedRect {
    pub const ZERO: Self = Self {
        x: 0.0,
        y: 0.0,
        width: 0.0,
        height: 0.0,
    };

    pub fn new(x: f32, y: f32, width: f32, height: f32) -> Self {
        Self {
            x,
            y,
            width: width.max(0.0),
            height: height.max(0.0),
        }
    }

    pub fn min_x(&self) -> f32 {
        self.x
    }

    pub fn max_x(&self) -> f32 {
        self.x + self.width
    }

    pub fn min_y(&self) -> f32 {
        self.y
    }

    pub fn max_y(&self) -> f32 {
        self.y + self.height
    }

    pub fn center(&self) -> NormalizedPoint {
        NormalizedPoint {
            x: self.x + self.width * 0.5,
            y: self.y + self.height * 0.5,
        }
    }

    pub fn area(&self) -> f32 {
        self.width * self.height
    }

    pub fn contains_point(&self, p: &NormalizedPoint) -> bool {
        p.x >= self.min_x() && p.x <= self.max_x() && p.y >= self.min_y() && p.y <= self.max_y()
    }

    pub fn intersection(&self, other: &Self) -> Option<Self> {
        let x1 = self.min_x().max(other.min_x());
        let y1 = self.min_y().max(other.min_y());
        let x2 = self.max_x().min(other.max_x());
        let y2 = self.max_y().min(other.max_y());

        if x2 > x1 && y2 > y1 {
            Some(Self::new(x1, y1, x2 - x1, y2 - y1))
        } else {
            None
        }
    }

    pub fn iou(&self, other: &Self) -> f32 {
        let inter_area = self.intersection(other).map(|r| r.area()).unwrap_or(0.0);
        let union_area = self.area() + other.area() - inter_area;
        if union_area <= 1e-6 {
            0.0
        } else {
            inter_area / union_area
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_normalized_rect_math() {
        let r1 = NormalizedRect::new(0.1, 0.1, 0.4, 0.4);
        let r2 = NormalizedRect::new(0.3, 0.3, 0.4, 0.4);

        assert_eq!(r1.center(), NormalizedPoint::new(0.3, 0.3));
        assert!((r1.area() - 0.16).abs() < 1e-6);

        let inter = r1.intersection(&r2).expect("should intersect");
        assert!((inter.area() - 0.04).abs() < 1e-6);

        // Union = 0.16 + 0.16 - 0.04 = 0.28. IoU = 0.04 / 0.28 = 1/7 ≈ 0.142857
        let iou = r1.iou(&r2);
        assert!((iou - (1.0 / 7.0)).abs() < 1e-5);
    }
}
