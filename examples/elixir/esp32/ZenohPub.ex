defmodule ZenohPub do
  @compile {:no_warn_undefined, [Zenoh, :network, EspConfig]}

  @keyexpr "atomvm/example/pub"
  @reconnect_delay_ms 5000

  def start() do
    IO.puts("=== ZenohPub starting ===")
    connect_wifi()
    IO.puts("WiFi connected, opening Zenoh session...")
    open_and_loop(0)
  end

  defp open_and_loop(count) do
    case Zenoh.open(EspConfig.zenoh_router()) do
      {:ok, session} ->
        IO.puts("Zenoh session open!")
        case Zenoh.declare_publisher(session, @keyexpr) do
          {:ok, pub} ->
            IO.puts("Publisher declared on #{@keyexpr}")
            count = publish_loop(session, pub, count)
            Zenoh.undeclare_publisher(pub)
            Zenoh.close(session)
            IO.puts("Reconnecting in #{@reconnect_delay_ms}ms...")
            Process.sleep(@reconnect_delay_ms)
            open_and_loop(count)

          {:error, reason} ->
            IO.puts("declare_publisher failed: #{inspect(reason)}, retrying...")
            Zenoh.close(session)
            Process.sleep(@reconnect_delay_ms)
            open_and_loop(count)
        end

      {:error, reason} ->
        IO.puts("Zenoh open failed: #{inspect(reason)}, retrying...")
        Process.sleep(@reconnect_delay_ms)
        open_and_loop(count)
    end
  end

  # Returns the next count when a publish error is detected.
  defp publish_loop(session, pub, count) do
    payload = "AtomVM count=#{count}"
    IO.puts("[#{count}] Publishing: #{payload}")
    case Zenoh.publisher_put(pub, payload) do
      :ok ->
        Process.sleep(1000)
        publish_loop(session, pub, count + 1)

      {:error, reason} ->
        IO.puts("Publish error: #{inspect(reason)}, will reconnect")
        count + 1
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
