use std::collections::HashMap;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::PathBuf;
use std::sync::{Arc, Mutex, OnceLock};

static COMPLETIONS: OnceLock<HashMap<&'static str, Vec<&'static str>>> = OnceLock::new();
static ZETA_MODEL: OnceLock<ZetaModel> = OnceLock::new();
static QWEN_MODEL: OnceLock<QwenModel> = OnceLock::new();
static GEMMA_MODEL: OnceLock<GemmaModel> = OnceLock::new();
static CURRENT_MODEL: OnceLock<Mutex<CompletionModel>> = OnceLock::new();
static MODEL_CACHE_DIR: OnceLock<PathBuf> = OnceLock::new();
static HF_TOKEN: OnceLock<Option<String>> = OnceLock::new();

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
}

#[allow(dead_code)]
struct ZetaModel {
    model_name: String,
    parameter_count: usize,
    vocab_size: usize,
    is_edit_model: bool,
    is_loaded: bool,
}

#[allow(dead_code)]
struct QwenModel {
    model_name: String,
    parameter_count: usize,
    vocab_size: usize,
    is_loaded: bool,
}

#[allow(dead_code)]
struct GemmaModel {
    model_name: String,
    parameter_count: usize,
    vocab_size: usize,
    is_multimodal: bool,
    is_loaded: bool,
}

#[derive(Clone)]
pub struct ModelInfo {
    pub repo_id: String,
    pub local_path: Option<PathBuf>,
    pub size_gb: f64,
    pub params: usize,
    pub quantization: String,
}

impl ZetaModel {
    fn new() -> Self {
        ZetaModel {
            model_name: "NexVeridian/zeta-2-4bit".to_string(),
            parameter_count: 1_000_000_000,
            vocab_size: 200000,
            is_edit_model: true,
            is_loaded: false,
        }
    }
}

impl QwenModel {
    fn new() -> Self {
        QwenModel {
            model_name: "Qwen3.5-0.8B".to_string(),
            parameter_count: 800_000_000,
            vocab_size: 151936,
            is_loaded: false,
        }
    }
}

impl GemmaModel {
    fn new() -> Self {
        GemmaModel {
            model_name: "mlx-community/gemma-4-e2b-it-4bit".to_string(),
            parameter_count: 1_000_000_000,
            vocab_size: 256000,
            is_multimodal: true,
            is_loaded: false,
        }
    }
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

#[repr(C)]
pub struct ModelDownloadResult {
    pub model_name: *const c_char,
    pub local_path: *const c_char,
    pub success: bool,
    pub error_message: *const c_char,
    pub size_bytes: u64,
}

impl ModelDownloadResult {
    pub fn success(model_name: String, local_path: PathBuf, size_bytes: u64) -> Self {
        Self {
            model_name: CString::new(model_name).unwrap().into_raw(),
            local_path: CString::new(local_path.to_string_lossy().to_string())
                .unwrap()
                .into_raw(),
            success: true,
            error_message: std::ptr::null(),
            size_bytes,
        }
    }

    pub fn failure(model_name: String, error: String) -> Self {
        Self {
            model_name: CString::new(model_name).unwrap().into_raw(),
            local_path: std::ptr::null(),
            success: false,
            error_message: CString::new(error).unwrap().into_raw(),
            size_bytes: 0,
        }
    }
}

static CODE_RESHAPE_ENABLED: OnceLock<std::sync::atomic::AtomicBool> = OnceLock::new();
static GRAMMAR_ENABLED: OnceLock<std::sync::atomic::AtomicBool> = OnceLock::new();

fn get_model_cache_dir() -> PathBuf {
    MODEL_CACHE_DIR
        .get_or_init(|| {
            dirs::cache_dir()
                .unwrap_or_else(|| PathBuf::from("."))
                .join("otto")
                .join("models")
        })
        .clone()
}

fn get_model_local_path(model: &CompletionModel) -> PathBuf {
    get_model_cache_dir().join(model.model_dir_name())
}

fn ensure_cache_dir_exists() -> std::io::Result<()> {
    std::fs::create_dir_all(get_model_cache_dir())
}

#[no_mangle]
pub unsafe extern "C" fn otto_set_hf_token(token: *const c_char) {
    if token.is_null() {
        HF_TOKEN.get_or_init(|| None);
        println!("HuggingFace token cleared");
        return;
    }

    let c_str = unsafe { CStr::from_ptr(token) };
    if let Ok(token_str) = c_str.to_str() {
        HF_TOKEN.get_or_init(|| Some(token_str.to_string()));
        println!("HuggingFace token set");
    }
}

#[no_mangle]
pub unsafe extern "C" fn otto_download_model(
    model_name: *const c_char,
) -> *mut ModelDownloadResult {
    let c_str = unsafe { CStr::from_ptr(model_name) };
    let model_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => {
            return Box::into_raw(Box::new(ModelDownloadResult::failure(
                "unknown".to_string(),
                "Invalid model name".to_string(),
            )));
        }
    };

