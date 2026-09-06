defmodule OpenchatWeb.ServerChannel do
  use OpenchatWeb, :channel
  alias OpenchatWeb.Presence

  def join("server:" <> id, _, socket) do
    if Openchat.Accounts.session(socket.assigns.session_token) &&
         Openchat.Chat.member?(socket.assigns.user.id, id) do
      send(self(), :track)
      Process.send_after(self(), :check_session, 30_000)
      {:ok, assign(socket, :server_id, id)}
    else
      {:error, %{reason: "forbidden"}}
    end
  end

  def handle_info(:track, socket) do
    Presence.track(socket, socket.assigns.user.id, Openchat.Accounts.public(socket.assigns.user))
    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  def handle_info(:check_session, socket) do
    if Openchat.Accounts.session(socket.assigns.session_token) &&
         Openchat.Chat.member?(socket.assigns.user.id, socket.assigns.server_id) do
      Process.send_after(self(), :check_session, 30_000)
      {:noreply, socket}
    else
      {:stop, :normal, socket}
    end
  end

  def handle_in(_, _, socket), do: {:reply, {:error, %{reason: "unsupported"}}, socket}
end
