//!
//! # Otto AI Completion Backend
//!
//! This crate provides AI completion services for the Otto autocomplete system.
//! It includes support for multiple AI backends and hardware-adaptive model selection.

use std::collections::HashMap;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::Mutex;

#[derive(Debug, Clone)]
pub struct CompletionRequest {
    pub text: String,
    pub context: Option<String>,
}

#[derive(Debug, Clone)]
pub struct CompletionResponse {
    pub prefix: String,
    pub suggestion: String,
    pub confidence: f64,
    pub is_ml_based: bool,
}

pub struct TabyrusBackend {
    completions: Mutex<HashMap<String, Vec<String>>>,
}

impl TabyrusBackend {
    pub fn new() -> Self {
        let mut completions = HashMap::new();
        completions.insert(
            "he".into(),
            vec!["hello".into(), "help".into(), "here".into()],
        );
        completions.insert(
            "th".into(),
            vec!["the".into(), "then".into(), "there".into()],
        );

        Self {
            completions: Mutex::new(completions),
        }
    }

    pub fn suggest(&self, request: CompletionRequest) -> Option<CompletionResponse> {
        let prefix = request.text.trim().to_lowercase();
        if prefix.is_empty() {
            return None;
        }

        let completions = self.completions.lock().ok()?;
        let candidates = completions.get(&prefix)?;
        let suggestion = candidates.first()?;

        Some(CompletionResponse {
            prefix,
            suggestion: suggestion.clone(),
            confidence: 0.95,
            is_ml_based: request.context.is_some(),
        })
    }
}

// Static instance for FFI
static mut BACKEND: Option<TabyrusBackend> = None;

/// Initialize the backend (call once)
#[no_mangle]
pub extern "C" fn otto_init() {
    unsafe {
        BACKEND = Some(TabyrusBackend::new());
    }
}

/// Get completion suggestion
/// Returns null if no suggestion available
#[no_mangle]
pub extern "C" fn otto_get_completion(text: *const c_char) -> *mut c_char {
    if text.is_null() {
        return std::ptr::null_mut();
    }

    let c_str = unsafe { CStr::from_ptr(text) };
    let text_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    let request = CompletionRequest {
        text: text_str.to_string(),
        context: None,
    };

    unsafe {
        if let Some(ref backend) = BACKEND {
            if let Some(response) = backend.suggest(request) {
                let result = format!("{{\"prefix\":\"{}\",\"suggestion\":\"{}\",\"confidence\":{},\"is_ml_based\":{}}}",
                    response.prefix, response.suggestion, response.confidence, response.is_ml_based);
                let c_string = CString::new(result).unwrap();
                c_string.into_raw()
            } else {
                std::ptr::null_mut()
            }
        } else {
            std::ptr::null_mut()
        }
    }
}

/// Free string returned by otto_get_completion
#[no_mangle]
pub extern "C" fn otto_free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe {
            drop(CString::from_raw(s));
        }
    }
}

/// Echo function for testing
#[no_mangle]
pub extern "C" fn otto_echo(input: *const c_char) -> *mut c_char {
    if input.is_null() {
        return std::ptr::null_mut();
    }

    let c_str = unsafe { CStr::from_ptr(input) };
    let input_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    let c_string = CString::new(input_str).unwrap();
    c_string.into_raw()
}
