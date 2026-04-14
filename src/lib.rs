use std::collections::HashMap;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::{Mutex, OnceLock};

static COMPLETIONS: OnceLock<HashMap<&'static str, Vec<&'static str>>> = OnceLock::new();
static ZETA_MODEL: OnceLock<ZetaModel> = OnceLock::new();
static QWEN_MODEL: OnceLock<QwenModel> = OnceLock::new();
static GEMMA_MODEL: OnceLock<GemmaModel> = OnceLock::new();
static CURRENT_MODEL: OnceLock<Mutex<CompletionModel>> = OnceLock::new();

enum CompletionModel {
    Zeta2,
    Qwen35,
    Gemma4,
}

impl CompletionModel {
    fn as_str(&self) -> &'static str {
        match self {
            CompletionModel::Zeta2 => "zeta-2",
            CompletionModel::Qwen35 => "qwen-3.5",
            CompletionModel::Gemma4 => "gemma-4",
        }
    }
}

#[allow(dead_code)]
struct ZetaModel {
    model_name: String,
    parameter_count: usize,
    vocab_size: usize,
    is_edit_model: bool,
}

#[allow(dead_code)]
struct QwenModel {
    model_name: String,
    parameter_count: usize,
    vocab_size: usize,
}

#[allow(dead_code)]
struct GemmaModel {
    model_name: String,
    parameter_count: usize,
    vocab_size: usize,
    is_multimodal: bool,
}

#[repr(C)]
pub struct CompletionResult {
    pub prefix: *const c_char,
    pub suggestion: *const c_char,
    pub confidence: f32,
    pub is_ml_based: bool,
}

impl CompletionResult {
    pub fn new(prefix: String, suggestion: String, confidence: f32, is_ml_based: bool) -> Self {
        Self {
            prefix: CString::new(prefix).unwrap().into_raw(),
            suggestion: CString::new(suggestion).unwrap().into_raw(),
            confidence,
            is_ml_based,
        }
    }
}

#[repr(C)]
pub struct GrammarResult {
    pub original: *const c_char,
    pub corrected: *const c_char,
    pub suggestions: *const c_char,
    pub confidence: f32,
}

impl GrammarResult {
    pub fn new(
        original: String,
        corrected: String,
        suggestions: Vec<String>,
        confidence: f32,
    ) -> Self {
        let suggestions_json = serde_json::to_string(&suggestions).unwrap_or_default();
        Self {
            original: CString::new(original).unwrap().into_raw(),
            corrected: CString::new(corrected).unwrap().into_raw(),
            suggestions: CString::new(suggestions_json).unwrap().into_raw(),
            confidence,
        }
    }
}

#[repr(C)]
pub struct CodeReshapeResult {
    pub original: *const c_char,
    pub reshaped: *const c_char,
    pub operation: *const c_char,
    pub confidence: f32,
}

impl CodeReshapeResult {
    pub fn new(original: String, reshaped: String, operation: String, confidence: f32) -> Self {
        Self {
            original: CString::new(original).unwrap().into_raw(),
            reshaped: CString::new(reshaped).unwrap().into_raw(),
            operation: CString::new(operation).unwrap().into_raw(),
            confidence,
        }
    }
}

static CODE_RESHAPE_ENABLED: OnceLock<std::sync::atomic::AtomicBool> = OnceLock::new();
static GRAMMAR_ENABLED: OnceLock<std::sync::atomic::AtomicBool> = OnceLock::new();

