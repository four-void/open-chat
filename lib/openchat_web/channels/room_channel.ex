defmodule OpenchatWeb.RoomChannel do
  use OpenchatWeb, :channel
  alias OpenchatWeb.Presence
  intercept ["signal", "message", "thread_changed", "presence_diff", "access_changed"]

  def join("room:" <> id, _, socket) do
    with {_, _} <- Openchat.Accounts.session(socket.assigns.session_token),
         {:ok, room} <- Openchat.Chat.room(socket.assigns.user.id, id),
         true <-
           room.kind != "voice" or
             Openchat.Permissions.allowed?(socket.assigns.user.id, room, "connect") do
      if room.kind == "voice", do: send(self(), :track)
      Process.send_after(self(), :check_session, 30_000)

      {:ok,
       %{
         peer_id: socket.assigns.peer_id,
         permissions: Openchat.Permissions.for_room(socket.assigns.user.id, room)
       }, assign(socket, :room, room)}
    else
      _ -> {:error, %{reason: "forbidden"}}
    end
  end

  def handle_info(:track, socket) do
    Presence.track(socket, socket.assigns.peer_id, Openchat.Accounts.public(socket.assigns.user))
    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  def handle_info(:check_session, socket) do
    if authorized?(socket) do
      Process.send_after(self(), :check_session, 30_000)
      {:noreply, socket}
    else
      {:stop, :normal, socket}
    end
  end

  def handle_in(event, params, socket) do
    bucket = if event in ["message", "thread_reply", "signal"], do: event, else: :unsupported

    if authorized?(socket) and
         Openchat.Security.Limiter.allow?(
           {:socket, socket.assigns.user.id, bucket},
           if(event == "signal", do: 600, else: 60)
         ) do
      dispatch(event, params, socket)
    else
      {:reply, {:error, %{reason: "forbidden_or_rate_limited"}}, socket}
    end
  end

  defp dispatch("message", params, socket) do
    case Openchat.Chat.send_message(socket.assigns.user, socket.assigns.room.id, params) do
      {:ok, message} ->
        broadcast!(socket, "message", message)
        {:reply, {:ok, message}, socket}

      _ ->
        {:reply, {:error, %{reason: "invalid_message"}}, socket}
    end
  end

  defp dispatch("thread_reply", %{"thread_id" => id, "encrypted" => payload}, socket) do
    case Openchat.Chat.reply_thread(socket.assigns.user, id, socket.assigns.room.id, payload) do
      {:ok, message} ->
        broadcast!(socket, "message", message)
        {:reply, {:ok, message}, socket}

      _ ->
        {:reply, {:error, %{reason: "forbidden"}}, socket}
    end
  end

  defp dispatch("signal", %{"to" => to, "data" => data}, socket) when is_map(data) do
    if socket.assigns.room.kind == "voice" and Map.has_key?(Presence.list(socket), to) and
         byte_size(Jason.encode!(data)) <= 40_000 and signal_allowed?(socket, data) do
      broadcast!(socket, "signal", %{to: to, from: socket.assigns.peer_id, data: data})
      {:reply, :ok, socket}
    else
      {:reply, {:error, %{reason: "invalid_target"}}, socket}
    end
  end

  defp dispatch(_, _, socket), do: {:reply, {:error, %{reason: "unsupported"}}, socket}

  def handle_out("access_changed", payload, socket) do
    push(socket, "access_changed", payload)

    if socket.assigns.room.kind == "voice" or not authorized?(socket),
      do: {:stop, :normal, socket},
      else: {:noreply, socket}
  end

  def handle_out(event, payload, socket) do
    if authorized?(socket) do
      if event != "signal" or payload.to == socket.assigns.peer_id,
        do: push(socket, event, payload)

      {:noreply, socket}
    else
      {:stop, :normal, socket}
    end
  end

  defp signal_allowed?(socket, data) do
    {:ok, room} = Openchat.Chat.room(socket.assigns.user.id, socket.assigns.room.id)
    permissions = Openchat.Permissions.for_room(socket.assigns.user.id, room)
    share? = data["sharing"] != true or "share" in permissions

    case data["description"] do
      %{"sdp" => sdp} when is_binary(sdp) ->
        share? and
          Enum.all?(String.split(sdp, ~r/(?=^m=)/m), fn section ->
            sends? =
              not String.contains?(section, ["a=recvonly", "a=inactive"]) and
                not Regex.match?(~r/^m=\w+ 0 /, section)

            cond do
              String.starts_with?(section, "m=audio") and sends? -> "speak" in permissions
              String.starts_with?(section, "m=video") and sends? -> "share" in permissions
              true -> true
            end
          end)

      nil ->
        share?

      _ ->
        false
    end
  end

  defp authorized?(socket) do
    with {_, _} <- Openchat.Accounts.session(socket.assigns.session_token),
         {:ok, room} <- Openchat.Chat.room(socket.assigns.user.id, socket.assigns.room.id) do
      room.kind != "voice" or
        Openchat.Permissions.allowed?(socket.assigns.user.id, room, "connect")
    else
      _ -> false
    end
  end
end
