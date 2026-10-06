use crate::utils::{CoreError, Result};
use std::path::PathBuf;
use std::process::Stdio;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::{Child, Command};
use tokio::sync::broadcast;

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum ConnectionStatus {
    Stopped,
    Starting,
    Running,
    Stopping,
    Error(String),
}

pub struct XrayProcessManager {
    core_path: PathBuf,
    status: parking_lot::RwLock<ConnectionStatus>,
    child_handle: parking_lot::Mutex<Option<Child>>,
    log_sender: broadcast::Sender<String>,
    should_run: Arc<AtomicBool>,
}

impl XrayProcessManager {
    pub fn new(core_path: PathBuf) -> Self {
        let (log_sender, _) = broadcast::channel(100);
        Self {
            core_path,
            status: parking_lot::RwLock::new(ConnectionStatus::Stopped),
            child_handle: parking_lot::Mutex::new(None),
            log_sender,
            should_run: Arc::new(AtomicBool::new(false)),
        }
    }

    pub fn get_status(&self) -> ConnectionStatus {
        self.status.read().clone()
    }

    pub fn subscribe_logs(&self) -> broadcast::Receiver<String> {
        self.log_sender.subscribe()
    }

    pub async fn start(&self, config_json_path: PathBuf) -> Result<()> {
        let mut status_lock = self.status.write();
        if *status_lock == ConnectionStatus::Running || *status_lock == ConnectionStatus::Starting {
            return Ok(());
        }

        *status_lock = ConnectionStatus::Starting;
        drop(status_lock);

        // Check if executable exists
        if !self.core_path.exists() {
            let err = format!("Xray core binary not found at {:?}", self.core_path);
            *self.status.write() = ConnectionStatus::Error(err.clone());
            return Err(CoreError::CoreStartError(err));
        }

        let mut cmd = Command::new(&self.core_path);
        cmd.arg("run")
            .arg("-c")
            .arg(config_json_path)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());

        let mut child = cmd.spawn().map_err(|e| {
            let err = format!("Failed to spawn Xray process: {}", e);
            *self.status.write() = ConnectionStatus::Error(err.clone());
            CoreError::CoreStartError(err)
        })?;

        self.should_run.store(true, Ordering::SeqCst);
        *self.status.write() = ConnectionStatus::Running;

        // Capture stdout & stderr with sensitive info filtering
        if let Some(stdout) = child.stdout.take() {
            let log_tx = self.log_sender.clone();
            tokio::spawn(async move {
                let mut reader = BufReader::new(stdout).lines();
                while let Ok(Some(line)) = reader.next_line().await {
                    let sanitized = sanitize_log(&line);
                    let _ = log_tx.send(sanitized);
                }
            });
        }

        if let Some(stderr) = child.stderr.take() {
            let log_tx = self.log_sender.clone();
            tokio::spawn(async move {
                let mut reader = BufReader::new(stderr).lines();
                while let Ok(Some(line)) = reader.next_line().await {
                    let sanitized = sanitize_log(&line);
                    let _ = log_tx.send(sanitized);
                }
            });
        }

        *self.child_handle.lock() = Some(child);
        Ok(())
    }

    pub async fn stop(&self) -> Result<()> {
        *self.status.write() = ConnectionStatus::Stopping;
        self.should_run.store(false, Ordering::SeqCst);

        let mut child_opt = self.child_handle.lock().take();
        if let Some(mut child) = child_opt.take() {
            let _ = child.kill().await;
        }

        *self.status.write() = ConnectionStatus::Stopped;
        Ok(())
    }
}

/// Strip potential UUIDs, tokens or secrets from logs before passing to UI
fn sanitize_log(input: &str) -> String {
    let re_uuid = regex::Regex::new(r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}").unwrap();
    let sanitized = re_uuid.replace_all(input, "[REDACTED_UUID]");
    sanitized.to_string()
}
