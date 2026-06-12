defmodule ZenohSub do
  @compile {:no_warn_undefined, [Zenoh, :network]}

  @moduledoc """
  Zenoh subscriber example for ESP32-S3.
  Connects WiFi, then subscribes to "atomvm/example/pub" and prints received messages.

  On your laptop run a Zenoh publisher:
    zenoh-put -e "tcp/192.168.1.x:7447" -k "atomvm/example/pub" -v "hello"
  """

  @wifi_ssid "YOUR_SSID"
  @wifi_pass "YOUR_PASSWORD"
  @zenoh_router "tcp/192.168.1.100:7447"
  @keyexpr "atomvm/example/**"

  def start() do
    IO.puts("=== ZenohSub starting ===")
    connect_wifi()
    IO.puts("WiFi connected, opening Zenoh session...")

    {:ok, session} = Zenoh.open(@zenoh_router)
    IO.puts("Zenoh session open!")

    {:ok, sub} = Zenoh.declare_subscriber(session, @keyexpr)
    IO.puts("Subscriber declared on #{@keyexpr}")
    IO.puts("Waiting for messages...")

    recv_loop(sub)
  end

  defp recv_loop(sub) do
    case Zenoh.subscriber_recv(sub, 5000) do
      {:ok, keyexpr, payload} ->
        IO.puts("[RECV] #{keyexpr} => #{payload}")

      :timeout ->
        IO.puts("(waiting...)")

      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
    end
    recv_loop(sub)
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
