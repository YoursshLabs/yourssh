use ironrdp::session::{ActiveStage, ActiveStageOutput};
use ironrdp::session::image::DecodedImage;
use ironrdp_cliprdr::CliprdrClient;
use ironrdp_cliprdr::pdu::{ClipboardFormat, ClipboardFormatId, OwnedFormatDataResponse};
use ironrdp_tokio::FramedWrite;
use tokio::sync::mpsc::UnboundedReceiver;

use crate::api::{RdpConfig, RdpEvent};
use crate::clipboard::CliprdrMsg;
use crate::connect::{ConnectOutcome, Connected, rdp_connect_stage};
use crate::input::InputState;
use crate::session::SessionCmd;

/// Largest server-negotiated desktop edge / pixel count accepted. The decoded
/// image allocates `w * h * 4` bytes up front and an allocation failure aborts
/// the whole process, so a hostile server must not choose an unbounded size.
pub const MAX_DESKTOP_EDGE: u32 = 8192;
pub const MAX_DESKTOP_PIXELS: u64 = 8192 * 8192;

/// True when the negotiated desktop size is non-empty and within the caps.
pub fn desktop_size_ok(width: u16, height: u16) -> bool {
    width != 0
        && height != 0
        && u32::from(width) <= MAX_DESKTOP_EDGE
        && u32::from(height) <= MAX_DESKTOP_EDGE
        && u64::from(width) * u64::from(height) <= MAX_DESKTOP_PIXELS
}

/// Copies the `region` rect out of the full RGBA framebuffer into a tight buffer.
pub fn extract_region(fb: &[u8], fb_width: u16, x: u16, y: u16, w: u16, h: u16) -> Vec<u8> {
    let stride = fb_width as usize * 4;
    let mut out = Vec::with_capacity(w as usize * h as usize * 4);
    for row in y as usize..(y as usize + h as usize) {
        let start = row * stride + x as usize * 4;
        out.extend_from_slice(&fb[start..start + w as usize * 4]);
    }
    out
}

/// Converts an IronRDP `InclusiveRectangle` (right/bottom are inclusive — so
/// width = right - left + 1) into a clamped `(x, y, w, h)`. Returns `None`
/// for degenerate/malformed rects instead of underflowing u16 or slicing the
/// framebuffer out of bounds.
pub fn clamp_region(
    left: u16,
    top: u16,
    right: u16,
    bottom: u16,
    img_w: u16,
    img_h: u16,
) -> Option<(u16, u16, u16, u16)> {
    if img_w == 0 || img_h == 0 || right < left || bottom < top {
        return None;
    }
    if left >= img_w || top >= img_h {
        return None;
    }
    let right = right.min(img_w - 1);
    let bottom = bottom.min(img_h - 1);
    Some((left, top, right - left + 1, bottom - top + 1))
}

/// Returns the disconnect reason when an X224 payload is an MCS Disconnect
/// Provider Ultimatum — the server-side session end (remote sign-out, session
/// taken over by another client, admin disconnect). ironrdp-session 0.9's
/// x224 processor surfaces that PDU as a decode *error* instead of a graceful
/// disconnect, so the run loop peeks every X224 frame before handing it to
/// the active stage. Anything that isn't an ultimatum (or doesn't decode)
/// returns `None` and flows through unchanged.
pub fn disconnect_ultimatum_reason(payload: &[u8]) -> Option<&'static str> {
    use ironrdp::pdu::mcs::McsMessage;
    use ironrdp::pdu::x224::X224;
    match ironrdp::core::decode::<X224<McsMessage<'_>>>(payload) {
        Ok(X224(McsMessage::DisconnectProviderUltimatum(msg))) => Some(msg.reason.description()),
        _ => None,
    }
}

pub async fn run_session(
    cfg: RdpConfig,
    mut cmd_rx: UnboundedReceiver<SessionCmd>,
    sink: impl Fn(RdpEvent) + Send + Sync + 'static,
) {
    match run_session_inner(cfg, &mut cmd_rx, &sink).await {
        Ok(reason) => sink(RdpEvent::Disconnected { reason }),
        Err(e) => sink(RdpEvent::Error { message: format!("{e:#}") }),
    }
}

