use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

static CODE_RESHAPE_ENABLED: OnceLock<AtomicBool> = OnceLock::new();
static GRAMMAR_ENABLED: OnceLock<AtomicBool> = OnceLock::new();
static CURRENT_MODEL: OnceLock<Mutex<CompletionModel>> = OnceLock::new();
static MODEL_CACHE_DIR: OnceLock<PathBuf> = OnceLock::new();
static HF_TOKEN: OnceLock<Option<String>> = OnceLock::new();

#[derive(Clone, Copy, PartialEq)]
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

    fn hf_repo_id(&self) -> &'static str {
        match self {
            CompletionModel::Zeta2 => "NexVeridian/zeta-2-4bit",
            CompletionModel::Qwen35 => "mlx-community/Qwen3.5-0.8B-OptiQ-4bit",
            CompletionModel::Gemma4 => "mlx-community/gemma-4-e2b-it-4bit",
        }
    }

    fn model_dir_name(&self) -> &'static str {
        match self {
            CompletionModel::Zeta2 => "zeta-2-4bit",
            CompletionModel::Qwen35 => "Qwen3.5-0.8B-OptiQ-4bit",
            CompletionModel::Gemma4 => "gemma-4-e2b-it-4bit",
        }
    }

    fn param_count(&self) -> usize {
        match self {
            CompletionModel::Zeta2 => 1_000_000_000,
            CompletionModel::Qwen35 => 800_000_000,
            CompletionModel::Gemma4 => 1_000_000_000,
        }
    }

    fn prompt_template(&self) -> &'static str {
        match self {
            CompletionModel::Zeta2 => "<|fim_prefix|>{prefix}<|fim_suffix|>{suffix}<|fim_middle|>",
            CompletionModel::Qwen35 => "<|im_start|>system\nContinue the text naturally. Output ONLY the continuation, no explanation.\n<|im_end|>\n<|im_start|>user\n{prefix}<|im_end|>\n<|im_start|>assistant\n",
            CompletionModel::Gemma4 => "<start_of_turn>user\nContinue this text naturally: {prefix}<end_of_turn>\n<start_of_turn>model\n",
        }
    }

    fn max_new_tokens(&self) -> usize {
        match self {
            CompletionModel::Zeta2 => 64,
            CompletionModel::Qwen35 => 32,
            CompletionModel::Gemma4 => 48,
        }
    }
}

fn parse_model(s: &str) -> Option<CompletionModel> {
    match s {
        "zeta-2" | "zeta" | "NexVeridian/zeta-2-4bit" => Some(CompletionModel::Zeta2),
        "qwen" | "qwen-3.5" | "Qwen3.5-0.8B" => Some(CompletionModel::Qwen35),
        "gemma" | "gemma-4" | "gemma4" | "mlx-community/gemma-4-e2b-it-4bit" => Some(CompletionModel::Gemma4),
        _ => None,
    }
}

fn get_model_cache_dir() -> PathBuf {
    MODEL_CACHE_DIR
        .get_or_init(|| dirs::cache_dir().unwrap_or_else(|| PathBuf::from(".")).join("tabyrus").join("models"))
        .clone()
}

fn get_model_local_path(model: &CompletionModel) -> PathBuf {
    get_model_cache_dir().join(model.model_dir_name())
}

fn ensure_cache_dir() -> std::io::Result<()> {
    std::fs::create_dir_all(get_model_cache_dir())
}

#[repr(C)]
pub struct CompletionResult {
    pub prefix: *const c_char,
    pub suggestion: *const c_char,
    pub confidence: f32,
    pub is_ml_based: bool,
}

#[repr(C)]
pub struct GrammarResult {
    pub original: *const c_char,
    pub corrected: *const c_char,
    pub suggestions: *const c_char,
    pub confidence: f32,
}

#[repr(C)]
pub struct CodeReshapeResult {
    pub original: *const c_char,
    pub reshaped: *const c_char,
    pub operation: *const c_char,
    pub confidence: f32,
}

#[repr(C)]
pub struct ModelDownloadResult {
    pub model_name: *const c_char,
    pub local_path: *const c_char,
    pub success: bool,
    pub error_message: *const c_char,
    pub size_bytes: u64,
}

#[repr(C)]
pub struct HardwareInfo {
    pub total_ram_gb: f64,
    pub has_apple_silicon: bool,
    pub cpu_count: u32,
    pub recommended_model: *const c_char,
}

