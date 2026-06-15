defmodule GiocciClient do
  @compile {:no_warn_undefined, [Zenoh, :network, EspConfig]}

  # Giocci client port for AtomVM (ESP32).
  # Mirrors giocci_example (https://github.com/biyooon-ex/giocci_example).
  #
  # Supported: register_client/4, exec_func/5, save_module/6
  # Not supported on AtomVM (use PC-side Giocci client instead):
  #   - exec_func_async — requires Task.Supervisor
  #   - HeavyLoad       — requires Task.async_stream
  #   - Measurer        — requires System.monotonic_time
  #   - AsyncServer     — requires GenServer + exec_func_async
  #
  # GiocciClientExample.beam is pre-compiled on the build host and embedded here
  # as a binary literal. At runtime the ESP32 sends it to the engine via save_module.

  @relay "giocci_relay"
  @client_name "atomvm_client"
  @default_timeout 10000
  @reconnect_delay_ms 5000

  # Embed GiocciClientExample.beam at compile time, wrapped in term_to_binary so that
  # the literal stored in the LitT chunk does NOT start with the BEAM magic bytes
  # (FOR1...BEAM). PackBEAM's get_atom_literals iterates LitT via binary_to_term and
  # an unwrapped raw BEAM binary can cause {invalid_chunk, <<FOR1...>>} crashes.
  # GIOCCI_EXAMPLE_BEAM_DIR must point to the directory containing the compiled .beam.
  # (cmake sets this automatically via `cmake -E env`.)
  @giocci_example_beam_etf :erlang.term_to_binary(
    File.read!(
      Path.join(
        System.get_env("GIOCCI_EXAMPLE_BEAM_DIR") ||
          raise("GIOCCI_EXAMPLE_BEAM_DIR not set — run via cmake or set manually"),
        "Elixir.GiocciClientExample.beam"
      )
    )
  )
  defp giocci_example_beam, do: :erlang.binary_to_term(@giocci_example_beam_etf)

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

  # Upload a pre-compiled Elixir module's BEAM binary to the engine via the relay.
  # module_atom:  the module atom (e.g. GiocciClientExample)
  # beam_binary:  raw BEAM binary (use @giocci_example_beam or File.read!/1)
  # Returns :ok | {:error, reason}
  def save_module(session, relay_name, client_name, module_atom, beam_binary, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    key = "giocci/save_module/client/" <> relay_name
    # module_object_code mirrors :code.get_object_code/1 return format:
    #   {module_atom, beam_binary, filename}
    # The engine passes this to :code.load_binary/3. Using the atom as filename
    # satisfies file:filename() :: string() | atom().
    module_object_code = {module_atom, beam_binary, module_atom}
    term = %{
      data: %{
        module_object_code: module_object_code,
        timeout: timeout,
        client_name: client_name
      },
      measurements: %{}
    }

    case zenoh_get(session, key, term, timeout) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  # Execute a function on a Giocci engine via the relay.
  # mfargs: {Module, :function, [arg1, arg2, ...]}
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
        demo_save_module(session)

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

  # --- save_module + GiocciClientExample (ESP32-defined module sent to engine) ---

  defp demo_save_module(session) do
    IO.puts("\n-- save_module + GiocciClientExample --")

    case save_module(session, @relay, @client_name, GiocciClientExample, giocci_example_beam()) do
      :ok ->
        IO.puts("  GiocciClientExample saved to engine!")
        exec_and_print(session, {GiocciClientExample, :hello, []})
        exec_and_print(session, {GiocciClientExample, :hello, ["Giocci"]})
        exec_and_print(session, {GiocciClientExample, :add, [10, 32]})
        exec_and_print(session, {GiocciClientExample, :fib, [8]})
        exec_and_print(session, {GiocciClientExample, :celsius_to_fahrenheit, [25]})

      {:error, reason} ->
        IO.puts("  save_module failed: #{inspect(reason)}")
    end
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