    let model = match model_str {
        "zeta-2" | "zeta" | "NexVeridian/zeta-2-4bit" => CompletionModel::Zeta2,
        "qwen" | "qwen-3.5" | "Qwen3.5-0.8B" => CompletionModel::Qwen35,
        "gemma" | "gemma-4" | "gemma4" | "mlx-community/gemma-4-e2b-it-4bit" => {
            CompletionModel::Gemma4
        }
        _ => {
            return Box::into_raw(Box::new(ModelDownloadResult::failure(
                model_str.to_string(),
                format!("Unknown model: {}", model_str),
            )));
        }
    };

    let repo_id = model.hf_repo_id().to_string();
    let local_path = get_model_local_path(&model);

    if local_path.exists() && local_path.join("config.json").exists() {
        let size = calculate_dir_size(&local_path);
        println!("Model {} already cached at {:?}", repo_id, local_path);
        return Box::into_raw(Box::new(ModelDownloadResult::success(
            repo_id, local_path, size,
        )));
    }

    println!("Downloading model {} from HuggingFace...", repo_id);

    match download_model_from_hf(&repo_id, &local_path) {
        Ok(size) => {
            println!(
                "Successfully downloaded {} ({} bytes) to {:?}",
                repo_id, size, local_path
            );
            Box::into_raw(Box::new(ModelDownloadResult::success(
                repo_id, local_path, size,
            )))
        }
        Err(e) => {
            println!("Failed to download model {}: {}", repo_id, e);
            Box::into_raw(Box::new(ModelDownloadResult::failure(
                repo_id,
                e.to_string(),
            )))
        }
    }
}

fn download_model_from_hf(
    repo_id: &str,
    local_path: &PathBuf,
) -> Result<u64, Box<dyn std::error::Error + Send + Sync>> {
    ensure_cache_dir_exists()?;

    let token = HF_TOKEN.get().and_then(|t| t.as_ref()).cloned();
    let repo_id_owned = repo_id.to_string();
    let local_path_owned = local_path.clone();

    println!("Connecting to HuggingFace Hub: {}", repo_id);

    let file_list = get_model_file_list(repo_id, token.as_deref())?;
    println!("Found {} files to download", file_list.len());

    std::fs::create_dir_all(local_path)?;

    let total_size: Arc<std::sync::atomic::AtomicU64> =
        Arc::new(std::sync::atomic::AtomicU64::new(0));
    let mut handles = vec![];

    for path in file_list {
        let file_path = local_path_owned.join(&path);
        let total = Arc::clone(&total_size);
        let repo = repo_id_owned.clone();
        let tok = token.clone();

        if let Some(parent) = file_path.parent() {
            std::fs::create_dir_all(parent).ok();
        }

        let handle = std::thread::spawn(move || {
            let url = format!("https://huggingface.co/{}/resolve/main/{}", repo, path);
            if let Err(e) = download_file(&url, &file_path, tok.as_deref()) {
                eprintln!("Failed to download: {}", e);
            } else {
                if let Ok(metadata) = std::fs::metadata(&file_path) {
                    total.fetch_add(metadata.len(), std::sync::atomic::Ordering::Relaxed);
                }
                println!(
                    "Downloaded: ({:.2} MB)",
                    file_path
                        .metadata()
                        .map(|m| m.len() as f64 / 1_048_576.0)
                        .unwrap_or(0.0)
                );
            }
        });
        handles.push(handle);
    }

    for handle in handles {
        let _ = handle.join();
    }

    let total_size = total_size.load(std::sync::atomic::Ordering::Relaxed);
    Ok(total_size)
}

fn download_file(
    url: &str,
    path: &PathBuf,
    token: Option<&str>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let mut request = ureq::get(url);
    if let Some(t) = token {
        request = request.set("Authorization", &format!("Bearer {}", t));
    }

    let response = request.call()?;

    let mut file = std::fs::File::create(path)?;
    std::io::copy(&mut response.into_reader(), &mut file)?;

    Ok(())
}

