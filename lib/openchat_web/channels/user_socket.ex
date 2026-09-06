defmodule OpenchatWeb.UserSocket do
  use Phoenix.Socket
  channel "inbox:*", OpenchatWeb.InboxChannel
  channel "room:*", OpenchatWeb.RoomChannel
  channel "server:*", OpenchatWeb.ServerChannel

  def connect(%{"token" => token}, socket, _) do
    with {:ok, session_token} <- Phoenix.Token.verify(socket, "socket", token, max_age: 86400),
         {session, user} <- Openchat.Accounts.session(session_token) do
      {:ok,
       socket
       |> assign(:user, user)
       |> assign(:session_token, session_token)
       |> assign(:session_hash, session.token_hash)
       |> assign(:peer_id, Ecto.UUID.generate())}
    else
      _ -> :error
    end
  end

  def connect(_, _, _), do: :error
  def id(socket), do: "session:" <> Base.url_encode64(socket.assigns.session_hash, padding: false)
end