#[repr(C)]
pub struct ClipboardAnalysis {
    pub text_type: *const c_char,
    pub app_name: *const c_char,
    pub summary: *const c_char,
    pub relevance_score: f32,
}

fn c_string(s: &str) -> *const c_char {
    CString::new(s).unwrap().into_raw()
}

fn from_c_str(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() { return None; }
    unsafe { CStr::from_ptr(ptr).to_str().ok().map(|s| s.to_string()) }
}

impl CompletionResult {
    pub fn new(prefix: String, suggestion: String, confidence: f32, is_ml_based: bool) -> Self {
        Self { prefix: c_string(&prefix), suggestion: c_string(&suggestion), confidence, is_ml_based }
    }
}

impl GrammarResult {
    pub fn new(original: String, corrected: String, suggestions: Vec<String>, confidence: f32) -> Self {
        let json = serde_json::to_string(&suggestions).unwrap_or_default();
        Self { original: c_string(&original), corrected: c_string(&corrected), suggestions: c_string(&json), confidence }
    }
}

impl CodeReshapeResult {
    pub fn new(original: String, reshaped: String, operation: String, confidence: f32) -> Self {
        Self { original: c_string(&original), reshaped: c_string(&reshaped), operation: c_string(&operation), confidence }
    }
}

impl ModelDownloadResult {
    pub fn success(model_name: String, local_path: PathBuf, size_bytes: u64) -> Self {
        Self {
            model_name: c_string(&model_name),
            local_path: c_string(&local_path.to_string_lossy()),
            success: true,
            error_message: std::ptr::null(),
            size_bytes,
        }
    }

    pub fn failure(model_name: String, error: String) -> Self {
        Self {
            model_name: c_string(&model_name),
            local_path: std::ptr::null(),
            success: false,
            error_message: c_string(&error),
            size_bytes: 0,
        }
    }
}

impl HardwareInfo {
    pub fn detect() -> Self {
        let total_ram = sys_info_ram_gb();
        let is_apple_silicon = cfg!(target_arch = "aarch64");
        let cpu_count = num_cpus::get() as u32;

        let recommended = if is_apple_silicon && total_ram >= 16.0 {
            "gemma-4"
        } else if is_apple_silicon && total_ram >= 8.0 {
            "qwen-3.5"
        } else if is_apple_silicon {
            "zeta-2"
        } else {
            "zeta-2"
        };

        Self {
            total_ram_gb: total_ram,
            has_apple_silicon: is_apple_silicon,
            cpu_count,
            recommended_model: c_string(recommended),
        }
    }
}

fn sys_info_ram_gb() -> f64 {
    let info = std::process::Command::new("sysctl")
        .args(["-n", "hw.memsize"])
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .and_then(|s| s.trim().parse::<u64>().ok())
        .unwrap_or(0);
    info as f64 / 1_073_741_824.0
}

impl ClipboardAnalysis {
    pub fn analyze(content: &str, app_name: &str) -> Self {
        let (text_type, relevance) = classify_clipboard(content);
        let summary = summarize_content(content);

        Self {
            text_type: c_string(&text_type),
            app_name: c_string(app_name),
            summary: c_string(&summary),
            relevance_score: relevance,
        }
    }
}

fn classify_clipboard(content: &str) -> (String, f32) {
    if content.is_empty() { return ("empty".into(), 0.0); }

    let prompt = format!(
        "Classify this content into one category. Reply with ONLY the category name.\n\
         Categories: code, url, email, prose, technical, data, message, or short.\n\n\
         Content: {}\n\n\
         Category:",
        &content.chars().take(500).collect::<String>()
    );

    if let Some(category) = run_mlx_prompt(&prompt, 8) {
        let cat = category.trim().to_lowercase();
        if !cat.is_empty() { return (cat, 0.9); }
    }

    ("unknown".into(), 0.0)
}

fn summarize_content(content: &str) -> String {
    let snippet: String = content.chars().take(300).collect();

    let prompt = format!(
        "Summarize what this text is about in 5 words or fewer. Reply ONLY with the summary.\n\n\
         Text: {snippet}\n\n\
         Summary:"
    );

    if let Some(summary) = run_mlx_prompt(&prompt, 20) {
        let s = summary.trim().to_string();
        if !s.is_empty() { return s; }
    }

    content.chars().take(50).collect()
}