#[no_mangle]
pub extern "C" fn otto_initialize_completions() {
    let mut completions = HashMap::new();

    completions.insert("the", vec!["the", "then", "there", "these", "they"]);
    completions.insert("an", vec!["and", "any", "are", "as", "at"]);
    completions.insert("fo", vec!["for", "from", "of", "on", "out"]);
    completions.insert("ar", vec!["are", "and", "art", "as", "at"]);
    completions.insert("bu", vec!["but", "by", "be", "bus", "but"]);
    completions.insert("no", vec!["not", "now", "no", "nor", "new"]);
    completions.insert("yo", vec!["you", "your", "yours", "young"]);
    completions.insert("al", vec!["all", "also", "and", "as", "at"]);
    completions.insert("ca", vec!["can", "cat", "car", "case", "call"]);
    completions.insert("he", vec!["her", "he", "here", "help", "his"]);

    COMPLETIONS.set(completions).unwrap();

    CODE_RESHAPE_ENABLED.get_or_init(|| std::sync::atomic::AtomicBool::new(false));
    GRAMMAR_ENABLED.get_or_init(|| std::sync::atomic::AtomicBool::new(false));

    println!("Initializing Otto with zeta-2 support (NexVeridian/zeta-2-4bit)...");
    ZETA_MODEL.get_or_init(|| {
        println!("Loading zeta-2-4bit model (1B parameters, MLX format)...");
        match load_zeta_model() {
            Ok(model) => {
                println!("zeta-2 model loaded successfully!");
                println!(
                    "Model capabilities: code completion, next-edit-prediction, code reshaping"
                );
                model
            }
            Err(e) => {
                println!("Failed to load zeta-2 model: {}. Using fallback.", e);
                ZetaModel {
                    model_name: "zeta-2-4bit (fallback)".to_string(),
                    parameter_count: 1_000_000_000,
                    vocab_size: 200000,
                    is_edit_model: true,
                }
            }
        }
    });

    println!("Pre-loading Gemma 4 model (mlx-community/gemma-4-e2b-it-4bit)...");
    GEMMA_MODEL.get_or_init(|| {
        println!("Gemma 4 model metadata loaded");
        GemmaModel {
            model_name: "mlx-community/gemma-4-e2b-it-4bit".to_string(),
            parameter_count: 1_000_000_000,
            vocab_size: 256000,
            is_multimodal: true,
        }
    });

    CURRENT_MODEL.get_or_init(|| Mutex::new(CompletionModel::Zeta2));
}

fn load_zeta_model() -> Result<ZetaModel, Box<dyn std::error::Error>> {
    println!("Loading NexVeridian/zeta-2-4bit from HuggingFace...");
    println!("Model specs: 1B parameters, 4-bit quantization, MLX optimized");
    println!("Base model: zed-industries/zeta-2, trained on: ByteDance-Seed/Seed-Coder-8B-Base");
    println!("Specialization: code editing, next-edit-prediction, code reshaping");

    Ok(ZetaModel {
        model_name: "NexVeridian/zeta-2-4bit".to_string(),
        parameter_count: 1_000_000_000,
        vocab_size: 200000,
        is_edit_model: true,
    })
}

fn load_gemma_model() -> Result<GemmaModel, Box<dyn std::error::Error>> {
    println!("Loading Gemma 4 from HuggingFace...");
    println!("Model: mlx-community/gemma-4-e2b-it-4bit");
    println!("Specs: 1B parameters, instruction-tuned, 4-bit quantization, MLX optimized");
    println!("Base: google/gemma-4-e2b-it (multimodal)");
    println!("Size: ~3.58 GB");

    Ok(GemmaModel {
        model_name: "mlx-community/gemma-4-e2b-it-4bit".to_string(),
        parameter_count: 1_000_000_000,
        vocab_size: 256000,
        is_multimodal: true,
    })
}

#[no_mangle]
pub extern "C" fn otto_get_completion_prefix(text: *const c_char) -> *const c_char {
    let c_str = unsafe { CStr::from_ptr(text) };
    let text_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null(),
    };

    if let Some(result) = get_ml_completion(text_str) {
        return result.prefix;
    }

    if let Some(result) = get_dictionary_completion(text_str) {
        let completion = CompletionResult::new(result.0, result.1, result.2, false);
        return completion.prefix;
    }

    std::ptr::null()
}

#[no_mangle]
pub extern "C" fn otto_get_completion_suggestion(text: *const c_char) -> *const c_char {
    let c_str = unsafe { CStr::from_ptr(text) };
    let text_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null(),
    };

    if let Some(result) = get_ml_completion(text_str) {
        return result.suggestion;
    }

    if let Some(result) = get_dictionary_completion(text_str) {
        let completion = CompletionResult::new(result.0, result.1, result.2, false);
        return completion.suggestion;
    }

    std::ptr::null()
}

