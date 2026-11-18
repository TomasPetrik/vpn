//! C FFI around the wstunnel 10.5.2 client for iOS PacketTunnel / Android VpnService.
//!
//! Config JSON (UTF-8):
//! ```json
//! {
//!   "server_ip": "72.61.158.103",
//!   "tls_sni": "vpn.radarcut.com",
//!   "path_prefix": "...",
//!   "remote": "127.0.0.1:51821",
//!   "local_udp": "127.0.0.1:51820",
//!   "url": "wss://vpn.radarcut.com"
//! }
//! ```

#[cfg(target_os = "android")]
mod android_jni;

use once_cell::sync::Lazy;
use serde::Deserialize;
use std::ffi::{CStr, CString};
use std::net::SocketAddr;
use std::os::raw::{c_char, c_int};
use std::sync::Mutex;
use std::sync::mpsc;
use std::thread::{self, JoinHandle};
use std::time::Duration;
use tokio::runtime::Runtime;
use tokio::sync::oneshot;
use tracing::{error, info};
use url::{Host, Url};
use wstunnel::config::{Client, HeaderValue, LocalToRemote};
use wstunnel::executor::DefaultTokioExecutor;
use wstunnel::tunnel::LocalProtocol;
use wstunnel::run_client;

static STATE: Lazy<Mutex<Option<ClientHandle>>> = Lazy::new(|| Mutex::new(None));

struct ClientHandle {
    stop_tx: Option<oneshot::Sender<()>>,
    join: Option<JoinHandle<()>>,
}

#[derive(Debug, Deserialize)]
struct FfiConfig {
    server_ip: String,
    #[serde(default)]
    tls_sni: Option<String>,
    path_prefix: String,
    remote: String,
    #[serde(default = "default_local_udp")]
    local_udp: String,
    #[serde(default)]
    url: Option<String>,
    #[serde(default)]
    tls_verify_certificate: Option<bool>,
}

fn default_local_udp() -> String {
    "127.0.0.1:51820".to_string()
}

fn write_err(buf: *mut c_char, len: usize, msg: &str) {
    if buf.is_null() || len == 0 {
        return;
    }
    let c = CString::new(msg.replace('\0', "")).unwrap_or_else(|_| CString::new("error").unwrap());
    let bytes = c.as_bytes_with_nul();
    let n = bytes.len().min(len);
    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), buf as *mut u8, n);
        if len > 0 {
            *buf.add(len - 1) = 0;
        }
    }
}

fn parse_host_port(s: &str) -> anyhow::Result<(Host, u16)> {
    let addr: SocketAddr = s
        .parse()
        .map_err(|e| anyhow::anyhow!("invalid host:port {s}: {e}"))?;
    match addr.ip() {
        std::net::IpAddr::V4(ip) => Ok((Host::Ipv4(ip), addr.port())),
        std::net::IpAddr::V6(ip) => Ok((Host::Ipv6(ip), addr.port())),
    }
}

fn build_client(cfg: &FfiConfig) -> anyhow::Result<Client> {
    let sni_host = cfg
        .tls_sni
        .clone()
        .or_else(|| {
            cfg.url.as_ref().and_then(|u| {
                Url::parse(u)
                    .ok()
                    .and_then(|url| url.host_str().map(|h| h.to_string()))
            })
        })
        .unwrap_or_else(|| "vpn.radarcut.com".to_string());

    let remote_url = Url::parse(&format!("wss://{}", cfg.server_ip.trim()))
        .map_err(|e| anyhow::anyhow!("bad server_ip url: {e}"))?;

    let local: SocketAddr = cfg
        .local_udp
        .parse()
        .map_err(|e| anyhow::anyhow!("bad local_udp: {e}"))?;
    let remote = parse_host_port(cfg.remote.trim())?;

    let path = cfg.path_prefix.trim().trim_matches('/').to_string();
    if path.is_empty() {
        anyhow::bail!("path_prefix required");
    }

    let sni = rustls_pki_types::DnsName::try_from(sni_host.as_str())
        .map_err(|_| anyhow::anyhow!("bad tls_sni"))?
        .to_owned();

    let host_header =
        HeaderValue::from_str(&sni_host).map_err(|e| anyhow::anyhow!("bad Host header: {e}"))?;

    Ok(Client {
        local_to_remote: vec![LocalToRemote {
            local_protocol: LocalProtocol::Udp {
                // None = disable idle timeout (matches CLI timeout_sec=0).
                timeout: None,
            },
            local,
            remote,
        }],
        remote_to_local: vec![],
        socket_so_mark: None,
        connection_min_idle: 0,
        connection_retry_max_backoff: Duration::from_secs(30),
        reverse_tunnel_connection_retry_max_backoff: Duration::from_secs(1),
        tls_sni_override: Some(sni),
        tls_sni_disable: false,
        tls_ech_enable: false,
        // Default true: vendored wstunnel loads webpki-roots so NE trust works.
        tls_verify_certificate: cfg.tls_verify_certificate.unwrap_or(true),
        http_proxy: None,
        http_proxy_login: None,
        http_proxy_password: None,
        http_upgrade_path_prefix: path,
        http_upgrade_credentials: None,
        websocket_ping_frequency: Some(Duration::from_secs(30)),
        websocket_mask_frame: false,
        http_headers: vec![(wstunnel::config::HeaderName::from_static("host"), host_header)],
        http_headers_file: None,
        remote_addr: remote_url,
        tls_certificate: None,
        tls_private_key: None,
        dns_resolver: vec![],
        dns_resolver_prefer_ipv4: true,
    })
}

