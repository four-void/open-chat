defmodule OpenchatWeb.InboxChannelTest do
  use Openchat.DataCase, async: false
  import Phoenix.ChannelTest
  import Openchat.PlatformFixtures
  alias Openchat.{Accounts, Chat, Direct}
  @endpoint OpenchatWeb.Endpoint

  defp socket_for(user) do
    token = Accounts.create_session(user)

    {:ok, socket} =
      connect(OpenchatWeb.UserSocket, %{"token" => Phoenix.Token.sign(@endpoint, "socket", token)})

    {socket, token}
  end

  test "inbox topic is private and revoked sessions cannot subscribe" do
    alice = user()
    bob = user()
    {socket, token} = socket_for(alice)

    assert {:error, %{reason: "forbidden"}} =
             subscribe_and_join(socket, OpenchatWeb.InboxChannel, "inbox:" <> bob.id)

    Accounts.revoke(token)

    assert {:error, %{reason: "forbidden"}} =
             subscribe_and_join(socket, OpenchatWeb.InboxChannel, "inbox:" <> alice.id)
  end

  test "recipient receives ciphertext immediately, third-party inbox does not" do
    alice = user()
    bob = user()
    third = user()

    for person <- [alice, bob] do
      {key, _} = :crypto.generate_key(:ecdh, :secp256r1)
      {:ok, _} = Direct.publish_identity(person, Base.encode64(key))
    end

    {:ok, server} = Chat.create_server(alice, "Inbox tests")
    {:ok, %{token: token}} = Chat.invite(alice, server.id)
    {:ok, _} = Chat.accept(bob, token)
    {:ok, c} = Direct.start(alice, bob.id)
    {socket, _} = socket_for(bob)
    {:ok, _, joined} = subscribe_and_join(socket, OpenchatWeb.InboxChannel, "inbox:" <> bob.id)
    {third_socket, _} = socket_for(third)

    {:ok, _, third_joined} =
      subscribe_and_join(third_socket, OpenchatWeb.InboxChannel, "inbox:" <> third.id)

    payload = message()
    {:ok, _} = Direct.send_message(alice, c.id, payload)
    topic = joined.topic

    assert_receive %Phoenix.Socket.Message{
      topic: ^topic,
      event: "direct_message",
      payload: %{encrypted: ^payload}
    }

    third_topic = third_joined.topic
    refute_receive %Phoenix.Socket.Message{topic: ^third_topic, event: "direct_message"}
  end
end
