defmodule ZenohPub do
  @compile {:no_warn_undefined, [Zenoh, :network, EspConfig]}

  @keyexpr "atomvm/example/pub"

  def start() do
    IO.puts("=== ZenohPub starting ===")
    connect_wifi()
    IO.puts("WiFi connected, opening Zenoh session...")

    {:ok, session} = Zenoh.open(EspConfig.zenoh_router())
    IO.puts("Zenoh session open!")

    {:ok, pub} = Zenoh.declare_publisher(session, @keyexpr)
    IO.puts("Publisher declared on #{@keyexpr}")

    loop(session, pub, 0)
  end

  defp loop(session, pub, count) do
    payload = "AtomVM count=#{count}"
    IO.puts("[#{count}] Publishing: #{payload}")
    Zenoh.publisher_put(pub, payload)
    Process.sleep(1000)
    loop(session, pub, count + 1)
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
