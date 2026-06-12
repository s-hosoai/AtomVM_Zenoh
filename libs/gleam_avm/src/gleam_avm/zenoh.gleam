// Zenoh pub/sub bindings for AtomVM via NIF.
// WiFi must be connected before calling open/1.
// Endpoint format: "tcp/<router_ip>:7447"

pub type Session
pub type Publisher
pub type Subscriber

@external(erlang, "zenoh", "open")
pub fn open(endpoint: String) -> Result(Session, Nil)

@external(erlang, "zenoh", "close")
pub fn close(session: Session) -> Nil

@external(erlang, "zenoh", "put")
pub fn put(session: Session, keyexpr: String, payload: BitArray) -> Result(Nil, Nil)

@external(erlang, "zenoh", "declare_publisher")
pub fn declare_publisher(session: Session, keyexpr: String) -> Result(Publisher, Nil)

@external(erlang, "zenoh", "publisher_put")
pub fn publisher_put(publisher: Publisher, payload: BitArray) -> Result(Nil, Nil)

@external(erlang, "zenoh", "undeclare_publisher")
pub fn undeclare_publisher(publisher: Publisher) -> Nil

@external(erlang, "zenoh", "declare_subscriber")
pub fn declare_subscriber(session: Session, keyexpr: String) -> Result(Subscriber, Nil)

@external(erlang, "zenoh", "subscriber_recv")
pub fn subscriber_recv_raw(subscriber: Subscriber, timeout_ms: Int) -> Result(#(BitArray, BitArray), Nil)

/// Receive a message from a subscriber, returning {keyexpr_string, payload_bytes}.
/// timeout_ms: -1 blocks forever, 0 returns immediately, >0 waits up to N ms.
pub fn subscriber_recv(subscriber: Subscriber, timeout_ms: Int) -> Result(#(String, BitArray), Nil) {
  case subscriber_recv_raw(subscriber, timeout_ms) {
    Ok(#(ke_bytes, payload)) -> {
      case bit_array_to_string(ke_bytes) {
        Ok(ke_str) -> Ok(#(ke_str, payload))
        Error(_) -> Error(Nil)
      }
    }
    Error(e) -> Error(e)
  }
}

@external(erlang, "zenoh", "undeclare_subscriber")
pub fn undeclare_subscriber(subscriber: Subscriber) -> Nil

@external(erlang, "unicode", "characters_to_binary")
fn bit_array_to_string(data: BitArray) -> Result(String, Nil)
