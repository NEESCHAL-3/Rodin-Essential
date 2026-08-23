use rodin_essential_backend::{
    PROTOCOL_VERSION, SOCKET_NAME, accept_stream, bind_listener, serve_client,
    start_background_services,
};

fn main() {
    eprintln!("RODIN_ESSENTIALD_START protocol={PROTOCOL_VERSION} socket=@{SOCKET_NAME}");
    let listener = match bind_listener(SOCKET_NAME) {
        Ok(fd) => fd,
        Err(e) => {
            eprintln!("RODIN_ESSENTIALD_BIND_FAIL {e}");
            return;
        }
    };
    start_background_services();
    eprintln!("RODIN_ESSENTIALD_READY protocol={PROTOCOL_VERSION} socket=@{SOCKET_NAME}");
    loop {
        match accept_stream(listener) {
            Ok(stream) => {
                std::thread::spawn(move || serve_client(stream));
            }
            Err(e) => {
                eprintln!("RODIN_ESSENTIALD_ACCEPT_FAIL {e}");
                std::thread::sleep(std::time::Duration::from_millis(100));
            }
        }
    }
}
