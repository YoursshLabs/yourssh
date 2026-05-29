use crate::error::SshError;
use std::sync::Mutex;

pub struct TunnelConfig {
    pub local_port: u16,
    pub remote_host: String,
    pub remote_port: u16,
}

pub struct Tunnel {
    config: TunnelConfig,
    running: Mutex<bool>,
}

impl Tunnel {
    pub fn stop(&self) {
        if let Ok(mut r) = self.running.lock() {
            *r = false;
        }
    }

    pub fn is_running(&self) -> bool {
        self.running.lock().map(|r| *r).unwrap_or(false)
    }

    pub fn local_port(&self) -> u16 {
        self.config.local_port
    }
}
