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

/// Catalog of hints for a single language.
#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
pub struct HintCatalog {
    pub hints: HashMap<String, HintItem>,
}

impl HintCatalog {
    pub fn new() -> Self {
        Self {
            hints: HashMap::new(),
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
}