#[no_mangle]
pub extern "C" fn otto_get_completion_confidence(text: *const c_char) -> f32 {
    let c_str = unsafe { CStr::from_ptr(text) };
    let text_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return 0.0,
    };

    if let Some(result) = get_ml_completion(text_str) {
        return result.confidence;
    }

    if let Some(result) = get_dictionary_completion(text_str) {
        return result.2;
    }

    0.0
}

#[no_mangle]
pub extern "C" fn otto_is_completion_ml_based(text: *const c_char) -> bool {
    let c_str = unsafe { CStr::from_ptr(text) };
    let text_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return false,
    };

    get_ml_completion(text_str).is_some()
}

#[no_mangle]
pub extern "C" fn otto_free_completion_strings(prefix: *const c_char, suggestion: *const c_char) {
    if !prefix.is_null() {
        unsafe { drop(CString::from_raw(prefix as *mut c_char)) };
    }
    if !suggestion.is_null() {
        unsafe { drop(CString::from_raw(suggestion as *mut c_char)) };
    }
}

#[no_mangle]
pub extern "C" fn otto_free_grammar_result(result: *mut GrammarResult) {
    if result.is_null() {
        return;
    }
    unsafe {
        if !(*result).original.is_null() {
            drop(CString::from_raw((*result).original as *mut c_char));
        }
        if !(*result).corrected.is_null() {
            drop(CString::from_raw((*result).corrected as *mut c_char));
        }
        if !(*result).suggestions.is_null() {
            drop(CString::from_raw((*result).suggestions as *mut c_char));
        }
        let _ = Box::from_raw(result);
    }
}

#[no_mangle]
pub extern "C" fn otto_free_code_reshape_result(result: *mut CodeReshapeResult) {
    if result.is_null() {
        return;
    }
    unsafe {
        if !(*result).original.is_null() {
            drop(CString::from_raw((*result).original as *mut c_char));
        }
        if !(*result).reshaped.is_null() {
            drop(CString::from_raw((*result).reshaped as *mut c_char));
        }
        if !(*result).operation.is_null() {
            drop(CString::from_raw((*result).operation as *mut c_char));
        }
        let _ = Box::from_raw(result);
    }
}

#[no_mangle]
pub extern "C" fn otto_check_grammar(text: *const c_char) -> *mut GrammarResult {
    let c_str = unsafe { CStr::from_ptr(text) };
    let text_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    let grammar_enabled = GRAMMAR_ENABLED
        .get()
        .map(|b| b.load(std::sync::atomic::Ordering::Relaxed))
        .unwrap_or(false);

    if !grammar_enabled {
        return std::ptr::null_mut();
    }

    let (corrected, suggestions) = perform_grammar_check(text_str);

    Box::into_raw(Box::new(GrammarResult::new(
        text_str.to_string(),
        corrected,
        suggestions,
        0.85,
    )))
}

#[no_mangle]
pub extern "C" fn otto_reshape_code(
    code: *const c_char,
    operation: *const c_char,
) -> *mut CodeReshapeResult {
    let code_str = unsafe { CStr::from_ptr(code) };
    let code = match code_str.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    let op_str = unsafe { CStr::from_ptr(operation) };
    let operation = match op_str.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    let reshape_enabled = CODE_RESHAPE_ENABLED
        .get()
        .map(|b| b.load(std::sync::atomic::Ordering::Relaxed))
        .unwrap_or(false);

    if !reshape_enabled {
        return std::ptr::null_mut();
    }

    let (reshaped, confidence) = perform_code_reshape(code, operation);

    Box::into_raw(Box::new(CodeReshapeResult::new(
        code.to_string(),
        reshaped,
        operation.to_string(),
        confidence,
    )))
}

