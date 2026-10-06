use crate::config::models::ProxyNode;
use crate::config::ConfigParser;
use crate::scanner::models::{ScannerEvent, ScannerOptions};
use crate::scanner::ScannerEngine;
use crate::storage::SecureStore;
use crate::utils::cloudflare_ranges::CloudflareDetector;
use crate::xray::{ConnectionStatus, XrayProcessManager};
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::runtime::Runtime;
use tokio::sync::mpsc;

pub struct CoreContext {
    runtime: Runtime,
    store: Arc<parking_lot::Mutex<Option<SecureStore>>>,
    scanner: Arc<ScannerEngine>,
    process_mgr: Arc<parking_lot::Mutex<Option<XrayProcessManager>>>,
    detector: CloudflareDetector,
}

lazy_static::lazy_static! {
    static ref CTX: CoreContext = {
        let rt = Runtime::new().expect("Failed to create Tokio runtime");
        CoreContext {
            runtime: rt,
            store: Arc::new(parking_lot::Mutex::new(None)),
            scanner: Arc::new(ScannerEngine::new()),
            process_mgr: Arc::new(parking_lot::Mutex::new(None)),
            detector: CloudflareDetector::new(),
        }
    };
}

// Global Callback Type for Flutter FFI Event Streaming
pub type NativeEventCallback = extern "C" fn(event_json: *const c_char);
static EVENT_CALLBACK: parking_lot::RwLock<Option<NativeEventCallback>> = parking_lot::RwLock::new(None);

#[no_mangle]
pub extern "C" fn v2raypro_register_event_callback(cb: NativeEventCallback) {
    *EVENT_CALLBACK.write() = Some(cb);
}

fn emit_event(event_type: &str, payload: serde_json::Value) {
    if let Some(cb) = *EVENT_CALLBACK.read() {
        let wrapper = serde_json::json!({
            "type": event_type,
            "data": payload
        });
        if let Ok(c_str) = CString::new(wrapper.to_string()) {
            cb(c_str.as_ptr());
        }
    }
}

#[no_mangle]
pub extern "C" fn v2raypro_init(data_dir: *const c_char, xray_bin: *const c_char) -> bool {
    let data_path = match unsafe { c_str_to_string(data_dir) } {
        Some(s) => PathBuf::from(s).join("app_data.json"),
        None => return false,
    };
    let xray_path = match unsafe { c_str_to_string(xray_bin) } {
        Some(s) => PathBuf::from(s),
        None => PathBuf::from("xray"),
    };

    if let Ok(store) = SecureStore::open(data_path) {
        *CTX.store.lock() = Some(store);
    }
    *CTX.process_mgr.lock() = Some(XrayProcessManager::new(xray_path));
    true
}

#[no_mangle]
pub extern "C" fn v2raypro_import_config(config_str: *const c_char) -> *mut c_char {
    let raw = match unsafe { c_str_to_string(config_str) } {
        Some(s) => s,
        None => return string_to_c_char("{\"error\":\"Empty string\"}"),
    };

    match ConfigParser::parse(&raw) {
        Ok(node) => {
            if let Some(store) = CTX.store.lock().as_mut() {
                let _ = store.add_node(node.clone());
            }
            let res = serde_json::json!({ "success": true, "node": node });
            string_to_c_char(&res.to_string())
        }
        Err(e) => {
            let res = serde_json::json!({ "success": false, "error": e.to_string() });
            string_to_c_char(&res.to_string())
        }
    }
}

#[no_mangle]
pub extern "C" fn v2raypro_import_batch(content: *const c_char) -> *mut c_char {
    let raw = match unsafe { c_str_to_string(content) } {
        Some(s) => s,
        None => return string_to_c_char("{\"nodes\":[]}"),
    };

    let nodes = ConfigParser::parse_batch(&raw);
    if let Some(store) = CTX.store.lock().as_mut() {
        for n in &nodes {
            let _ = store.add_node(n.clone());
        }
    }
    let res = serde_json::json!({ "success": true, "count": nodes.len(), "nodes": nodes });
    string_to_c_char(&res.to_string())
}

#[no_mangle]
pub extern "C" fn v2raypro_get_nodes() -> *mut c_char {
    let nodes = CTX.store.lock().as_ref().map(|s| s.get_nodes()).unwrap_or_default();
    let res = serde_json::json!({ "nodes": nodes });
    string_to_c_char(&res.to_string())
}

