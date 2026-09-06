defmodule OpenchatWeb.InboxChannel do
  use OpenchatWeb, :channel
  intercept ["direct_message"]

  def join("inbox:" <> id, _, socket) do
    if id == socket.assigns.user.id and authenticated?(socket) do
      Process.send_after(self(), :check_session, 30_000)
      {:ok, socket}
    else
      {:error, %{reason: "forbidden"}}
    end
  end

  def handle_info(:check_session, socket) do
    if authenticated?(socket) do
      Process.send_after(self(), :check_session, 30_000)
      {:noreply, socket}
    else
      {:stop, :normal, socket}
    end
  end

  def handle_out("direct_message", payload, socket) do
    if authenticated?(socket) and
         match?(
           {:ok, _},
           Openchat.Direct.conversation(socket.assigns.user.id, payload.conversation_id)
         ) do
      push(socket, "direct_message", payload)
      {:noreply, socket}
    else
      {:stop, :normal, socket}
    end
  end

  defp authenticated?(socket),
    do: not is_nil(Openchat.Accounts.session(socket.assigns.session_token))
end