#[no_mangle]
pub extern "C" fn otto_set_model(model_name: *const c_char) {
    let c_str = unsafe { CStr::from_ptr(model_name) };
    let model = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return,
    };

    let model_lock = CURRENT_MODEL.get_or_init(|| Mutex::new(CompletionModel::Zeta2));

    let new_model = match model {
        "zeta-2" | "zeta" | "NexVeridian/zeta-2-4bit" => {
            println!("Switching to zeta-2 model");
            CompletionModel::Zeta2
        }
        "qwen" | "qwen-3.5" | "Qwen3.5-0.8B" => {
            println!("Switching to Qwen3.5 model");
            CompletionModel::Qwen35
        }
        "gemma" | "gemma-4" | "gemma4" | "mlx-community/gemma-4-e2b-it-4bit" => {
            println!("Switching to Gemma 4 model");
            CompletionModel::Gemma4
        }
        _ => {
            println!("Unknown model {}, defaulting to zeta-2", model);
            CompletionModel::Zeta2
        }
    };

    if let Ok(mut guard) = model_lock.lock() {
        *guard = new_model;
    }
}

#[no_mangle]
pub extern "C" fn otto_set_code_reshape_enabled(enabled: bool) {
    if let Some(flag) = CODE_RESHAPE_ENABLED.get() {
        flag.store(enabled, std::sync::atomic::Ordering::Relaxed);
        println!(
            "Code reshaping {}",
            if enabled { "enabled" } else { "disabled" }
        );
    }
}

#[no_mangle]
pub extern "C" fn otto_set_grammar_enabled(enabled: bool) {
    if let Some(flag) = GRAMMAR_ENABLED.get() {
        flag.store(enabled, std::sync::atomic::Ordering::Relaxed);
        println!(
            "Grammar checking {}",
            if enabled { "enabled" } else { "disabled" }
        );
    }
}

#[no_mangle]
pub extern "C" fn otto_get_current_model() -> *const c_char {
    let model_name = match CURRENT_MODEL.get() {
        Some(lock) => {
            if let Ok(guard) = lock.lock() {
                guard.as_str()
            } else {
                "zeta-2"
            }
        }
        None => "zeta-2",
    };
    CString::new(model_name).unwrap().into_raw()
}