/// Start the wstunnel client. Returns 0 on success, non-zero on error.
#[no_mangle]
pub extern "C" fn wstunnel_client_start(
    config_json: *const c_char,
    err_buf: *mut c_char,
    err_len: usize,
) -> c_int {
    if config_json.is_null() {
        write_err(err_buf, err_len, "config_json is null");
        return 1;
    }
    let json = unsafe { CStr::from_ptr(config_json) }.to_string_lossy();
    let cfg: FfiConfig = match serde_json::from_str(&json) {
        Ok(c) => c,
        Err(e) => {
            write_err(err_buf, err_len, &format!("config parse: {e}"));
            return 2;
        }
    };
    let client = match build_client(&cfg) {
        Ok(c) => c,
        Err(e) => {
            write_err(err_buf, err_len, &format!("{e:#}"));
            return 3;
        }
    };

    let mut guard = match STATE.lock() {
        Ok(g) => g,
        Err(_) => {
            write_err(err_buf, err_len, "state lock poisoned");
            return 8;
        }
    };
    if guard.is_some() {
        write_err(err_buf, err_len, "already running");
        return 4;
    }

    let (stop_tx, stop_rx) = oneshot::channel::<()>();
    let (ready_tx, ready_rx) = mpsc::channel::<Result<(), String>>();

    let join = thread::Builder::new()
        .name("wstunnel-client".into())
        .spawn(move || {
            let _ = std::env::set_var("TOKIO_WORKER_THREADS", "2");
            let _ = tracing_subscriber::fmt()
                .with_max_level(tracing::Level::INFO)
                .with_ansi(false)
                .try_init();

            let rt = match Runtime::new() {
                Ok(rt) => rt,
                Err(e) => {
                    let _ = ready_tx.send(Err(format!("runtime: {e}")));
                    return;
                }
            };

            rt.block_on(async move {
                info!("wstunnel_ffi: starting client");
                let exec = DefaultTokioExecutor::default();
                let mut client_fut = Box::pin(run_client(client, exec));
                // Wait until UDP listener is up before telling the host we are ready.
                tokio::select! {
                    res = &mut client_fut => {
                        let msg = match res {
                            Ok(()) => "client exited before ready".to_string(),
                            Err(e) => format!("client failed before ready: {e:#}"),
                        };
                        error!("wstunnel_ffi: {msg}");
                        let _ = ready_tx.send(Err(msg));
                        return;
                    }
                    _ = tokio::time::sleep(Duration::from_millis(600)) => {
                        info!("wstunnel_ffi: ready (udp should be bound)");
                        let _ = ready_tx.send(Ok(()));
                    }
                }
                tokio::select! {
                    res = client_fut => {
                        if let Err(e) = res {
                            error!("wstunnel_ffi: client exited with error: {e:#}");
                        } else {
                            info!("wstunnel_ffi: client exited");
                        }
                    }
                    _ = stop_rx => {
                        info!("wstunnel_ffi: stop requested");
                    }
                }
            });
        });

    let join = match join {
        Ok(j) => j,
        Err(e) => {
            write_err(err_buf, err_len, &format!("spawn: {e}"));
            return 5;
        }
    };

    match ready_rx.recv_timeout(Duration::from_secs(5)) {
        Ok(Ok(())) => {}
        Ok(Err(e)) => {
            let _ = join.join();
            write_err(err_buf, err_len, &e);
            return 6;
        }
        Err(_) => {
            write_err(err_buf, err_len, "start timeout waiting for runtime");
            *guard = Some(ClientHandle {
                stop_tx: Some(stop_tx),
                join: Some(join),
            });
            return 7;
        }
    }

    *guard = Some(ClientHandle {
        stop_tx: Some(stop_tx),
        join: Some(join),
    });
    0
}

/// Stop the client if running.
#[no_mangle]
pub extern "C" fn wstunnel_client_stop() {
    let mut guard = match STATE.lock() {
        Ok(g) => g,
        Err(_) => return,
    };
    if let Some(mut h) = guard.take() {
        if let Some(tx) = h.stop_tx.take() {
            let _ = tx.send(());
        }
        if let Some(join) = h.join.take() {
            let _ = join.join();
        }
    }
}

/// Returns 1 if a client handle is held, else 0.
#[no_mangle]
pub extern "C" fn wstunnel_client_is_running() -> c_int {
    match STATE.lock() {
        Ok(g) => {
            if g.is_some() {
                1
            } else {
                0
            }
        }
        Err(_) => 0,
    }
}
