use crate::error::SshError;
use uuid::Uuid;

pub enum KeyType {
    Ed25519,
    Rsa { bits: u32 },
}

pub struct SshKey {
    pub id: String,
    pub label: String,
    pub key_type: String,
    pub public_key: String,
    pub fingerprint: String,
}

pub struct KeyManager {}

impl KeyManager {
    pub fn new() -> Self {
        Self {}
    }

    pub fn generate(&self, label: String, key_type: KeyType) -> Result<SshKey, SshError> {
        // TODO: implement key generation
        Err(SshError::KeyError("not implemented".into()))
    }

    pub fn import_pem(&self, label: String, pem_content: String) -> Result<SshKey, SshError> {
        Err(SshError::KeyError("not implemented".into()))
    }

    pub fn list_keys(&self) -> Vec<SshKey> {
        vec![]
    }

    pub fn delete_key(&self, key_id: String) -> Result<(), SshError> {
        Err(SshError::KeyError("not implemented".into()))
    }
}