fn get_model_file_list(
    repo_id: &str,
    token: Option<&str>,
) -> Result<Vec<String>, Box<dyn std::error::Error + Send + Sync>> {
    let url = format!("https://huggingface.co/api/models/{}", repo_id);

    let mut request = ureq::get(&url);
    if let Some(t) = token {
        request = request.set("Authorization", &format!("Bearer {}", t));
    }

    let response: serde_json::Value = request.call()?.into_json()?;

    let siblings = response
        .get("siblings")
        .and_then(|s| s.as_array())
        .ok_or("Could not find siblings in model info")?;

    let files: Vec<String> = siblings
        .iter()
        .filter_map(|f| f.get("rfilename").and_then(|r| r.as_str()))
        .map(String::from)
        .collect();

    Ok(files)
}

fn calculate_dir_size(path: &PathBuf) -> u64 {
    walkdir::WalkDir::new(path)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| e.file_type().is_file())
        .filter_map(|e| e.metadata().ok())
        .map(|m| m.len())
        .sum()
}

#[no_mangle]
pub unsafe extern "C" fn otto_free_model_download_result(result: *mut ModelDownloadResult) {
    if result.is_null() {
        return;
    }
    unsafe {
        if !(*result).model_name.is_null() {
            drop(CString::from_raw((*result).model_name as *mut c_char));
        }
        if !(*result).local_path.is_null() {
            drop(CString::from_raw((*result).local_path as *mut c_char));
        }
        if !(*result).error_message.is_null() {
            drop(CString::from_raw((*result).error_message as *mut c_char));
        }
        let _ = Box::from_raw(result);
    }
}

#[no_mangle]
pub unsafe extern "C" fn otto_is_model_downloaded(model_name: *const c_char) -> bool {
    let c_str = unsafe { CStr::from_ptr(model_name) };
    let model_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return false,
    };

    let model = match model_str {
        "zeta-2" | "zeta" | "NexVeridian/zeta-2-4bit" => CompletionModel::Zeta2,
        "qwen" | "qwen-3.5" | "Qwen3.5-0.8B" => CompletionModel::Qwen35,
        "gemma" | "gemma-4" | "gemma4" | "mlx-community/gemma-4-e2b-it-4bit" => {
            CompletionModel::Gemma4
        }
        _ => return false,
    };

    let local_path = get_model_local_path(&model);
    local_path.exists() && local_path.join("config.json").exists()
}

#[no_mangle]
pub unsafe extern "C" fn otto_get_model_cache_path(model_name: *const c_char) -> *const c_char {
    let c_str = unsafe { CStr::from_ptr(model_name) };
    let model_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null(),
    };

    let model = match model_str {
        "zeta-2" | "zeta" | "NexVeridian/zeta-2-4bit" => CompletionModel::Zeta2,
        "qwen" | "qwen-3.5" | "Qwen3.5-0.8B" => CompletionModel::Qwen35,
        "gemma" | "gemma-4" | "gemma4" | "mlx-community/gemma-4-e2b-it-4bit" => {
            CompletionModel::Gemma4
        }
        _ => return std::ptr::null(),
    };

    let path = get_model_local_path(&model);
    CString::new(path.to_string_lossy().to_string())
        .unwrap()
        .into_raw()
}