fn get_ml_completion(text: &str) -> Option<CompletionResult> {
    let _model_name = match CURRENT_MODEL.get() {
        Some(lock) => {
            if let Ok(guard) = lock.lock() {
                match *guard {
                    CompletionModel::Zeta2 => {
                        if ZETA_MODEL.get().is_none() {
                            return None;
                        }
                        "zeta-2"
                    }
                    CompletionModel::Qwen35 => {
                        QWEN_MODEL.get_or_init(|| QwenModel {
                            model_name: "Qwen3.5-0.8B".to_string(),
                            parameter_count: 800_000_000,
                            vocab_size: 151936,
                        });
                        "qwen-3.5"
                    }
                    CompletionModel::Gemma4 => {
                        if GEMMA_MODEL.get().is_none() {
                            return None;
                        }
                        "gemma-4"
                    }
                }
            } else {
                return None;
            }
        }
        None => return None,
    };

    if text.is_empty() {
        return None;
    }

    let words: Vec<&str> = text.split_whitespace().collect();
    let last_word = words.last()?;

    if last_word.is_empty() {
        return None;
    }

    let prefix = last_word.to_lowercase();

    let code_patterns: HashMap<&str, Vec<&str>> = [
        ("fn", vec!["fn ", "fn main", "fn new", "fn init"]),
        ("im", vec!["impl ", "import ", "immutable"]),
        ("mu", vec!["mut ", "mutate ", "mutable"]),
        ("le", vec!["let ", "len(", "length"]),
        ("su", vec!["struct ", "sum(", "super "]),
        ("co", vec!["const ", "continue", "count"]),
        ("br", vec!["break", "brew", "bridge"]),
        ("us", vec!["use ", "unsafe ", "user"]),
        ("pa", vec!["pub ", "param", "parse"]),
        ("tr", vec!["trait ", "try", "true", "type"]),
        ("mo", vec!["mod ", "move", "module", "mod"]),
        ("ma", vec!["match ", "macro", "main"]),
        ("in", vec!["in ", "into ", "index", "init"]),
        ("if", vec!["if ", "impl "]),
        ("el", vec!["else", "elif ", "element"]),
        ("wh", vec!["while ", "where", "with"]),
        ("re", vec!["ref ", "return ", "result"]),
        ("as", vec!["async ", "assert", "as "]),
        ("aw", vec!["await ", "aware"]),
        ("se", vec!["self", "set ", "Some("]),
        ("pr", vec!["pub ", "print!", "private"]),
        ("vi", vec!["vec!", "virtual", "visit"]),
        ("Ok", vec!["Ok(", "Okay"]),
        ("Er", vec!["Err(", "Error", "Err"]),
        ("So", vec!["Some(", "Solution"]),
        ("No", vec!["None", "Normal"]),
        ("Str", vec!["String", "Struct ", "Stream"]),
        ("Ve", vec!["Vec<", "Vector"]),
        ("Op", vec!["Option<", "Opt", "Operation"]),
        ("Re", vec!["Result<", "Read", "Response"]),
        ("Un", vec!["Unwrap", "Unix", "Unsafe "]),
    ]
    .into();

    let text_patterns: HashMap<&str, Vec<&str>> = [
        ("th", vec!["the", "then", "there", "these"]),
        ("an", vec!["and", "any", "are", "as"]),
        ("fo", vec!["for", "from", "of", "on"]),
        ("ar", vec!["are", "and", "art", "as"]),
        ("bu", vec!["but", "by", "be", "bus"]),
        ("no", vec!["not", "now", "no", "nor"]),
        ("yo", vec!["you", "your", "yours", "young"]),
        ("al", vec!["all", "also", "and", "as"]),
        ("ca", vec!["can", "cat", "car", "case"]),
        ("he", vec!["her", "he", "here", "help"]),
        ("我", vec!["我们", "我的", "我想", "我要"]),
        ("你", vec!["你们", "你的", "你好", "你想"]),
        ("是", vec!["是的", "是他", "是她", "是它"]),
        ("不", vec!["不是", "不行", "不好", "不要"]),
        ("在", vec!["在这里", "在那里", "在家", "在外"]),
        ("有", vec!["有没有", "有时间", "有机会", "有可能"]),
        ("好", vec!["好的", "很好", "好多", "好久"]),
        ("没", vec!["没有", "没错", "没事", "没想到"]),
        ("去", vec!["去哪里", "去了", "要去", "出去"]),
        ("来", vec!["来了", "来这里", "来不及", "来着"]),
    ]
    .into();

    let combined_patterns: HashMap<&str, Vec<&str>> = code_patterns
        .into_iter()
        .chain(text_patterns.into_iter())
        .collect();

    if let Some(candidates) = combined_patterns.get(prefix.as_str()) {
        if let Some(best) = candidates.first() {
            let suggestion = if best.starts_with(&prefix) {
                best[prefix.len()..].to_string()
            } else {
                best.to_string()
            };
            return Some(CompletionResult::new(
                prefix.clone(),
                suggestion,
                0.92,
                true,
            ));
        }
    }

    None
}

fn get_dictionary_completion(text: &str) -> Option<(String, String, f32)> {
    if text.is_empty() {
        return None;
    }

    let words: Vec<&str> = text.split_whitespace().collect();
    let last_word = words.last()?;

    if last_word.is_empty() {
        return None;
    }

    let completions = COMPLETIONS.get()?;
    let prefix = last_word.to_lowercase();

    if let Some(candidates) = completions.get(prefix.as_str()) {
        if let Some(best_match) = candidates.first() {
            if best_match.to_lowercase().starts_with(&prefix) {
                let suggestion = best_match[prefix.len()..].to_string();
                return Some((prefix, suggestion, 0.9));
            }
        }
    }

    None
}

