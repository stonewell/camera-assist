use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Localized prompt strings for a specific finding action or condition.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HintItem {
    pub primary: String,
    pub secondary: String,
    pub spoken: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct HintFileWrapper {
    #[serde(default)]
    pub version: u32,
    pub hints: HashMap<String, HintItem>,
}

const BUILTIN_ZH_HANS_JSON: &str = include_str!("../../../shared/hints/zh-Hans.json");
const BUILTIN_EN_JSON: &str = include_str!("../../../shared/hints/en.json");

/// Catalog of hints for a single language.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct HintCatalog {
    pub hints: HashMap<String, HintItem>,
}

impl Default for HintCatalog {
    fn default() -> Self {
        Self::builtin_zh_hans()
    }
}

impl HintCatalog {
    pub fn new() -> Self {
        Self {
            hints: HashMap::new(),
        }
    }

    pub fn builtin_zh_hans() -> Self {
        Self::from_json_str(BUILTIN_ZH_HANS_JSON).expect("builtin zh-Hans hints must be valid JSON")
    }

    pub fn builtin_en() -> Self {
        Self::from_json_str(BUILTIN_EN_JSON).expect("builtin en hints must be valid JSON")
    }

    pub fn for_locale(locale: &str) -> Self {
        let clean = locale.trim().to_ascii_lowercase();
        if clean.starts_with("en") {
            Self::builtin_en()
        } else {
            Self::builtin_zh_hans()
        }
    }

    pub fn from_json_str(json_str: &str) -> Result<Self, serde_json::Error> {
        let wrapper: HintFileWrapper = serde_json::from_str(json_str)?;
        Ok(Self {
            hints: wrapper.hints,
        })
    }

    pub fn get(&self, hint_key: &str) -> Option<&HintItem> {
        self.hints.get(hint_key)
    }

    pub fn primary_text<'a>(&'a self, hint_key: &'a str) -> &'a str {
        self.hints
            .get(hint_key)
            .map(|h| h.primary.as_str())
            .unwrap_or(hint_key)
    }

    pub fn resolve(&self, hint_key: &str) -> HintItem {
        if let Some(item) = self.hints.get(hint_key) {
            item.clone()
        } else {
            HintItem {
                primary: hint_key.to_string(),
                secondary: String::new(),
                spoken: hint_key.to_string(),
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_builtin_and_for_locale() {
        let zh = HintCatalog::builtin_zh_hans();
        assert!(zh.get("good").is_some());
        assert_eq!(zh.resolve("good").primary, "构图不错，可以拍");

        let en = HintCatalog::builtin_en();
        assert!(en.get("good").is_some());
        assert_eq!(
            en.resolve("good").primary,
            "Great composition, take the shot"
        );

        let zh_loc = HintCatalog::for_locale("zh-CN");
        assert_eq!(zh_loc.resolve("good").primary, "构图不错，可以拍");

        let en_loc = HintCatalog::for_locale("en_US");
        assert_eq!(
            en_loc.resolve("good").primary,
            "Great composition, take the shot"
        );

        let default_cat = HintCatalog::default();
        assert_eq!(default_cat.resolve("good").primary, "构图不错，可以拍");
    }

    #[test]
    fn test_resolve_fallback() {
        let cat = HintCatalog::new();
        let fallback = cat.resolve("unknown_rule_key");
        assert_eq!(fallback.primary, "unknown_rule_key");
        assert_eq!(fallback.secondary, "");
        assert_eq!(fallback.spoken, "unknown_rule_key");
    }
}