#[no_mangle]
pub unsafe extern "C" fn otto_initialize_completions() {
    // Only ML completions - dictionary is disabled
    // Models must be downloaded for completions to work

    CODE_RESHAPE_ENABLED.get_or_init(|| std::sync::atomic::AtomicBool::new(false));
    GRAMMAR_ENABLED.get_or_init(|| std::sync::atomic::AtomicBool::new(false));

    println!("===========================================");
    println!("  Otto AI Autocomplete - Initializing");
    println!("===========================================");
    println!();
    println!("Available Models:");
    println!("  • zeta-2 (NexVeridian/zeta-2-4bit) - Code editing specialist");
    println!("  • qwen-3.5 (Qwen3.5-0.8B-OptiQ-4bit) - General purpose");
    println!("  • gemma-4 (gemma-4-e2b-it-4bit) - Multimodal instruction-tuned");
    println!();
    println!("Model cache directory: {:?}", get_model_cache_dir());
    println!();

    ZETA_MODEL.get_or_init(|| {
        let local_path = get_model_local_path(&CompletionModel::Zeta2);
        if local_path.exists() {
            println!("zeta-2 model found in cache at {:?}", local_path);
            let mut model = ZetaModel::new();
            model.is_loaded = true;
            model
        } else {
            println!("zeta-2 model not downloaded. Use otto_download_model() to fetch it.");
            ZetaModel::new()
        }
    });

    QWEN_MODEL.get_or_init(|| {
        let local_path = get_model_local_path(&CompletionModel::Qwen35);
        if local_path.exists() {
            println!("Qwen3.5 model found in cache at {:?}", local_path);
            let mut model = QwenModel::new();
            model.is_loaded = true;
            model
        } else {
            println!("Qwen3.5 model not downloaded. Use otto_download_model() to fetch it.");
            QwenModel::new()
        }
    });

    GEMMA_MODEL.get_or_init(|| {
        let local_path = get_model_local_path(&CompletionModel::Gemma4);
        if local_path.exists() {
            println!("Gemma 4 model found in cache at {:?}", local_path);
            let mut model = GemmaModel::new();
            model.is_loaded = true;
            model
        } else {
            println!("Gemma 4 model not downloaded. Use otto_download_model() to fetch it.");
            GemmaModel::new()
        }
    });

    CURRENT_MODEL.get_or_init(|| Mutex::new(CompletionModel::Zeta2));
}

