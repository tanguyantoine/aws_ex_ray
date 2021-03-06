defmodule AwsExRay.Client.UDPClient do

  require Logger

  use GenServer

  @moduledoc """
  This is a UDP client module which reports TRACE information to xray-daemon
  running on localhost.
  """
  @max_retry 10

  @header "{\"format\": \"json\", \"version\": 1}\n"

  defstruct address: nil,
            port:    2000,
            socket:  nil

  @spec send(pid, binary) :: :ok
  def send(client, data) do
    GenServer.call(client, {:send, data})
    :ok
  end

  @spec start_link(keyword) :: GenServer.on_start
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl GenServer
  def init(opts) do

    address = Keyword.fetch!(opts, :address)
    port    = Keyword.fetch!(opts, :port)

    Process.flag(:trap_exit, true)

    case open(0, @max_retry) do

      {:ok, socket} ->
        state = %{
          address: address,
          port:    port,
          socket:  socket,
        }
        {:ok, state}

      :error -> {:stop, :daemon}

    end

  end

  @impl GenServer
  def handle_info({:EXIT, _pid, _reason}, state) do
    {:stop, :normal, state}
  end

  @impl GenServer
  def handle_call({:send, data}, _from, state) do
    case send_data(data, state) do
      :ok ->
        {:reply, :ok, state}
      _other ->
        Logger.error "<AwsExRay.UDPClient> failed to send data"
        {:stop, :normal, state}
    end
  end

  @impl GenServer
  def terminate(_reason, state) do
    :gen_udp.close(state.socket)
    :ok
  end

  defp open(attempts, max_retry) do

    port = get_port()

    case :gen_udp.open(port, [:binary]) do

      {:ok, socket} -> {:ok, socket}

      other when attempts < max_retry ->
        Logger.error "<AwsExRay.UDPClient> failed to open UDP(#{port}): #{inspect other}, retry"
        open(attempts + 1, max_retry)

      other ->
        Logger.error "<AwsExRay.UDPClient> failed to open UDP(#{port}): #{inspect other}, shutdown"
        :error

    end
  end

  defp get_port() do
    :rand.uniform(65_535 - 1023) + 1023
  end

  defp send_data(data, state) do
    :gen_udp.send(
      state.socket,
      state.address,
      state.port,
      @header <> data <> "\n"
    )
  end

end
