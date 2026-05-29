use thiserror::Error;

#[derive(Debug, Error)]
pub enum SshError {
    #[error("Connection failed: {0}")]
    ConnectionFailed(String),
    #[error("Authentication failed: {0}")]
    AuthFailed(String),
    #[error("Timed out")]
    Timeout,
    #[error("Channel error: {0}")]
    ChannelError(String),
    #[error("SFTP error: {0}")]
    SftpError(String),
    #[error("Key error: {0}")]
    KeyError(String),
    #[error("Vault error: {0}")]
    VaultError(String),
}
