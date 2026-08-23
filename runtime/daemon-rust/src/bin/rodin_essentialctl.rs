use rodin_essential_backend::{SOCKET_NAME, connect_stream};
use std::io::{Read, Write};

fn main() {
    let command = std::env::args().skip(1).collect::<Vec<_>>().join(" ");
    if command.is_empty() {
        eprintln!("usage: rodin_essentialctl <command>");
        return;
    }
    let mut stream = match connect_stream(SOCKET_NAME) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("ERR {e}");
            return;
        }
    };
    if let Err(e) = stream.write_all(command.as_bytes()) {
        eprintln!("ERR write: {e}");
        return;
    }
    let mut response = String::new();
    if let Err(e) = stream.read_to_string(&mut response) {
        eprintln!("ERR read: {e}");
        return;
    }
    print!("{response}");
}
