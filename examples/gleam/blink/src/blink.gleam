import gleam/int
import gleam_avm/atomvm

pub type Uart

@external(erlang, "uart", "open")
fn uart_open(name: String, opts: List(a)) -> Uart

@external(erlang, "uart", "write")
fn uart_write(uart: Uart, data: BitArray) -> Result(Nil, Nil)

@external(erlang, "timer", "sleep")
fn sleep(ms: Int) -> Nil

fn println(uart: Uart, msg: String) {
  let _ = uart_write(uart, <<msg:utf8, "\r\n":utf8>>)
}

pub fn start() {
  main()
}

pub fn main() {
  let serial = uart_open("USB_SERIAL_JTAG", [])
  println(serial, "Blink example on AtomVM / Gleam")
  println(serial, "Platform: " <> platform_name())
  loop(serial, 0)
}

fn loop(serial: Uart, count: Int) {
  let state = case count % 2 {
    0 -> "ON"
    _ -> "OFF"
  }
  println(serial, "[" <> int.to_string(count) <> "] LED: " <> state)
  sleep(1000)
  loop(serial, count + 1)
}

fn platform_name() {
  case atomvm.platform() {
    atomvm.Esp32 -> "ESP32"
    atomvm.GenericUnix -> "GenericUnix"
    atomvm.Emscripten -> "Emscripten"
    atomvm.Pico -> "Pico"
    atomvm.Stm32 -> "STM32"
  }
}
