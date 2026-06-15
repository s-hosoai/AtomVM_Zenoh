defmodule GiocciClient do
  @compile {:no_warn_undefined, [Zenoh, :network, EspConfig]}

  @moduledoc """
  Giocci client port for AtomVM (ESP32).

  Supported:
    - register_client/4
    - exec_func/5

  Not supported (use a PC Giocci client instead):
    - save_module  — requires :code.get_object_code/1, unavailable on AtomVM
    - exec_func_async — requires Task.Supervisor, unavailable on AtomVM
  """

  @default_timeout 5000
  @reconnect_delay_ms 5000

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Register this client with a Giocci relay.

      :ok | {:error, reason}
  """
  def register_client(session, relay_name, client_name, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    key = "giocci/register/client/" <> relay_name
    term = %{data: %{client_name: client_name}, measurements: %{}}

    case zenoh_get(session, key, term, timeout) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @doc """
  Execute a function on a Giocci engine via the relay.

      mfargs: {Module, :function, [arg1, arg2, ...]}

  The module must already be uploaded to the relay by a PC-side Giocci client.
  Returns {:ok, result} | {:error, reason}.
  """
  def exec_func(session, relay_name, client_name, mfargs, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    # Step 1: ask relay which engine handles this request
    key1 = "giocci/inquiry_engine/client/" <> relay_name
    term1 = %{data: %{mfargs: mfargs, client_name: client_name}, measurements: %{}}

    with {:ok, %{data: relay_data, measurements: measurements}} <-
           zenoh_get(session, key1, term1, timeout) do
      engine_name = relay_data[:engine_name]

      # Step 2: execute on the assigned engine
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

  @doc "Boot entry point for demo. Edit relay_name / client_name as needed."
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
    relay_name = "relay1"
    client_name = "atomvm_client"

    case register_client(session, relay_name, client_name) do
      :ok ->
        IO.puts("Registered with relay '#{relay_name}' as '#{client_name}'")
        exec_loop(session, relay_name, client_name, 0)

      {:error, reason} ->
        IO.puts("register_client failed: #{inspect(reason)}")
    end
  end

  defp exec_loop(session, relay_name, client_name, count) do
    IO.puts("[#{count}] exec_func Integer.to_string(#{count})...")

    case exec_func(session, relay_name, client_name, {Integer, :to_string, [count]}) do
      {:ok, result} ->
        IO.puts("  => #{inspect(result)}")

      {:error, reason} ->
        IO.puts("  error: #{inspect(reason)}")
        # On error, return to trigger reconnect
        :error
    end

    Process.sleep(3000)
    exec_loop(session, relay_name, client_name, count + 1)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Send a term via Zenoh GET and decode the reply.
  # Returns the decoded reply term directly, or {:error, reason}.
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
