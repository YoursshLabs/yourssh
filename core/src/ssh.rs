use crate::error::SshError;
use crate::shell::{ShellDelegate, ShellSession};
use async_trait::async_trait;
use russh::client::{self, Handle};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use tokio::sync::Mutex;

pub struct HostConfig {
    pub id: String,
    pub label: String,
    pub host: String,
    pub port: u16,
    pub username: String,
    pub auth: AuthMethod,
}

pub enum AuthMethod {
    Password { password: String },
    PrivateKey { key_id: String },
    Agent,
}

pub struct ExecResult {
    pub stdout: String,
    pub stderr: String,
    pub exit_code: i32,
}

struct ClientHandler;

#[async_trait]
impl client::Handler for ClientHandler {
    type Error = russh::Error;

    async fn check_server_key(
        &mut self,
        _server_public_key: &russh_keys::key::PublicKey,
    ) -> Result<bool, Self::Error> {
        // TODO Sprint 2: implement known_hosts verification
        Ok(true)
    }
}

pub struct SshClient {
    handle: Mutex<Handle<ClientHandler>>,
    connected: AtomicBool,
}

impl SshClient {
    // Return Self (not Arc<Self>) — UniFFI wraps constructor return in Arc automatically
    pub async fn new(config: HostConfig) -> Result<Self, SshError> {
        let russh_config = Arc::new(client::Config::default());
        let addr = format!("{}:{}", config.host, config.port);

        let mut session = client::connect(russh_config, addr, ClientHandler)
            .await
            .map_err(|e| SshError::ConnectionFailed(e.to_string()))?;

        let authenticated = match &config.auth {
            AuthMethod::Password { password } => session
                .authenticate_password(&config.username, password.as_str())
                .await
                .map_err(|e| SshError::AuthFailed(e.to_string()))?,
            AuthMethod::PrivateKey { .. } => {
                return Err(SshError::AuthFailed("Key auth — Sprint 2".into()))
            }
            AuthMethod::Agent => {
                return Err(SshError::AuthFailed("Agent auth — Sprint 2".into()))
            }
        };

        if !authenticated {
            return Err(SshError::AuthFailed("Invalid credentials".into()));
        }

        Ok(Self {
            handle: Mutex::new(session),
            connected: AtomicBool::new(true),
        })
    }

    pub async fn exec(&self, command: String) -> Result<ExecResult, SshError> {
        let mut handle = self.handle.lock().await;
        let mut channel = handle
            .channel_open_session()
            .await
            .map_err(|e| SshError::ChannelError(e.to_string()))?;

        channel
            .exec(true, command.as_bytes())
            .await
            .map_err(|e| SshError::ChannelError(e.to_string()))?;

        let mut stdout = Vec::new();
        let mut stderr = Vec::new();
        let mut exit_code = 0i32;

        loop {
            match channel.wait().await {
                Some(russh::ChannelMsg::Data { ref data }) => {
                    stdout.extend_from_slice(data);
                }
                Some(russh::ChannelMsg::ExtendedData { ref data, ext: 1 }) => {
                    stderr.extend_from_slice(data);
                }
                Some(russh::ChannelMsg::ExitStatus { exit_status }) => {
                    exit_code = exit_status as i32;
                }
                Some(russh::ChannelMsg::Eof) | None => break,
                _ => {}
            }
        }

        Ok(ExecResult {
            stdout: String::from_utf8_lossy(&stdout).into_owned(),
            stderr: String::from_utf8_lossy(&stderr).into_owned(),
            exit_code,
        })
    }

    // Methods returning interface objects must return Arc<T>
    pub async fn open_shell(
        &self,
        cols: u32,
        rows: u32,
        delegate: Box<dyn ShellDelegate>,
    ) -> Result<Arc<ShellSession>, SshError> {
        let mut handle = self.handle.lock().await;
        let mut channel = handle
            .channel_open_session()
            .await
            .map_err(|e| SshError::ChannelError(e.to_string()))?;

        channel
            .request_pty(false, "xterm-256color", cols, rows, 0, 0, &[])
            .await
            .map_err(|e| SshError::ChannelError(e.to_string()))?;

        channel
            .request_shell(false)
            .await
            .map_err(|e| SshError::ChannelError(e.to_string()))?;

        Ok(Arc::new(ShellSession::new(channel, delegate)))
    }

    pub fn disconnect(&self) {
        self.connected.store(false, Ordering::Relaxed);
    }

    pub fn is_connected(&self) -> bool {
        self.connected.load(Ordering::Relaxed)
    }
}
