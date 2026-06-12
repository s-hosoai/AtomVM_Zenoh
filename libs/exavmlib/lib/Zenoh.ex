defmodule Zenoh do
  @compile {:no_warn_undefined, [:zenoh]}

  @moduledoc """
  Zenoh pub/sub NIFs for AtomVM on ESP32.
  WiFi must be connected before calling open/1.
  """

  @doc "Open a Zenoh session. endpoint: \"tcp/<router_ip>:7447\""
  def open(endpoint) when is_binary(endpoint), do: :zenoh.open(endpoint)

  @doc "Close a Zenoh session."
  def close(session), do: :zenoh.close(session)

  @doc "Publish a payload to a key expression."
  def put(session, keyexpr, payload) when is_binary(keyexpr) and is_binary(payload) do
    :zenoh.put(session, keyexpr, payload)
  end

  @doc "Declare a publisher for a key expression."
  def declare_publisher(session, keyexpr) when is_binary(keyexpr) do
    :zenoh.declare_publisher(session, keyexpr)
  end

  @doc "Publish a payload via a declared publisher."
  def publisher_put(publisher, payload) when is_binary(payload) do
    :zenoh.publisher_put(publisher, payload)
  end

  @doc "Undeclare a publisher."
  def undeclare_publisher(publisher), do: :zenoh.undeclare_publisher(publisher)

  @doc "Declare a subscriber for a key expression."
  def declare_subscriber(session, keyexpr) when is_binary(keyexpr) do
    :zenoh.declare_subscriber(session, keyexpr)
  end

  @doc """
  Receive a message from a subscriber.
  Returns {:ok, keyexpr, payload} | :timeout | {:error, reason}.
  timeout_ms: -1 blocks forever, 0 = immediate, >0 = wait up to N ms.
  """
  def subscriber_recv(subscriber, timeout_ms \\ -1) do
    :zenoh.subscriber_recv(subscriber, timeout_ms)
  end

  @doc "Undeclare a subscriber."
  def undeclare_subscriber(subscriber), do: :zenoh.undeclare_subscriber(subscriber)
end
