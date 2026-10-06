use thiserror::Error;

#[derive(Error, Debug, Clone, serde::Serialize, serde::Deserialize)]
pub enum CoreError {
    #[error("Invalid configuration: {0}")]
    InvalidConfig(String),

    #[error("Parse error: {0}")]
    ParseError(String),

    #[error("Network error: {0}")]
    NetworkError(String),

    #[error("Timeout error: {0}")]
    Timeout(String),

    #[error("Core start error: {0}")]
    CoreStartError(String),

    #[error("Permission error: {0}")]
    PermissionError(String),

    #[error("Scanner error: {0}")]
    ScannerError(String),

    #[error("Storage error: {0}")]
    StorageError(String),

    #[error("IO error: {0}")]
    Io(String),

    #[error("Unknown error: {0}")]
    Unknown(String),
}

pub type Result<T> = std::result::Result<T, CoreError>;
