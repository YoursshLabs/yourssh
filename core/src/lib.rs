pub mod error;
pub mod ssh;
pub mod shell;
pub mod sftp;
pub mod tunnel;
pub mod keys;

pub use error::SshError;
pub use ssh::{SshClient, HostConfig, AuthMethod, ExecResult};
pub use shell::{ShellSession, ShellDelegate};
pub use sftp::{SftpClient, FileEntry};
pub use tunnel::{Tunnel, TunnelConfig};
pub use keys::{KeyManager, SshKey, KeyType};

uniffi::include_scaffolding!("yourssh");