#[no_mangle]
pub extern "C" fn v2raypro_delete_node(id: *const c_char) -> bool {
    let id_str = match unsafe { c_str_to_string(id) } {
        Some(s) => s,
        None => return false,
    };
    if let Some(store) = CTX.store.lock().as_mut() {
        return store.remove_node(&id_str).is_ok();
    }
    false
}

#[no_mangle]
pub extern "C" fn v2raypro_start_scan(options_json: *const c_char) -> bool {
    let raw = match unsafe { c_str_to_string(options_json) } {
        Some(s) => s,
        None => return false,
    };

    let options: ScannerOptions = match serde_json::from_str(&raw) {
        Ok(opt) => opt,
        Err(_) => return false,
    };

    let scanner = CTX.scanner.clone();
    let (tx, mut rx) = mpsc::channel::<ScannerEvent>(100);

    // Spawn event bridge from Tokio channel to Flutter FFI
    CTX.runtime.spawn(async move {
        while let Some(evt) = rx.recv().await {
            match evt {
                ScannerEvent::Started { total_candidates } => {
                    emit_event("ScanStarted", serde_json::json!({ "total": total_candidates }));
                }
                ScannerEvent::Progress { scanned, total, current_ip } => {
                    emit_event("ScanProgress", serde_json::json!({ "scanned": scanned, "total": total, "current_ip": current_ip }));
                }
                ScannerEvent::Result(res) => {
                    emit_event("ScanResult", serde_json::to_value(res).unwrap_or_default());
                }
                ScannerEvent::Finished { total_tested, successful_count, best_ip } => {
                    emit_event("ScanFinished", serde_json::json!({
                        "total_tested": total_tested,
                        "successful_count": successful_count,
                        "best_ip": best_ip
                    }));
                }
                ScannerEvent::Cancelled => {
                    emit_event("ScanCancelled", serde_json::json!({}));
                }
                ScannerEvent::Error(err) => {
                    emit_event("ScanError", serde_json::json!({ "error": err }));
                }
            }
        }
    });

    CTX.runtime.spawn(async move {
        scanner.run_scan(options, tx).await;
    });

    true
}

#[no_mangle]
pub extern "C" fn v2raypro_cancel_scan() {
    CTX.scanner.cancel();
}

#[no_mangle]
pub extern "C" fn v2raypro_apply_ip_to_node(node_id: *const c_char, new_ip: *const c_char) -> *mut c_char {
    let nid = match unsafe { c_str_to_string(node_id) } {
        Some(s) => s,
        None => return string_to_c_char("{\"error\":\"Invalid ID\"}"),
    };
    let nip = match unsafe { c_str_to_string(new_ip) } {
        Some(s) => s,
        None => return string_to_c_char("{\"error\":\"Invalid IP\"}"),
    };

    let mut store_lock = CTX.store.lock();
    if let Some(store) = store_lock.as_mut() {
        let mut nodes = store.get_nodes();
        if let Some(node) = nodes.iter_mut().find(|n| n.id == nid) {
            // Backup original address if not already backed up
            if node.original_address.is_none() {
                node.original_address = Some(node.address.clone());
            }
            node.address = nip.clone();
            let _ = store.update_node(node.clone());
            let res = serde_json::json!({ "success": true, "node": node });
            return string_to_c_char(&res.to_string());
        }
    }
    string_to_c_char("{\"error\":\"Node not found\"}")
}

#[no_mangle]
pub extern "C" fn v2raypro_restore_node_address(node_id: *const c_char) -> *mut c_char {
    let nid = match unsafe { c_str_to_string(node_id) } {
        Some(s) => s,
        None => return string_to_c_char("{\"error\":\"Invalid ID\"}"),
    };

    let mut store_lock = CTX.store.lock();
    if let Some(store) = store_lock.as_mut() {
        let mut nodes = store.get_nodes();
        if let Some(node) = nodes.iter_mut().find(|n| n.id == nid) {
            if let Some(orig) = node.original_address.take() {
                node.address = orig;
                let _ = store.update_node(node.clone());
                let res = serde_json::json!({ "success": true, "node": node });
                return string_to_c_char(&res.to_string());
            }
        }
    }
    string_to_c_char("{\"error\":\"No original address to restore\"}")
}

#[no_mangle]
pub extern "C" fn v2raypro_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

unsafe fn c_str_to_string(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    CStr::from_ptr(ptr).to_str().ok().map(|s| s.to_string())
}

fn string_to_c_char(s: &str) -> *mut c_char {
    CString::new(s).unwrap_or_default().into_raw()
}
