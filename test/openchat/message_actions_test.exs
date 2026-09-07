defmodule Openchat.MessageActionsTest do
  use Openchat.DataCase, async: true
  import Openchat.PlatformFixtures
  alias Openchat.{Chat, Direct, MessageActions, Permissions, Repo}

  setup do
    alice = user()
    bob = user()
    stranger = user()
    {:ok, server} = Chat.create_server(alice, "Messages")
    {:ok, %{token: token}} = Chat.invite(alice, server.id)
    {:ok, _} = Chat.accept(bob, token)
    {:ok, [room | _]} = Chat.rooms(alice, server.id)

    for person <- [alice, bob] do
      {key, _} = :crypto.generate_key(:ecdh, :secp256r1)
      {:ok, _} = Direct.publish_identity(person, Base.encode64(key))
    end

    {:ok, dm} = Direct.start(alice, bob.id)
    %{alice: alice, bob: bob, stranger: stranger, room: room, dm: dm}
  end

  test "editing is author-only and deletion removes stored content in both message types", c do
    for {kind, schema, send} <- [
          {:room, Openchat.Chat.Message,
           fn -> Chat.send_message(c.alice, c.room.id, message()) end},
          {:direct, Openchat.Chat.DirectMessage,
           fn -> Direct.send_message(c.alice, c.dm.id, message()) end}
        ] do
      {:ok, m} = send.()
      replacement = message()

      assert {:error, _} =
               MessageActions.change(c.bob, kind, m.id, :edit, %{"encrypted" => replacement})

      assert {:error, _} = MessageActions.change(c.stranger, kind, m.id, :delete, %{})

      assert {:ok, edited} =
               MessageActions.change(c.alice, kind, m.id, :edit, %{"encrypted" => replacement})

      assert edited.encrypted == replacement
      assert edited.edited_at
      assert {:ok, deleted} = MessageActions.change(c.alice, kind, m.id, :delete, %{})
      assert deleted.deleted_at
      assert deleted.encrypted == nil
      assert Repo.get!(schema, m.id).data == %{}

      assert {:error, _} =
               MessageActions.change(c.alice, kind, m.id, :edit, %{"encrypted" => message()})
    end
  end

  test "reactions are idempotent per person and preserve others", c do
    for {kind, send} <- [
          {:room, fn -> Chat.send_message(c.alice, c.room.id, message()) end},
          {:direct, fn -> Direct.send_message(c.alice, c.dm.id, message()) end}
        ] do
      {:ok, m} = send.()
      add = %{"emoji" => "👍", "enabled" => true}

      for u <- [c.alice, c.alice, c.bob],
          do: assert({:ok, _} = MessageActions.change(u, kind, m.id, :react, add))

      assert {:ok, changed} =
               MessageActions.change(c.alice, kind, m.id, :react, %{
                 "emoji" => "👍",
                 "enabled" => false
               })

      assert changed.reactions == %{"👍" => [c.bob.id]}
      assert {:error, _} = MessageActions.change(c.stranger, kind, m.id, :react, add)

      assert {:error, _} =
               MessageActions.change(c.bob, kind, m.id, :react, %{
                 "emoji" => "invalid",
                 "enabled" => true
               })

      assert {:ok, _} = MessageActions.change(c.alice, kind, m.id, :delete, %{})
      assert {:error, _} = MessageActions.change(c.bob, kind, m.id, :react, add)
    end
  end

  test "read-only rights prevent edits and reactions, but allow the author to remove their content",
       c do
    {:ok, m} = Chat.send_message(c.bob, c.room.id, message())

    {:ok, _} =
      Permissions.set_overrides(c.alice, c.room.id, %{
        "everyone" => %{"allow" => [], "deny" => ["send"]}
      })

    assert {:error, _} =
             MessageActions.change(c.bob, :room, m.id, :edit, %{"encrypted" => message()})

    assert {:error, _} =
             MessageActions.change(c.bob, :room, m.id, :react, %{
               "emoji" => "👍",
               "enabled" => true
             })

    assert {:ok, _} = MessageActions.change(c.bob, :room, m.id, :delete, %{})
  end

  test "deleting a root preserves its existing thread and disallows creating a new one", c do
    {:ok, root} = Chat.send_message(c.alice, c.room.id, message())
    {:ok, thread} = Chat.create_thread(c.alice, root.id)
    {:ok, _} = Chat.reply_thread(c.bob, thread.id, c.room.id, message())
    {:ok, _} = MessageActions.change(c.alice, :room, root.id, :delete, %{})

    assert {:ok, %{thread: %{root: %{encrypted: nil}}, messages: [_]}} =
             Chat.thread_history(c.bob, thread.id)

    assert {:error, _} = Chat.create_thread(c.bob, root.id)
  end
end
