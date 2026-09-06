defmodule Openchat.DirectTest do
  use Openchat.DataCase, async: true
  import Openchat.PlatformFixtures
  alias Openchat.{Accounts, Chat, Direct, Repo}

  defp identity(user) do
    {public, _private} = :crypto.generate_key(:ecdh, :secp256r1)
    key = Base.encode64(public)
    assert {:ok, _} = Direct.publish_identity(user, key)
    key
  end

  setup do
    alice = user()
    bob = user()
    outsider = user()
    identity(alice)
    identity(bob)
    identity(outsider)
    {:ok, server} = Chat.create_server(alice, "Amis communs")
    {:ok, %{token: token}} = Chat.invite(alice, server.id)
    {:ok, _} = Chat.accept(bob, token)
    %{alice: alice, bob: bob, outsider: outsider, server: server}
  end

  test "identities are public-only, immutable and do not overwrite the vault", %{alice: alice} do
    before = Repo.get!(Openchat.Chat.User, alice.id)
    key = before.data["dm_public_key"]
    assert {:ok, _} = Direct.publish_identity(alice, key)
    assert {:error, _} = Direct.publish_identity(alice, "not a public key")
    {other, _} = :crypto.generate_key(:ecdh, :secp256r1)
    assert {:error, _} = Direct.publish_identity(alice, Base.encode64(other))
    assert Repo.get!(Openchat.Chat.User, alice.id).data == before.data
    assert Accounts.private(before)["dm_public_key"] == nil
  end

  test "contacts reveal only fellow members and never their email", c do
    assert [%{id: id, name: _, ready: true} = contact] = Direct.contacts(c.alice)
    assert id == c.bob.id
    assert Map.keys(contact) |> Enum.sort() == [:id, :name, :ready, :username]
    assert Direct.contacts(c.outsider) == []
    assert {:error, _} = Direct.start(c.alice, c.outsider.id)
    assert {:error, _} = Direct.start(c.alice, c.alice.id)
    assert {:error, _} = Direct.start(c.alice, "invalid")
  end

  test "a conversation is unique for the pair, independent of who starts it", c do
    assert {:ok, a} = Direct.start(c.alice, c.bob.id)
    assert {:ok, b} = Direct.start(c.bob, c.alice.id)
    assert a.id == b.id
    assert a.peer.id == c.bob.id
    assert b.peer.id == c.alice.id
    assert [listed] = Direct.list(c.bob)
    assert listed.id == a.id
    assert Direct.list(c.outsider) == []
  end

  test "only the two participants can read and send, even another server member cannot", c do
    {:ok, %{token: token}} = Chat.invite(c.alice, c.server.id)
    {:ok, _} = Chat.accept(c.outsider, token)
    {:ok, conversation} = Direct.start(c.alice, c.bob.id)
    assert {:ok, sent} = Direct.send_message(c.alice, conversation.id, message())
    assert sent.user_id == c.alice.id
    assert {:ok, %{messages: [^sent]}} = Direct.history(c.bob, conversation.id)
    assert {:error, _} = Direct.history(c.outsider, conversation.id)
    assert {:error, _} = Direct.send_message(c.outsider, conversation.id, message())
    assert {:error, _} = Direct.send_message(c.alice, conversation.id, %{"text" => "plaintext"})

    raw =
      Repo.query!("SELECT data FROM direct_messages WHERE id = $1", [Ecto.UUID.dump!(sent.id)]).rows
      |> hd()
      |> hd()

    refute String.contains?(raw, sent.encrypted["cipher"])
  end

  test "history is paginated without leaking a different conversation", c do
    {:ok, conversation} = Direct.start(c.alice, c.bob.id)
    for _ <- 1..53, do: Direct.send_message(c.alice, conversation.id, message())
    {:ok, %{messages: page}} = Direct.history(c.bob, conversation.id)
    assert length(page) == 50
    {:ok, %{messages: older}} = Direct.history(c.bob, conversation.id, hd(page).id)
    assert length(older) == 3
    assert MapSet.disjoint?(MapSet.new(page, & &1.id), MapSet.new(older, & &1.id))
  end

  test "uninitialized recipients must activate their identity first", c do
    person = user()
    {:ok, %{token: token}} = Chat.invite(c.alice, c.server.id)
    {:ok, _} = Chat.accept(person, token)
    assert Enum.find(Direct.contacts(c.alice), &(&1.id == person.id)).ready == false
    assert {:error, _} = Direct.start(c.alice, person.id)
  end
end
