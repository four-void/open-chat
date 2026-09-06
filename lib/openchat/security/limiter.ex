defmodule Openchat.Security.Limiter do
  use GenServer
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def allow?(key, limit, window \\ 60),
    do: GenServer.call(__MODULE__, {:allow, key, limit, window})

  def init(_), do: {:ok, %{}}

  def handle_call({:allow, key, limit, window}, _from, state) do
    now = System.monotonic_time(:second)
    state = Map.reject(state, fn {_, {until, _}} -> until <= now end)
    {until, count} = Map.get(state, key, {now + window, 0})
    {:reply, count < limit, Map.put(state, key, {until, count + 1})}
  end
end