async fn run_session_inner(
    cfg: RdpConfig,
    cmd_rx: &mut UnboundedReceiver<SessionCmd>,
    sink: &(impl Fn(RdpEvent) + Send + Sync),
) -> anyhow::Result<String> {
    let connected = match rdp_connect_stage(&cfg).await? {
        ConnectOutcome::Connected(c) => c,
        ConnectOutcome::CertMismatch { fingerprint } => {
            sink(RdpEvent::CertMismatch { fingerprint });
            anyhow::bail!("server certificate changed — connection aborted before authentication");
        }
    };
    let Connected { mut framed, connection_result, cert, mut cliprdr_rx, clipboard_shared } =
        *connected;
    let (desktop_width, desktop_height) = (
        connection_result.desktop_size.width,
        connection_result.desktop_size.height,
    );
    if !desktop_size_ok(desktop_width, desktop_height) {
        anyhow::bail!(
            "server negotiated an unsupported desktop size {desktop_width}x{desktop_height}"
        );
    }
    sink(RdpEvent::Connected { cert, desktop_width, desktop_height });

    let mut image = DecodedImage::new(
        ironrdp::graphics::image_processing::PixelFormat::RgbA32,
        desktop_width,
        desktop_height,
    );
    let mut active_stage = ActiveStage::new(connection_result);
    let mut input = InputState::new();

    loop {
        let outputs: Vec<ActiveStageOutput> = tokio::select! {
            frame = framed.read_pdu() => {
                let (action, payload) = frame?;
                if action == ironrdp::pdu::Action::X224 {
                    if let Some(reason) = disconnect_ultimatum_reason(&payload) {
                        return Ok(format!("server ended the session ({reason})"));
                    }
                }
                active_stage.process(&mut image, action, &payload)?
            }
            cmd = cmd_rx.recv() => {
                match cmd {
                    None | Some(SessionCmd::Disconnect) => {
                        for out in active_stage.graceful_shutdown()? {
                            if let ActiveStageOutput::ResponseFrame(f) = out {
                                framed.write_all(&f).await?;
                            }
                        }
                        return Ok("disconnected by user".into());
                    }
                    Some(SessionCmd::ClipboardText(text)) => {
                        // Store text and advertise to server.
                        clipboard_shared.lock().unwrap().pending_text = Some(text);
                        if let Some(cliprdr) = active_stage.get_svc_processor_mut::<CliprdrClient>() {
                            let formats = vec![
                                ClipboardFormat::new(ClipboardFormatId::new(13)), // CF_UNICODETEXT
                            ];
                            if let Ok(msgs) = cliprdr.initiate_copy(&formats) {
                                let bytes = active_stage.process_svc_processor_messages(msgs)?;
                                if !bytes.is_empty() {
                                    framed.write_all(&bytes).await?;
                                }
                            }
                        }
                        vec![]
                    }
                    Some(cmd) => input.handle(&mut active_stage, &mut image, cmd)?,
                }
            }
            msg = cliprdr_rx.recv() => {
                match msg {
                    Some(CliprdrMsg::SubmitFormatData { data }) => {
                        if let Some(cliprdr) = active_stage.get_svc_processor_mut::<CliprdrClient>() {
                            let response = OwnedFormatDataResponse::new_data(data);
                            if let Ok(msgs) = cliprdr.submit_format_data(response) {
                                let bytes = active_stage.process_svc_processor_messages(msgs)?;
                                if !bytes.is_empty() {
                                    framed.write_all(&bytes).await?;
                                }
                            }
                        }
                        vec![]
                    }
                    Some(CliprdrMsg::RequestPaste { format_id }) => {
                        if let Some(cliprdr) = active_stage.get_svc_processor_mut::<CliprdrClient>() {
                            if let Ok(msgs) = cliprdr.initiate_paste(ClipboardFormatId::new(format_id)) {
                                let bytes = active_stage.process_svc_processor_messages(msgs)?;
                                if !bytes.is_empty() {
                                    framed.write_all(&bytes).await?;
                                }
                            }
                        }
                        vec![]
                    }
                    Some(CliprdrMsg::InitiateCopy(formats)) => {
                        if let Some(cliprdr) = active_stage.get_svc_processor_mut::<CliprdrClient>() {
                            if let Ok(msgs) = cliprdr.initiate_copy(&formats) {
                                let bytes = active_stage.process_svc_processor_messages(msgs)?;
                                if !bytes.is_empty() {
                                    framed.write_all(&bytes).await?;
                                }
                            }
                        }
                        vec![]
                    }
                    Some(CliprdrMsg::RemoteText(text)) => {
                        sink(RdpEvent::ClipboardText { text });
                        vec![]
                    }
                    None => vec![],
                }
            }
        };

        for out in outputs {
            match out {
                ActiveStageOutput::GraphicsUpdate(region) => {
                    if let Some((x, y, w, h)) = clamp_region(
                        region.left, region.top, region.right, region.bottom,
                        image.width(), image.height(),
                    ) {
                        sink(RdpEvent::FrameUpdate {
                            x, y, width: w, height: h,
                            rgba: extract_region(image.data(), image.width(), x, y, w, h),
                        });
                    }
                }
                ActiveStageOutput::ResponseFrame(frame) => framed.write_all(&frame).await?,
                ActiveStageOutput::Terminate(reason) => return Ok(format!("{reason:?}")),
                _ => {}
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ironrdp::pdu::mcs::{
        DisconnectProviderUltimatum, DisconnectReason, McsMessage, SendDataIndication,
    };
    use ironrdp::pdu::x224::X224;

    #[test]
    fn disconnect_ultimatum_reason_detects_server_session_end() {
        let frame = ironrdp::core::encode_vec(&X224(McsMessage::DisconnectProviderUltimatum(
            DisconnectProviderUltimatum::from_reason(DisconnectReason::UserRequested),
        )))
        .unwrap();
        assert_eq!(
            disconnect_ultimatum_reason(&frame),
            Some("user-requested disconnect")
        );
    }

    #[test]
    fn disconnect_ultimatum_reason_ignores_other_frames() {
        // A regular in-session MCS frame must fall through to the active stage.
        let frame = ironrdp::core::encode_vec(&X224(McsMessage::SendDataIndication(
            SendDataIndication {
                initiator_id: 1002,
                channel_id: 1003,
                user_data: std::borrow::Cow::Owned(vec![1, 2, 3]),
            },
        )))
        .unwrap();
        assert_eq!(disconnect_ultimatum_reason(&frame), None);
        // Undecodable bytes must fall through too (active stage owns the error).
        assert_eq!(disconnect_ultimatum_reason(&[0u8; 4]), None);
    }

    #[test]
    fn desktop_size_ok_rejects_oversized_or_empty() {
        assert!(desktop_size_ok(1920, 1080));
        assert!(desktop_size_ok(8192, 8192));
        assert!(!desktop_size_ok(8193, 100));
        assert!(!desktop_size_ok(100, 8193));
        assert!(!desktop_size_ok(65535, 65535));
        assert!(!desktop_size_ok(0, 600));
    }

    #[test]
    fn extract_region_copies_tight_rect() {
        // 4x2 framebuffer, pixel value = its index
        let fb: Vec<u8> = (0..4 * 2 * 4).map(|i| i as u8).collect();
        let out = extract_region(&fb, 4, 1, 0, 2, 2);
        assert_eq!(out.len(), 2 * 2 * 4);
        assert_eq!(&out[0..4], &fb[4..8]);    // (1,0)
        assert_eq!(&out[8..12], &fb[20..24]); // (1,1)
    }

    #[test]
    fn clamp_region_inclusive_plus_one() {
        // InclusiveRectangle (0,0)-(3,1) on a 4x2 image = the whole image.
        assert_eq!(clamp_region(0, 0, 3, 1, 4, 2), Some((0, 0, 4, 2)));
        // Single pixel: left == right, top == bottom.
        assert_eq!(clamp_region(2, 1, 2, 1, 4, 2), Some((2, 1, 1, 1)));
    }

    #[test]
    fn clamp_region_clamps_to_image_bounds() {
        // right/bottom past the edge are clamped, not sliced out of bounds.
        assert_eq!(clamp_region(2, 0, 10, 5, 4, 2), Some((2, 0, 2, 2)));
    }

    #[test]
    fn clamp_region_rejects_malformed() {
        assert_eq!(clamp_region(3, 0, 1, 1, 4, 2), None); // right < left
        assert_eq!(clamp_region(0, 1, 1, 0, 4, 2), None); // bottom < top
        assert_eq!(clamp_region(4, 0, 5, 1, 4, 2), None); // starts past edge
        assert_eq!(clamp_region(0, 0, 1, 1, 0, 0), None); // empty image
    }
}
