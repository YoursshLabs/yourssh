use crate::error::SshError;
use russh::{client, Channel, ChannelMsg};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use tokio::sync::Mutex;

pub trait ShellDelegate: Send + Sync {
    fn on_data(&self, data: Vec<u8>);
    fn on_disconnect(&self);
    fn on_error(&self, message: String);
}

// Inner state shared between ShellSession and the background reader task
struct Inner {
    channel: Mutex<Channel<client::Msg>>,
    delegate: Arc<dyn ShellDelegate>,
    closed: AtomicBool,
}

pub struct ShellSession {
    inner: Arc<Inner>,
}

impl ShellSession {
    pub fn new(channel: Channel<client::Msg>, delegate: Box<dyn ShellDelegate>) -> Self {
        let delegate: Arc<dyn ShellDelegate> = Arc::from(delegate);
        let inner = Arc::new(Inner {
            channel: Mutex::new(channel),
            delegate,
            closed: AtomicBool::new(false),
        });

        // Spawn background reader task
        let inner_reader = inner.clone();
        tokio::spawn(async move {
            loop {
                let msg = inner_reader.channel.lock().await.wait().await;
                match msg {
                    Some(ChannelMsg::Data { ref data }) => {
                        inner_reader.delegate.on_data(data.to_vec());
                    }
                    Some(ChannelMsg::ExtendedData { ref data, .. }) => {
                        inner_reader.delegate.on_data(data.to_vec());
                    }
                    Some(ChannelMsg::Eof) | None => {
                        inner_reader.closed.store(true, Ordering::Relaxed);
                        inner_reader.delegate.on_disconnect();
                        break;
                    }
                    _ => {}
                }
            }
        });

        Self { inner }
    }

    pub async fn write_data(&self, data: Vec<u8>) -> Result<(), SshError> {
        if self.inner.closed.load(Ordering::Relaxed) {
            return Err(SshError::ChannelError("Session closed".into()));
        }
        self.inner
            .channel
            .lock()
            .await
            .data(data.as_ref())
            .await
            .map_err(|e| SshError::ChannelError(e.to_string()))
    }

    pub async fn resize(&self, cols: u32, rows: u32) -> Result<(), SshError> {
        self.inner
            .channel
            .lock()
            .await
            .window_change(cols, rows, 0, 0)
            .await
            .map_err(|e| SshError::ChannelError(e.to_string()))
    }

    pub fn close(&self) {
        self.inner.closed.store(true, Ordering::Relaxed);
    }
}
