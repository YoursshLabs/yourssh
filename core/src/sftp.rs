use crate::error::SshError;

pub struct FileEntry {
    pub name: String,
    pub path: String,
    pub is_dir: bool,
    pub size: u64,
    pub modified: u64,
    pub permissions: String,
}

pub struct SftpClient {
    // TODO: hold russh-sftp session handle
}

impl SftpClient {
    pub async fn list_dir(&self, path: String) -> Result<Vec<FileEntry>, SshError> {
        Err(SshError::SftpError("not implemented".into()))
    }

    pub async fn upload(&self, local_path: String, remote_path: String) -> Result<(), SshError> {
        Err(SshError::SftpError("not implemented".into()))
    }

    pub async fn download(&self, remote_path: String, local_path: String) -> Result<(), SshError> {
        Err(SshError::SftpError("not implemented".into()))
    }

    pub async fn remove(&self, path: String) -> Result<(), SshError> {
        Err(SshError::SftpError("not implemented".into()))
    }

    pub async fn mkdir(&self, path: String) -> Result<(), SshError> {
        Err(SshError::SftpError("not implemented".into()))
    }
}
