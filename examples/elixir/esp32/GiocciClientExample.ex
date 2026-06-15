defmodule GiocciClientExample do
  # Module defined on the ESP32 side and uploaded to GiocciEngine at runtime
  # via save_module. Functions run on the engine (standard Elixir/Erlang).
  # Must use only standard OTP — no AtomVM-specific NIFs.

  def hello, do: :world
  def hello(name), do: "Hello from AtomVM to #{name}!!"

  def add(a, b), do: a + b
  def multiply(a, b), do: a * b

  def fib(0), do: 0
  def fib(1), do: 1
  def fib(n) when n > 1, do: fib(n - 1) + fib(n - 2)

  def celsius_to_fahrenheit(c), do: c * 9 / 5 + 32
end