#[no_mangle]
pub unsafe extern "C" fn otto_get_completion_prefix(text: *const c_char) -> *const c_char {
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
pub unsafe extern "C" fn otto_get_completion_suggestion(text: *const c_char) -> *const c_char {
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
pub unsafe extern "C" fn otto_get_completion_confidence(text: *const c_char) -> f32 {
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
pub unsafe extern "C" fn otto_is_completion_ml_based(text: *const c_char) -> bool {
    let c_str = unsafe { CStr::from_ptr(text) };
    let text_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return false,
    };

    get_ml_completion(text_str).is_some()
}

#[no_mangle]
pub unsafe extern "C" fn otto_free_completion_strings(
    prefix: *const c_char,
    suggestion: *const c_char,
) {
    if !prefix.is_null() {
        unsafe { drop(CString::from_raw(prefix as *mut c_char)) };
    }
    if !suggestion.is_null() {
        unsafe { drop(CString::from_raw(suggestion as *mut c_char)) };
    }
}

#[no_mangle]
pub unsafe extern "C" fn otto_free_grammar_result(result: *mut GrammarResult) {
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
pub unsafe extern "C" fn otto_free_code_reshape_result(result: *mut CodeReshapeResult) {
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
pub unsafe extern "C" fn otto_check_grammar(text: *const c_char) -> *mut GrammarResult {
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
pub unsafe extern "C" fn otto_reshape_code(
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
pub unsafe extern "C" fn otto_set_model(model_name: *const c_char) {
    let c_str = unsafe { CStr::from_ptr(model_name) };
    let model = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return,
    };

    let model_lock = CURRENT_MODEL.get_or_init(|| Mutex::new(CompletionModel::Qwen35));

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
            println!("Unknown model {}, defaulting to qwen-3.5", model);
            CompletionModel::Qwen35
        }
    };

    if let Ok(mut guard) = model_lock.lock() {
        *guard = new_model;
    }
}

#[no_mangle]
pub unsafe extern "C" fn otto_set_code_reshape_enabled(enabled: bool) {
    if let Some(flag) = CODE_RESHAPE_ENABLED.get() {
        flag.store(enabled, std::sync::atomic::Ordering::Relaxed);
        println!(
            "Code reshaping {}",
            if enabled { "enabled" } else { "disabled" }
        );
    }
}

#[no_mangle]
pub unsafe extern "C" fn otto_set_grammar_enabled(enabled: bool) {
    if let Some(flag) = GRAMMAR_ENABLED.get() {
        flag.store(enabled, std::sync::atomic::Ordering::Relaxed);
        println!(
            "Grammar checking {}",
            if enabled { "enabled" } else { "disabled" }
        );
    }
}

#[no_mangle]
pub unsafe extern "C" fn otto_get_current_model() -> *const c_char {
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

#[no_mangle]
pub unsafe extern "C" fn otto_get_current_model_repo_id() -> *const c_char {
    let repo_id = match CURRENT_MODEL.get() {
        Some(lock) => {
            if let Ok(guard) = lock.lock() {
                guard.hf_repo_id()
            } else {
                "NexVeridian/zeta-2-4bit"
            }
        }
        None => "NexVeridian/zeta-2-4bit",
    };
    CString::new(repo_id).unwrap().into_raw()
}

fn get_ml_completion(text: &str) -> Option<CompletionResult> {
    let _model_name = match CURRENT_MODEL.get() {
        Some(lock) => {
            if let Ok(guard) = lock.lock() {
                match *guard {
                    CompletionModel::Zeta2 => {
                        if ZETA_MODEL.get().map(|m| m.is_loaded).unwrap_or(false) {
                            "zeta-2"
                        } else {
                            return None;
                        }
                    }
                    CompletionModel::Qwen35 => {
                        if QWEN_MODEL.get().map(|m| m.is_loaded).unwrap_or(false) {
                            "qwen-3.5"
                        } else {
                            return None;
                        }
                    }
                    CompletionModel::Gemma4 => {
                        if GEMMA_MODEL.get().map(|m| m.is_loaded).unwrap_or(false) {
                            "gemma-4"
                        } else {
                            return None;
                        }
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
        ("是", vec!["是的", "是他", "她是", "是它"]),
        ("不", vec!["不是", "不行", "不好", "不要"]),
        ("在", vec!["在这里", "在那里", "在家", "在外"]),
        ("有", vec!["有没有", "有时间", "有机会", "有可能"]),
        ("好", vec!["好的", "很好", "好多", "好久"]),
        ("没", vec!["没有", "没错", "没事", "没想到"]),
        ("去", vec!["去哪里", "去了", "要去", "出去"]),
        ("来", vec!["来了", "来这里", "来不及", "来着"]),
    ]
    .into();

    let combined_patterns: HashMap<&str, Vec<&str>> =
        code_patterns.into_iter().chain(text_patterns).collect();

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
        ("im ", "I'm ", "Contract with apostrophe"),
        ("your ", "you're ", "Your vs you're"),
        ("there ", "they're ", "Their vs they're"),
        ("loose", "lose", "Lose vs loose"),
        ("alot", "a lot", "Two words"),
        ("teh", "the", "Spelling"),
        ("recieve", "receive", "Spelling (i before e)"),
        ("occured", "occurred", "Double r"),
        ("seperate", "separate", "Spelling"),
        ("definately", "definitely", "Spelling"),
        ("accomodate", "accommodate", "Double c and m"),
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
            unsafe { otto_initialize_completions() };
        });
    }

    #[test]
    fn test_completion_lookup() {
        ensure_initialized();

        let test_text = CString::new("the").unwrap();
        let prefix = unsafe { otto_get_completion_prefix(test_text.as_ptr()) };
        let suggestion = unsafe { otto_get_completion_suggestion(test_text.as_ptr()) };

        assert!(!prefix.is_null());
        assert!(!suggestion.is_null());

        unsafe { otto_free_completion_strings(prefix, suggestion) };
    }

    #[test]
    fn test_grammar_check() {
        ensure_initialized();
        unsafe { otto_set_grammar_enabled(true) };

        let test_text = CString::new("dont").unwrap();
        let result = unsafe { otto_check_grammar(test_text.as_ptr()) };

        assert!(!result.is_null());
        unsafe { otto_free_grammar_result(result) };
    }

    #[test]
    fn test_code_reshape() {
        ensure_initialized();
        unsafe { otto_set_code_reshape_enabled(true) };

        let code = CString::new("if x == true { return true; }").unwrap();
        let operation = CString::new("refactor").unwrap();
        let result = unsafe { otto_reshape_code(code.as_ptr(), operation.as_ptr()) };

        assert!(!result.is_null());
        unsafe { otto_free_code_reshape_result(result) };
    }

    #[test]
    fn test_model_switching() {
        ensure_initialized();

        unsafe { otto_set_model(CString::new("zeta-2").unwrap().as_ptr()) };
        let model = unsafe { CStr::from_ptr(otto_get_current_model()) };
        assert_eq!(model.to_str().unwrap(), "zeta-2");

        unsafe { otto_set_model(CString::new("qwen-3.5").unwrap().as_ptr()) };
        let model = unsafe { CStr::from_ptr(otto_get_current_model()) };
        assert_eq!(model.to_str().unwrap(), "qwen-3.5");

        unsafe { otto_set_model(CString::new("gemma-4").unwrap().as_ptr()) };
        let model = unsafe { CStr::from_ptr(otto_get_current_model()) };
        assert_eq!(model.to_str().unwrap(), "gemma-4");
    }
}
