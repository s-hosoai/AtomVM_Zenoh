defmodule ZenohSub do
  @compile {:no_warn_undefined, [Zenoh, :network, EspConfig]}

  @keyexpr "atomvm/example/**"
  @recv_timeout_ms 5000
  # Reconnect after this many consecutive timeouts (~30 seconds with 5s timeout).
  @max_timeouts 6
  @reconnect_delay_ms 5000

  def start() do
    IO.puts("=== ZenohSub starting ===")
    connect_wifi()
    IO.puts("WiFi connected, opening Zenoh session...")
    open_and_loop()
  end

  defp open_and_loop() do
    case Zenoh.open(EspConfig.zenoh_router()) do
      {:ok, session} ->
        IO.puts("Zenoh session open!")
        case Zenoh.declare_subscriber(session, @keyexpr) do
          {:ok, sub} ->
            IO.puts("Subscriber declared on #{@keyexpr}")
            IO.puts("Waiting for messages...")
            recv_loop(session, sub, 0)
            Zenoh.undeclare_subscriber(sub)
            Zenoh.close(session)
            IO.puts("Reconnecting in #{@reconnect_delay_ms}ms...")
            Process.sleep(@reconnect_delay_ms)
            open_and_loop()

          {:error, reason} ->
            IO.puts("declare_subscriber failed: #{inspect(reason)}, retrying...")
            Zenoh.close(session)
            Process.sleep(@reconnect_delay_ms)
            open_and_loop()
        end

      {:error, reason} ->
        IO.puts("Zenoh open failed: #{inspect(reason)}, retrying...")
        Process.sleep(@reconnect_delay_ms)
        open_and_loop()
    end
  end

  # Returns when reconnection is needed (consecutive timeouts exceeded or error).
  defp recv_loop(session, sub, timeout_count) do
    case Zenoh.subscriber_recv(sub, @recv_timeout_ms) do
      {:ok, keyexpr, payload} ->
        IO.puts("[RECV] #{keyexpr} => #{payload}")
        recv_loop(session, sub, 0)

      :timeout ->
        IO.puts("(waiting... #{timeout_count + 1}/#{@max_timeouts})")
        if timeout_count + 1 >= @max_timeouts do
          IO.puts("Too many timeouts, reconnecting...")
        else
          recv_loop(session, sub, timeout_count + 1)
        end

      {:error, reason} ->
        IO.puts("Recv error: #{inspect(reason)}, will reconnect")
    end
  end

  defp connect_wifi() do
    parent = self()
    {:ok, _} = :network.start_link(
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