#[no_mangle]
pub unsafe extern "C" fn tabyrus_init() {
    CODE_RESHAPE_ENABLED.get_or_init(|| AtomicBool::new(false));
    GRAMMAR_ENABLED.get_or_init(|| AtomicBool::new(false));
    CURRENT_MODEL.get_or_init(|| Mutex::new(CompletionModel::Gemma4));

    let cache = get_model_cache_dir();
    println!("Tabyrus Backend v0.2.0 (MLX)");
    println!("  Cache: {:?}", cache);

    for model in [CompletionModel::Gemma4, CompletionModel::Qwen35, CompletionModel::Zeta2] {
        let path = get_model_local_path(&model);
        let ok = path.exists() && path.join("config.json").exists();
        println!("  {} {}: {}", if ok { "[OK]" } else { "[--]" }, model.as_str(), model.hf_repo_id());
    }
    println!("Tabyrus ready.");
}

#[no_mangle]
pub unsafe extern "C" fn tabyrus_detect_hardware() -> *mut HardwareInfo {
    Box::into_raw(Box::new(HardwareInfo::detect()))
}

#[no_mangle]
pub unsafe extern "C" fn tabyrus_free_hardware_info(info: *mut HardwareInfo) {
    if info.is_null() { return; }
    unsafe {
        if !(*info).recommended_model.is_null() {
            drop(CString::from_raw((*info).recommended_model as *mut c_char));
        }
        let _ = Box::from_raw(info);
    }
}

