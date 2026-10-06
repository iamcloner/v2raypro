use crate::config::models::{ProxyNode, Subscription};
use crate::utils::{CoreError, Result};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

#[derive(Debug, Default, Clone, Serialize, Deserialize)]
pub struct AppData {
    pub nodes: Vec<ProxyNode>,
    pub subscriptions: Vec<Subscription>,
    pub active_node_id: Option<String>,
    pub settings: serde_json::Value,
}

pub struct SecureStore {
    file_path: PathBuf,
    data: parking_lot::RwLock<AppData>,
}

impl SecureStore {
    pub fn open(file_path: PathBuf) -> Result<Self> {
        let data = if file_path.exists() {
            let content = fs::read_to_string(&file_path)
                .map_err(|e| CoreError::StorageError(format!("Read failed: {}", e)))?;
            serde_json::from_str(&content).unwrap_or_default()
        } else {
            AppData::default()
        };

        Ok(Self {
            file_path,
            data: parking_lot::RwLock::new(data),
        })
    }

    pub fn save(&self) -> Result<()> {
        let data = self.data.read();
        let content = serde_json::to_string_pretty(&*data)
            .map_err(|e| CoreError::StorageError(format!("Serialize failed: {}", e)))?;
        
        if let Some(parent) = self.file_path.parent() {
            let _ = fs::create_dir_all(parent);
        }

        fs::write(&self.file_path, content)
            .map_err(|e| CoreError::StorageError(format!("Write failed: {}", e)))?;
        Ok(())
    }

    pub fn get_nodes(&self) -> Vec<ProxyNode> {
        self.data.read().nodes.clone()
    }

    pub fn add_node(&self, node: ProxyNode) -> Result<()> {
        self.data.write().nodes.push(node);
        self.save()
    }

    pub fn update_node(&self, node: ProxyNode) -> Result<()> {
        let mut data = self.data.write();
        if let Some(pos) = data.nodes.iter().position(|n| n.id == node.id) {
            data.nodes[pos] = node;
        }
        drop(data);
        self.save()
    }

    pub fn remove_node(&self, id: &str) -> Result<()> {
        let mut data = self.data.write();
        data.nodes.retain(|n| n.id != id);
        if data.active_node_id.as_deref() == Some(id) {
            data.active_node_id = None;
        }
        drop(data);
        self.save()
    }

    pub fn set_active_node(&self, id: Option<String>) -> Result<()> {
        let mut data = self.data.write();
        for node in &mut data.nodes {
            node.is_active = id.as_ref() == Some(&node.id);
        }
        data.active_node_id = id;
        drop(data);
        self.save()
    }

    pub fn get_active_node(&self) -> Option<ProxyNode> {
        let data = self.data.read();
        data.active_node_id.as_ref().and_then(|id| {
            data.nodes.iter().find(|n| &n.id == id).cloned()
        })
    }
}
