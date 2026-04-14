uniffi::include_scaffolding!("test");

pub struct Test;

#[uniffi::export]
impl Test {
    #[uniffi::constructor]
    pub fn new() -> Self {
        Self
    }

    pub fn hello(&self) -> String {
        "Hello from Rust!".to_string()
    }
}
