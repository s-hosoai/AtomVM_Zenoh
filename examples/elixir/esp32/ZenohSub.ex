defmodule ZenohSub do
  @compile {:no_warn_undefined, [Zenoh, :network, EspConfig]}

  @keyexpr "atomvm/example/**"

  def start() do
    IO.puts("=== ZenohSub starting ===")
    connect_wifi()
    IO.puts("WiFi connected, opening Zenoh session...")

    {:ok, session} = Zenoh.open(EspConfig.zenoh_router())
    IO.puts("Zenoh session open!")

    {:ok, sub} = Zenoh.declare_subscriber(session, @keyexpr)
    IO.puts("Subscriber declared on #{@keyexpr}")
    IO.puts("Waiting for messages...")

    recv_loop(session, sub)
  end

  defp recv_loop(session, sub) do
    case Zenoh.subscriber_recv(sub, 5000) do
      {:ok, keyexpr, payload} ->
        IO.puts("[RECV] #{keyexpr} => #{payload}")

      :timeout ->
        IO.puts("(waiting...)")

      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
    end
    recv_loop(session, sub)
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
