use crate::error::SshError;

// Encrypted local storage for host configs and credentials
// Uses `age` crate for encryption

pub struct Vault {
    path: std::path::PathBuf,
}

impl Vault {
    pub fn open(path: std::path::PathBuf, passphrase: &str) -> Result<Self, SshError> {
        Ok(Self { path })
    }

    pub fn save_raw(&self, key: &str, data: &[u8]) -> Result<(), SshError> {
        Err(SshError::VaultError("not implemented".into()))
    }

    pub fn load_raw(&self, key: &str) -> Result<Vec<u8>, SshError> {
        Err(SshError::VaultError("not implemented".into()))
    }
}