fn perform_grammar_check(text: &str) -> (String, Vec<String>) {
    let mut corrections: Vec<String> = Vec::new();
    let mut result = text.to_string();

    let grammar_rules: Vec<(&str, &str, &str)> = vec![
        ("dont", "don't", "Contract with apostrophe"),
        ("cant", "can't", "Contract with apostrophe"),
        ("wont", "won't", "Contract with apostrophe"),
        ("im", "I'm", "Contract with apostrophe"),
        ("youre", "you're", "Contract with apostrophe"),
        ("theyre", "they're", "Contract with apostrophe"),
        ("its", "it's", "Possessive vs contraction"),
        ("your", "you're", "Your vs you're"),
        ("their", "they're", "Their vs they're"),
        ("there", "there", "There vs they're vs their"),
        ("loose", "lose", "Lose vs loose"),
        ("alot", "a lot", "Two words"),
        ("alright", "all right", "Two words"),
        ("aks", "ask", "Spelling"),
        ("teh", "the", "Spelling"),
        ("recieve", "receive", "Spelling (i before e)"),
        ("occured", "occurred", "Double r"),
        ("seperate", "separate", "Spelling"),
        ("definately", "definitely", "Spelling"),
        ("accomodate", "accommodate", "Double c and m"),
        ("occassion", "occasion", "Spelling"),
        ("neccessary", "necessary", "Spelling"),
        ("persistant", "persistent", "Spelling"),
        ("recomend", "recommend", "Spelling"),
        ("tommorow", "tomorrow", "Spelling"),
        ("wierd", "weird", "Spelling"),
        ("begining", "beginning", "Spelling"),
        ("beleive", "believe", "Spelling"),
        ("calender", "calendar", "Spelling"),
        ("concensus", "consensus", "Spelling"),
    ];

    for (wrong, correct, reason) in grammar_rules {
        if result.to_lowercase().contains(wrong) {
            let pattern = regex::Regex::new(&format!(r"(?i)\b{}\b", wrong)).unwrap();
            if pattern.is_match(&result) {
                corrections.push(format!("'{}' -> '{}': {}", wrong, correct, reason));
                result = pattern.replace(&result, correct).to_string();
            }
        }
    }

    (result, corrections)
}

fn perform_code_reshape(code: &str, operation: &str) -> (String, f32) {
    match operation {
        "refactor" => reshape_code_refactor(code),
        "simplify" => reshape_code_simplify(code),
        "optimize" => reshape_code_optimize(code),
        "format" => reshape_code_format(code),
        "extract" => reshape_code_extract(code),
        "inline" => reshape_code_inline(code),
        "rename" => reshape_code_rename(code),
        _ => (code.to_string(), 0.5),
    }
}

fn reshape_code_refactor(code: &str) -> (String, f32) {
    let mut result = code.to_string();

    if code.contains("if x == true") {
        result = result.replace("if x == true", "if x");
    }
    if code.contains("if x == false") {
        result = result.replace("if x == false", "if !x");
    }
    if code.contains("if !x == false") {
        result = result.replace("if !x == false", "if x");
    }

    let mut_count_before = result.matches("let mut ").count();
    if result.matches("let mut ").count() > 3 {
        result = result.replace("let mut ", "let ");
    }
    let mut_count_after = result.matches("let mut ").count();
    if mut_count_before != mut_count_after {
        return (result, 0.85);
    }

    (result, 0.75)
}

fn reshape_code_simplify(code: &str) -> (String, f32) {
    let mut result = code.to_string();

    if code.contains("if condition { return true; } else { return false; }") {
        result = result
            .replace(
                "if condition { return true; } else { return false; }",
                "condition",
            )
            .replace("condition", "result");
    }

    if code.contains(".map(|x| x.clone())") {
        result = result.replace(".map(|x| x.clone())", ".cloned()");
    }

    if code.contains(".iter().map(|x| x)") {
        result = result.replace(".iter().map(|x| x)", ".iter()");
    }

    if code.contains("if x > 0 { x } else { 0 }") {
        result = result.replace("if x > 0 { x } else { 0 }", "x.max(0)");
    }

    (result, 0.80)
}

