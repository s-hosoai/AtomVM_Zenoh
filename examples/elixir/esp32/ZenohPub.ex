defmodule ZenohPub do
  @compile {:no_warn_undefined, [Zenoh, :network]}

  @moduledoc """
  Zenoh publisher example for ESP32-S3.
  Connects WiFi, then publishes a counter to "atomvm/example/pub" every second.

  Flash and run:
    idf.py -p /dev/ttyACM0 flash
    esptool.py --chip esp32s3 --port /dev/ttyACM0 write_flash 0x250000 ZenohPub.avm

  On your laptop run a Zenoh subscriber:
    zenoh-sub -e "tcp/192.168.1.x:7447" -k "atomvm/example/pub"
  """

  @wifi_ssid "YOUR_SSID"
  @wifi_pass "YOUR_PASSWORD"
  @zenoh_router "tcp/192.168.1.100:7447"
  @keyexpr "atomvm/example/pub"

  def start() do
    IO.puts("=== ZenohPub starting ===")
    connect_wifi()
    IO.puts("WiFi connected, opening Zenoh session...")

    {:ok, session} = Zenoh.open(@zenoh_router)
    IO.puts("Zenoh session open!")

    {:ok, pub} = Zenoh.declare_publisher(session, @keyexpr)
    IO.puts("Publisher declared on #{@keyexpr}")

    loop(pub, 0)
  end

  defp loop(pub, count) do
    payload = "AtomVM count=#{count}"
    IO.puts("[#{count}] Publishing: #{payload}")
    Zenoh.publisher_put(pub, payload)
    Process.sleep(1000)
    loop(pub, count + 1)
  end

  defp connect_wifi() do
    :ok = :network.start_link(%{
      sta: %{
        ssid: @wifi_ssid,
        psk: @wifi_pass,
        connected: fn -> IO.puts("WiFi connected!") end,
        got_ip: fn info -> IO.puts("Got IP: #{inspect(info)}") end,
        disconnected: fn -> IO.puts("WiFi disconnected") end
      }
    })
    IO.puts("Waiting for WiFi...")
    wait_for_ip()
  end

  defp wait_for_ip() do
    case :network.sta_ip() do
      {:ok, _ip} -> :ok
      _ ->
        Process.sleep(500)
        wait_for_ip()
    end
  end
end
