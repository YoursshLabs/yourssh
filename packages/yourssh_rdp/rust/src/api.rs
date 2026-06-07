pub fn rdp_lib_version() -> String {
    format!("yourssh_rdp {}", env!("CARGO_PKG_VERSION"))
}