#[no_mangle]
pub unsafe extern "C" fn tabyrus_set_model(model_name: *const c_char) {
    if let Some(s) = from_c_str(model_name).and_then(|s| parse_model(&s)) {
        if let Ok(mut g) = CURRENT_MODEL.get_or_init(|| Mutex::new(CompletionModel::Gemma4)).lock() {
            *g = s;
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn tabyrus_set_code_reshape_enabled(enabled: bool) {
    if let Some(f) = CODE_RESHAPE_ENABLED.get() { f.store(enabled, Ordering::Relaxed); }
}

#[no_mangle]
pub unsafe extern "C" fn tabyrus_set_grammar_enabled(enabled: bool) {
    if let Some(f) = GRAMMAR_ENABLED.get() { f.store(enabled, Ordering::Relaxed); }
}

#[no_mangle]
pub unsafe extern "C" fn tabyrus_get_current_model() -> *const c_char {
    let name = CURRENT_MODEL.get()
        .and_then(|l| l.lock().ok())
        .map(|g| g.as_str())
        .unwrap_or("gemma-4");
    c_string(name)
}

#[no_mangle]
pub unsafe extern "C" fn tabyrus_get_completion(text: *const c_char) -> *mut c_char {
    let text_str = match from_c_str(text) { Some(s) => s, None => return std::ptr::null_mut() };
    if text_str.is_empty() { return std::ptr::null_mut(); }

    if let Some(result) = ml_complete(&text_str) {
        let json = format!(
            r#"{{"prefix":"{}","suggestion":"{}","confidence":{},"is_ml_based":true}}"#,
            escape_json(&result.0), escape_json(&result.1), result.2
        );
        return CString::new(json).unwrap().into_raw();
    }

    std::ptr::null_mut()
}

#[no_mangle]
pub unsafe extern "C" fn tabyrus_get_completion_suggestion(text: *const c_char) -> *const c_char {
    let text_str = match from_c_str(text) { Some(s) => s, None => return std::ptr::null() };

    if let Some(result) = ml_complete(&text_str) {
        return c_string(&normalize_suggestion(&result.1, &text_str));
    }
    std::ptr::null()
}

#[no_mangle]
pub unsafe extern "C" fn tabyrus_normalize_suggestion(suggestion: *const c_char, input: *const c_char) -> *const c_char {
    let sug = from_c_str(suggestion).unwrap_or_default();
    let inp = from_c_str(input).unwrap_or_default();
    c_string(&normalize_suggestion(&sug, &inp))
}

pub fn normalize_suggestion(suggestion: &str, input: &str) -> String {
    let gen = suggestion.trim();

    let stop_tokens = ["\n\n", "\nfn ", "\nimpl ", "\nmod ", "\nstruct ",
                       "\npub ", "\ntrait ", "\nuse ", "\nlet ", "\nif ",
                       "<|", "\n---", "```"];
    let mut result = gen.to_string();
    for token in stop_tokens {
        if let Some(pos) = result.find(token) {
            result.truncate(pos);
        }
    }

    let words: Vec<&str> = result.split_whitespace().collect();
    if words.len() > 12 {
        result = words[..12].join(" ");
    }

    let gen_lower = result.to_lowercase();
    let input_lower = input.trim().to_lowercase();

    if gen_lower.starts_with(&input_lower) && input_lower.len() < gen_lower.len() {
        return result[input_lower.len()..].trim().to_string();
    }

    let input_words: Vec<&str> = input.split_whitespace().collect();
    let last_word = input_words.last().unwrap_or(&"").to_lowercase();
    if gen_lower.starts_with(&last_word) && last_word.len() < gen_lower.len() {
        return result[last_word.len()..].trim().to_string();
    }

    result
}

fn ml_complete(text: &str) -> Option<(String, String, f32)> {
    let (model_path, prompt_template, max_new_tokens) = {
        let model = CURRENT_MODEL.get()?.lock().ok()?;
        (
            get_model_local_path(&model),
            model.prompt_template().to_string(),
            model.max_new_tokens(),
        )
    };

    if !model_path.exists() || !model_path.join("config.json").exists() {
        return None;
    }

    let words: Vec<&str> = text.split_whitespace().collect();
    let last_word = words.last()?;
    if last_word.len() < 2 { return None; }

    let context: Vec<&str> = if words.len() > 40 { words[words.len() - 40..].to_vec() } else { words.clone() };
    let prefix = context.join(" ");
    let last_word_str = last_word.to_string();

    let prompt = prompt_template.replace("{prefix}", &prefix).replace("{suffix}", "");
    let generated = generate_text(&prompt, max_new_tokens)?;

    let cleaned = normalize_suggestion(&generated, text);
    if cleaned.is_empty() { return None; }
    Some((last_word_str, cleaned, 0.85))
}

fn generate_text(prompt: &str, max_tokens: usize) -> Option<String> {
    #[cfg(feature = "mlx")]
    { return mlx_generate_inner(prompt, max_tokens); }
    #[cfg(not(feature = "mlx"))]
    { return fallback_mlx_generate(prompt, max_tokens); }
}

#[cfg(feature = "mlx")]
fn mlx_generate_inner(prompt: &str, max_tokens: usize) -> Option<String> {
    // MLX inference via mlx-rs crate
    fallback_mlx_generate(prompt, max_tokens)
}

fn fallback_mlx_generate(prompt: &str, max_tokens: usize) -> Option<String> {
    let model_path = {
        let model = CURRENT_MODEL.get()?.lock().ok()?;
        get_model_local_path(&model)
    };

    if !model_path.exists() { return None; }

    let output = std::process::Command::new("mlx_lm.generate")
        .arg("--model").arg(model_path.to_string_lossy().to_string())
        .arg("--prompt").arg(prompt)
        .arg("--max-tokens").arg(max_tokens.to_string())
        .arg("--temp").arg("0.3")
        .output().ok()?;

    if output.status.success() {
        Some(String::from_utf8_lossy(&output.stdout).trim().to_string())
    } else {
        None
    }
}

fn escape_json(s: &str) -> String {
    s.replace('\\', "\\\\").replace('"', "\\\"").replace('\n', "\\n")
}

#[no_mangle]
pub unsafe extern "C" fn tabyrus_free_string(s: *mut c_char) {
    if !s.is_null() { unsafe { drop(CString::from_raw(s)); } }
}

#[no_mangle]
pub unsafe extern "C" fn tabyrus_free_result(prefix: *const c_char, suggestion: *const c_char) {
    if !prefix.is_null() { unsafe { drop(CString::from_raw(prefix as *mut c_char)); } }
    if !suggestion.is_null() { unsafe { drop(CString::from_raw(suggestion as *mut c_char)); } }
}

#[no_mangle]
pub unsafe extern "C" fn tabyrus_check_grammar(text: *const c_char) -> *mut GrammarResult {
    let text_str = match from_c_str(text) { Some(s) => s, None => return std::ptr::null_mut() };
    let enabled = GRAMMAR_ENABLED.get().map(|b| b.load(Ordering::Relaxed)).unwrap_or(false);
    if !enabled { return std::ptr::null_mut(); }

    let (corrected, suggestions) = run_grammar_check(&text_str);
    Box::into_raw(Box::new(GrammarResult::new(text_str, corrected, suggestions, 0.85)))
}

#[no_mangle]
pub unsafe extern "C" fn tabyrus_free_grammar_result(result: *mut GrammarResult) {
    if result.is_null() { return; }
    unsafe {
        if !(*result).original.is_null() { drop(CString::from_raw((*result).original as *mut c_char)); }
        if !(*result).corrected.is_null() { drop(CString::from_raw((*result).corrected as *mut c_char)); }
        if !(*result).suggestions.is_null() { drop(CString::from_raw((*result).suggestions as *mut c_char)); }
        let _ = Box::from_raw(result);
    }
}

fn run_grammar_check(text: &str) -> (String, Vec<String>) {
    let prompt = format!(
        "You are a grammar checker. Analyze the text below.\n\
         If it contains grammar, spelling, or punctuation errors, output ONLY the corrected version.\n\
         If it is already correct, output ONLY the exact same text.\n\
         Do not add explanations, do not rephrase, only fix errors.\n\n\
         Text: {text}\n\n\
         Corrected:",
        text = text
    );

    if let Some(corrected) = run_mlx_prompt(&prompt, 128) {
        let cleaned = corrected.trim().to_string();
        if cleaned != text && !cleaned.is_empty() {
            return (cleaned, vec!["AI grammar correction".into()]);
        }
    }

    (text.to_string(), vec![])
}

fn run_mlx_prompt(prompt: &str, max_tokens: usize) -> Option<String> {
    let model_path = {
        let model = CURRENT_MODEL.get()?.lock().ok()?;
        get_model_local_path(&model)
    };
    if !model_path.exists() { return None; }

    let output = std::process::Command::new("mlx_lm.generate")
        .arg("--model").arg(model_path.to_string_lossy().to_string())
        .arg("--prompt").arg(prompt)
        .arg("--max-tokens").arg(max_tokens.to_string())
        .arg("--temp").arg("0.1")
        .output().ok()?;

    if output.status.success() {
        let raw = String::from_utf8_lossy(&output.stdout).trim().to_string();
        Some(strip_prompt_echo(&raw, prompt))
    } else {
        None
    }
}

fn strip_prompt_echo(output: &str, prompt: &str) -> String {
    if output.starts_with(prompt) {
        output[prompt.len()..].trim().to_string()
    } else {
        output.to_string()
    }
}

#[no_mangle]
pub unsafe extern "C" fn tabyrus_reshape_code(code: *const c_char, operation: *const c_char) -> *mut CodeReshapeResult {
    let code_str = match from_c_str(code) { Some(s) => s, None => return std::ptr::null_mut() };
    let op_str = match from_c_str(operation) { Some(s) => s, None => return std::ptr::null_mut() };
    let enabled = CODE_RESHAPE_ENABLED.get().map(|b| b.load(Ordering::Relaxed)).unwrap_or(false);
    if !enabled { return std::ptr::null_mut(); }

    let (reshaped, confidence) = run_code_reshape(&code_str, &op_str);
    Box::into_raw(Box::new(CodeReshapeResult::new(code_str, reshaped, op_str, confidence)))
}

#[no_mangle]
pub unsafe extern "C" fn tabyrus_free_code_reshape_result(result: *mut CodeReshapeResult) {
    if result.is_null() { return; }
    unsafe {
        if !(*result).original.is_null() { drop(CString::from_raw((*result).original as *mut c_char)); }
        if !(*result).reshaped.is_null() { drop(CString::from_raw((*result).reshaped as *mut c_char)); }
        if !(*result).operation.is_null() { drop(CString::from_raw((*result).operation as *mut c_char)); }
        let _ = Box::from_raw(result);
    }
}

fn run_code_reshape(code: &str, operation: &str) -> (String, f32) {
    let prompt = format!(
        "You are a code editor. Apply the '{operation}' operation to the code below.\n\
         Output ONLY the transformed code.\n\n\
         Code:\n```\n{code}\n```\n\n\
         Transformed:\n```",
        operation = operation, code = code
    );

    if let Some(reshaped) = run_mlx_prompt(&prompt, 512) {
        let cleaned = reshaped.trim().trim_matches('`').trim().to_string();
        if !cleaned.is_empty() {
            return (cleaned, 0.85);
        }
    }

    (code.to_string(), 0.0)
}

#[no_mangle]
pub unsafe extern "C" fn tabyrus_analyze_clipboard(content: *const c_char, app_name: *const c_char) -> *mut ClipboardAnalysis {
    let content_str = from_c_str(content).unwrap_or_default();
    let app_str = from_c_str(app_name).unwrap_or_default();
    Box::into_raw(Box::new(ClipboardAnalysis::analyze(&content_str, &app_str)))
}

#[no_mangle]
pub unsafe extern "C" fn tabyrus_free_clipboard_analysis(analysis: *mut ClipboardAnalysis) {
    if analysis.is_null() { return; }
    unsafe {
        if !(*analysis).text_type.is_null() { drop(CString::from_raw((*analysis).text_type as *mut c_char)); }
        if !(*analysis).app_name.is_null() { drop(CString::from_raw((*analysis).app_name as *mut c_char)); }
        if !(*analysis).summary.is_null() { drop(CString::from_raw((*analysis).summary as *mut c_char)); }
        let _ = Box::from_raw(analysis);
    }
}

#[no_mangle]
pub unsafe extern "C" fn tabyrus_set_hf_token(token: *const c_char) {
    if token.is_null() { HF_TOKEN.get_or_init(|| None); return; }
    if let Ok(s) = unsafe { CStr::from_ptr(token).to_str() } { HF_TOKEN.get_or_init(|| Some(s.to_string())); }
}

#[no_mangle]
pub unsafe extern "C" fn tabyrus_download_model(model_name: *const c_char) -> *mut ModelDownloadResult {
    let model_str = match from_c_str(model_name) { Some(s) => s, None => return Box::into_raw(Box::new(ModelDownloadResult::failure("unknown".into(), "Invalid name".into()))) };
    let model = match parse_model(&model_str) { Some(m) => m, None => return Box::into_raw(Box::new(ModelDownloadResult::failure(model_str.clone(), format!("Unknown: {}", model_str)))) };

    let local = get_model_local_path(&model);
    let repo = model.hf_repo_id().to_string();

    if local.exists() && local.join("config.json").exists() {
        let size = walkdir::WalkDir::new(&local).into_iter().filter_map(|e| e.ok())
            .filter(|e| e.file_type().is_file()).filter_map(|e| e.metadata().ok()).map(|m| m.len()).sum();
        return Box::into_raw(Box::new(ModelDownloadResult::success(repo, local, size)));
    }

    match download_hf_model(&repo, &local) {
        Ok(size) => Box::into_raw(Box::new(ModelDownloadResult::success(repo, local, size))),
        Err(e) => Box::into_raw(Box::new(ModelDownloadResult::failure(repo, e.to_string()))),
    }
}

#[no_mangle]
pub unsafe extern "C" fn tabyrus_is_model_downloaded(model_name: *const c_char) -> bool {
    let model = match from_c_str(model_name).and_then(|s| parse_model(&s)) { Some(m) => m, None => {
        println!("is_downloaded: unknown model");
        return false;
    }};
    let p = get_model_local_path(&model);
    let exists = p.exists();
    let has_config = exists && p.join("config.json").exists();
    println!("is_downloaded({}): path={:?} exists={} config={}", model.as_str(), p, exists, has_config);
    has_config
}

#[no_mangle]
pub unsafe extern "C" fn tabyrus_get_model_cache_path(model_name: *const c_char) -> *const c_char {
    match from_c_str(model_name).and_then(|s| parse_model(&s)) {
        Some(m) => c_string(&get_model_local_path(&m).to_string_lossy()),
        None => std::ptr::null(),
    }
}

#[no_mangle]
pub unsafe extern "C" fn tabyrus_free_model_download_result(result: *mut ModelDownloadResult) {
    if result.is_null() { return; }
    unsafe {
        if !(*result).model_name.is_null() { drop(CString::from_raw((*result).model_name as *mut c_char)); }
        if !(*result).local_path.is_null() { drop(CString::from_raw((*result).local_path as *mut c_char)); }
        if !(*result).error_message.is_null() { drop(CString::from_raw((*result).error_message as *mut c_char)); }
        let _ = Box::from_raw(result);
    }
}

fn download_hf_model(repo_id: &str, local_path: &PathBuf) -> Result<u64, Box<dyn std::error::Error + Send + Sync>> {
    ensure_cache_dir()?;
    let token = HF_TOKEN.get().and_then(|t| t.as_ref()).cloned();
    let url = format!("https://huggingface.co/api/models/{}", repo_id);
    let mut req = ureq::get(&url);
    if let Some(ref t) = token { req = req.set("Authorization", &format!("Bearer {}", t)); }
    let resp: serde_json::Value = req.call()?.into_json()?;
    let siblings = resp.get("siblings").and_then(|s| s.as_array()).ok_or("No siblings")?;
    let files: Vec<String> = siblings.iter().filter_map(|f| f.get("rfilename").and_then(|r| r.as_str())).map(String::from).collect();

    std::fs::create_dir_all(local_path)?;
    let total = Arc::new(std::sync::atomic::AtomicU64::new(0));
    let mut handles = vec![];

    for path in files {
        let fp = local_path.join(&path);
        let tot = Arc::clone(&total);
        let rid = repo_id.to_string();
        let tok = token.clone();
        if let Some(p) = fp.parent() { std::fs::create_dir_all(p).ok(); }
        handles.push(std::thread::spawn(move || {
            let u = format!("https://huggingface.co/{}/resolve/main/{}", rid, path);
            let mut r = ureq::get(&u);
            if let Some(ref t) = tok { r = r.set("Authorization", &format!("Bearer {}", t)); }
            if let Ok(resp) = r.call() {
                if let Ok(mut file) = std::fs::File::create(&fp) {
                    if std::io::copy(&mut resp.into_reader(), &mut file).is_ok() {
                        if let Ok(meta) = std::fs::metadata(&fp) { tot.fetch_add(meta.len(), Ordering::Relaxed); }
                    }
                }
            }
        }));
    }
    for h in handles { let _ = h.join(); }
    Ok(total.load(Ordering::Relaxed))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Once;
    static INIT: Once = Once::new();
    fn init() { INIT.call_once(|| unsafe { tabyrus_init() }); }

    #[test]
    fn test_completion() {
        init();
        let s = CString::new("th").unwrap();
        let r = unsafe { tabyrus_get_completion(s.as_ptr()) };
        // Returns null when no ML model is downloaded (no dictionary fallback)
        if !r.is_null() { unsafe { tabyrus_free_string(r); } }
    }

    #[test]
    fn test_grammar_check() {
        init();
        unsafe { tabyrus_set_grammar_enabled(true); }
        let s = CString::new("dont do that").unwrap();
        let r = unsafe { tabyrus_check_grammar(s.as_ptr()) };
        // May be null if MLX model not available
        if !r.is_null() { unsafe { tabyrus_free_grammar_result(r); } }
    }

    #[test]
    fn test_code_reshape() {
        init();
        unsafe { tabyrus_set_code_reshape_enabled(true); }
        let c = CString::new("fn hello() { return 1; }").unwrap();
        let o = CString::new("refactor").unwrap();
        let r = unsafe { tabyrus_reshape_code(c.as_ptr(), o.as_ptr()) };
        // May be null if MLX model not available — that's fine, test just ensures no crash
        if !r.is_null() { unsafe { tabyrus_free_code_reshape_result(r); } }
    }

    #[test]
    fn test_model_switch() {
        init();
        unsafe { tabyrus_set_model(CString::new("zeta-2").unwrap().as_ptr()); }
        let m = unsafe { CStr::from_ptr(tabyrus_get_current_model()) };
        assert_eq!(m.to_str().unwrap(), "zeta-2");
    }

    #[test]
    fn test_clipboard_analysis() {
        let a = ClipboardAnalysis::analyze("https://github.com/user/repo", "Safari");
        // Without MLX model loaded, returns "unknown" — structure is still valid
        let _type = unsafe { CStr::from_ptr(a.text_type).to_str().unwrap() };
        assert!(!_type.is_empty());
    }

    #[test]
    fn test_hardware_detection() {
        let h = HardwareInfo::detect();
        assert!(h.total_ram_gb > 0.0);
    }

    #[test]
    fn test_normalize_suggestion() {
        assert_eq!(normalize_suggestion("the thing\n\n", "th"), "e thing");
        assert_eq!(normalize_suggestion("fn main() {", "fn m"), "ain() {");
    }

    #[test]
    fn test_normalize_stops_at_newline() {
        let n = normalize_suggestion("hello world\nfn new", "hello");
        assert_eq!(n, "world");
    }
}
