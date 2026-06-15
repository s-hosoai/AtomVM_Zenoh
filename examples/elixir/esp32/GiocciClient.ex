defmodule GiocciClient do
  @compile {:no_warn_undefined, [Zenoh, :network, EspConfig]}

  # Giocci client port for AtomVM (ESP32).
  # Mirrors giocci_example (https://github.com/biyooon-ex/giocci_example).
  #
  # Supported: register_client/4, exec_func/5
  # Not supported on AtomVM (use PC-side Giocci client instead):
  #   - save_module     — requires :code.get_object_code/1
  #   - exec_func_async — requires Task.Supervisor
  #   - HeavyLoad       — requires Task.async_stream
  #   - Measurer        — requires System.monotonic_time
  #   - AsyncServer     — requires GenServer + exec_func_async

  @relay "giocci_relay"
  @client_name "atomvm_client"
  @default_timeout 5000
  @reconnect_delay_ms 5000

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  # Register this client with a Giocci relay.
  # Returns :ok | {:error, reason}
  def register_client(session, relay_name, client_name, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    key = "giocci/register/client/" <> relay_name
    term = %{data: %{client_name: client_name}, measurements: %{}}

    case zenoh_get(session, key, term, timeout) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  # Execute a function on a Giocci engine via the relay.
  # mfargs: {Module, :function, [arg1, arg2, ...]}
  # Module must already be uploaded by a PC-side Giocci client via save_module.
  # Returns {:ok, result} | {:error, reason}
  def exec_func(session, relay_name, client_name, mfargs, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    key1 = "giocci/inquiry_engine/client/" <> relay_name
    term1 = %{data: %{mfargs: mfargs, client_name: client_name}, measurements: %{}}

    with {:ok, %{data: relay_data, measurements: measurements}} <-
           zenoh_get(session, key1, term1, timeout) do
      engine_name = relay_data[:engine_name]
      key2 = "giocci/exec_func/client/" <> engine_name
      term2 = %{data: %{mfargs: mfargs, client_name: client_name}, measurements: measurements}

      with {:ok, %{data: result}} <- zenoh_get(session, key2, term2, timeout) do
        {:ok, result}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Demo entry point (called by AtomVM on boot)
  # ---------------------------------------------------------------------------

  def start() do
    IO.puts("=== GiocciClient starting ===")
    connect_wifi()
    IO.puts("WiFi connected, opening Zenoh session...")
    open_and_run()
  end

  defp open_and_run() do
    case Zenoh.open(EspConfig.zenoh_router()) do
      {:ok, session} ->
        IO.puts("Zenoh session open!")
        run_demo(session)
        Zenoh.close(session)
        IO.puts("Session closed, reconnecting in #{@reconnect_delay_ms}ms...")
        Process.sleep(@reconnect_delay_ms)
        open_and_run()

      {:error, reason} ->
        IO.puts("Zenoh open failed: #{inspect(reason)}, retrying in #{@reconnect_delay_ms}ms...")
        Process.sleep(@reconnect_delay_ms)
        open_and_run()
    end
  end

  defp run_demo(session) do
    case register_client(session, @relay, @client_name) do
      :ok ->
        IO.puts("Registered with relay '#{@relay}' as '#{@client_name}'")
        demo_hello(session)
        demo_basic_calc(session)

      {:error, reason} ->
        IO.puts("register_client failed: #{inspect(reason)}, reconnecting...")
    end
  end

  # --- GiocciExample.hello (mirrors README "Hello, World!!" section) ---

  defp demo_hello(session) do
    IO.puts("\n-- GiocciExample.hello --")
    exec_and_print(session, {GiocciExample, :hello, []})
    exec_and_print(session, {GiocciExample, :hello, ["AtomVM"]})
  end

  # --- GiocciExample.BasicCalc (mirrors README "Basic Calculation" section) ---

  defp demo_basic_calc(session) do
    IO.puts("\n-- GiocciExample.BasicCalc --")
    exec_and_print(session, {GiocciExample.BasicCalc, :add, [3, 4]})
    exec_and_print(session, {GiocciExample.BasicCalc, :multiply, [3, 4]})
    exec_and_print(session, {GiocciExample.BasicCalc, :power, [3, 4]})
    exec_and_print(session, {GiocciExample.BasicCalc, :fib, [10]})
  end

  defp exec_and_print(session, {m, f, a} = mfargs) do
    label = "#{inspect(m)}.#{f}(#{Enum.join(Enum.map(a, &inspect/1), ", ")})"

    case exec_func(session, @relay, @client_name, mfargs) do
      {:ok, result} ->
        IO.puts("  #{label} => #{inspect(result)}")

      {:error, reason} ->
        IO.puts("  #{label} => ERROR: #{inspect(reason)}")
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp zenoh_get(session, key, term, timeout_ms) do
    payload = :erlang.term_to_binary(term)

    case Zenoh.get(session, key, payload, timeout_ms) do
      {:ok, reply_bin} -> :erlang.binary_to_term(reply_bin)
      :timeout -> {:error, :timeout}
      error -> error
    end
  end

  defp connect_wifi() do
    parent = self()

    {:ok, _} =
      :network.start_link(
        sta: [
          ssid: EspConfig.wifi_ssid(),
          psk: EspConfig.wifi_pass(),
          connected: fn -> IO.puts("WiFi connected!") end,
          got_ip: fn _info -> send(parent, :got_ip) end,
          disconnected: fn -> IO.puts("WiFi disconnected") end
        ]
      )

    IO.puts("Waiting for WiFi...")

    receive do
      :got_ip -> :ok
    end
  end
end