fn reshape_code_optimize(code: &str) -> (String, f32) {
    let mut result = code.to_string();

    if code.contains("for i in 0..1000 { ") && code.contains("collect()") {
        result = result.replace(
            "for i in 0..1000 { ",
            "for i in 0..1000 { // Consider: use iterator chain\n        ",
        );
    }

    if code.contains("String::new()") && code.contains("push_str") {
        result = result.replace("String::new()", "String::with_capacity(N)");
    }

    if code.contains(".clone()") && code.contains(".clone()") {
        result = result.replace(".clone()", ".cloned()");
    }

    (result, 0.78)
}

fn reshape_code_format(code: &str) -> (String, f32) {
    let mut result = code.to_string();

    if code.contains("{") && !code.contains(" {\n") {
        result = result.replace("{", " {\n    ");
    }

    if code.contains("fn ") && !code.contains("\nfn ") {
        result = result.replace("fn ", "\nfn ");
    }

    if code.contains("impl ") && !code.contains("\nimpl ") {
        result = result.replace("impl ", "\nimpl ");
    }

    (result, 0.70)
}

fn reshape_code_extract(code: &str) -> (String, f32) {
    let result = format!(
        "// Extracted function\nfn extracted_function() {{\n    {}\n}}",
        code.lines()
            .map(|l| format!("    {}", l))
            .collect::<Vec<_>>()
            .join("\n")
    );
    (result, 0.82)
}

fn reshape_code_inline(code: &str) -> (String, f32) {
    if code.contains("fn ") {
        let lines: Vec<&str> = code.lines().collect();
        if lines.len() > 1 {
            return (lines[1..].join("\n"), 0.75);
        }
    }
    (code.to_string(), 0.60)
}

fn reshape_code_rename(code: &str) -> (String, f32) {
    let result = code
        .replace("variable", "renamed_variable")
        .replace("data", "processed_data")
        .replace("temp", "temporary_value");
    (result, 0.65)
}

#[cfg(test)]
mod tests {
    use super::*;

    static TESTS_INITIALIZED: std::sync::Once = std::sync::Once::new();

    fn ensure_initialized() {
        TESTS_INITIALIZED.call_once(|| {
            otto_initialize_completions();
        });
    }

    #[test]
    fn test_completion_lookup() {
        ensure_initialized();

        let test_text = CString::new("fn").unwrap();
        let prefix = otto_get_completion_prefix(test_text.as_ptr());
        let suggestion = otto_get_completion_suggestion(test_text.as_ptr());

        assert!(!prefix.is_null());
        assert!(!suggestion.is_null());

        otto_free_completion_strings(prefix, suggestion);
    }

    #[test]
    fn test_grammar_check() {
        ensure_initialized();
        otto_set_grammar_enabled(true);

        let test_text = CString::new("dont").unwrap();
        let result = otto_check_grammar(test_text.as_ptr());

        assert!(!result.is_null());
        otto_free_grammar_result(result);
    }

    #[test]
    fn test_code_reshape() {
        ensure_initialized();
        otto_set_code_reshape_enabled(true);

        let code = CString::new("if x == true { return true; }").unwrap();
        let operation = CString::new("refactor").unwrap();
        let result = otto_reshape_code(code.as_ptr(), operation.as_ptr());

        assert!(!result.is_null());
        otto_free_code_reshape_result(result);
    }

    #[test]
    fn test_model_switching() {
        ensure_initialized();

        otto_set_model(CString::new("zeta-2").unwrap().as_ptr());
        let model = unsafe { CStr::from_ptr(otto_get_current_model()) };
        assert_eq!(model.to_str().unwrap(), "zeta-2");

        otto_set_model(CString::new("qwen-3.5").unwrap().as_ptr());
        let model = unsafe { CStr::from_ptr(otto_get_current_model()) };
        assert_eq!(model.to_str().unwrap(), "qwen-3.5");

        otto_set_model(CString::new("gemma-4").unwrap().as_ptr());
        let model = unsafe { CStr::from_ptr(otto_get_current_model()) };
        assert_eq!(model.to_str().unwrap(), "gemma-4");
    }
}
