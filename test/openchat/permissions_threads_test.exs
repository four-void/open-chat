defmodule Openchat.PermissionsThreadsTest do
  use Openchat.DataCase, async: true
  import Openchat.PlatformFixtures
  alias Openchat.{Chat, Permissions}

  setup do
    owner = user()
    member = user()
    {:ok, server} = Chat.create_server(owner, "Espace de test")
    {:ok, %{token: token}} = Chat.invite(owner, server.id)
    {:ok, _} = Chat.accept(member, token)
    {:ok, [room, voice]} = Chat.rooms(owner, server.id)
    %{owner: owner, member: member, server: server, room: room, voice: voice}
  end

  defp rule(allow, deny), do: %{"allow" => allow, "deny" => deny}

  defp role(owner, server, permissions) do
    {:ok, role} =
      Permissions.save_role(owner, server.id, nil, %{
        "name" => "Équipe",
        "color" => "#608060",
        "permissions" => permissions
      })

    role
  end

  test "legacy memberships inherit normal rights and only owner can create roles", c do
    {:ok, rooms} = Chat.rooms(c.member, c.server.id)
    assert Enum.all?(rooms, &("view" in &1.permissions))

    assert {:error, _} =
             Permissions.save_role(c.member, c.server.id, nil, %{
               "name" => "Escalation",
               "color" => "#123456",
               "permissions" => ["administrator"]
             })

    assert {:error, _} = Permissions.set_everyone(c.owner, c.server.id, ["administrator"])

    assert {:error, _} =
             Permissions.save_role(c.owner, c.server.id, nil, %{
               "name" => "Bad",
               "color" => "red",
               "permissions" => []
             })
  end

  test "private channels disappear and cannot be read directly", c do
    {:ok, _} = Chat.send_message(c.owner, c.room.id, message())

    assert {:ok, _} =
             Permissions.set_overrides(c.owner, c.room.id, %{"everyone" => rule([], ["view"])})

    assert {:ok, [visible]} = Chat.rooms(c.member, c.server.id)
    assert visible.id == c.voice.id
    assert {:error, _} = Chat.room(c.member.id, c.room.id)
    assert {:error, _} = Chat.history(c.member, c.room.id)
    assert {:error, _} = Chat.threads(c.member, c.room.id)
    assert {:error, _} = Chat.send_message(c.member, c.room.id, message())
    assert {:ok, _} = Chat.room(c.owner.id, c.room.id)
  end

  test "role allows beat combined role denies, and member override wins last", c do
    a = role(c.owner, c.server, [])
    b = role(c.owner, c.server, [])
    assert {:ok, _} = Permissions.assign_roles(c.owner, c.server.id, c.member.id, [a.id, b.id])

    overrides = %{
      "everyone" => rule([], ["view", "send"]),
      a.id => rule(["view", "send"], []),
      b.id => rule([], ["send"])
    }

    assert {:ok, _} = Permissions.set_overrides(c.owner, c.room.id, overrides)
    {:ok, room} = Chat.room(c.member.id, c.room.id)
    assert Permissions.allowed?(c.member.id, room, "send")

    assert {:ok, _} =
             Permissions.set_overrides(
               c.owner,
               c.room.id,
               Map.put(overrides, c.member.id, rule([], ["send"]))
             )

    {:ok, room} = Chat.room(c.member.id, c.room.id)
    refute Permissions.allowed?(c.member.id, room, "send")
    assert {:error, _} = Chat.send_message(c.member, c.room.id, message())
  end

  test "administrators bypass channel overrides but cannot change their own roles", c do
    a = role(c.owner, c.server, ["administrator"])
    {:ok, _} = Permissions.assign_roles(c.owner, c.server.id, c.member.id, [a.id])
    {:ok, _} = Permissions.set_overrides(c.owner, c.room.id, %{"everyone" => rule([], ["view"])})
    assert {:ok, _} = Chat.room(c.member.id, c.room.id)
    assert {:error, _} = Permissions.assign_roles(c.member, c.server.id, c.member.id, [])
  end

  test "cross-server role IDs and invalid override shapes are rejected", c do
    {:ok, other} = Chat.create_server(c.owner, "Autre espace")
    foreign = role(c.owner, other, ["administrator"])
    assert {:error, _} = Permissions.assign_roles(c.owner, c.server.id, c.member.id, [foreign.id])
    assert {:error, _} = Permissions.assign_roles(c.owner, c.server.id, "invalid", [])

    for overrides <- [
          nil,
          %{"everyone" => nil},
          %{"everyone" => rule(["administrator"], [])},
          %{"everyone" => rule(["send"], ["send"])},
          %{foreign.id => rule(["view"], [])}
        ] do
      assert {:error, _} = Permissions.set_overrides(c.owner, c.room.id, overrides)
    end
  end

  test "channel managers cannot escalate by removing their own deny", c do
    a = role(c.owner, c.server, ["manage_channels"])
    {:ok, _} = Permissions.assign_roles(c.owner, c.server.id, c.member.id, [a.id])
    {:ok, _} = Permissions.set_overrides(c.owner, c.room.id, %{c.member.id => rule([], ["send"])})
    assert {:error, _} = Permissions.set_overrides(c.member, c.room.id, %{})

    assert {:error, _} =
             Permissions.set_overrides(c.member, c.room.id, %{
               c.member.id => rule(["invite"], ["send"])
             })
  end

  test "threads are isolated, idempotent and paginated separately", c do
    {:ok, root} = Chat.send_message(c.owner, c.room.id, message())
    {:ok, thread} = Chat.create_thread(c.member, root.id)
    assert {:ok, %{id: id}} = Chat.create_thread(c.owner, root.id)
    assert id == thread.id
    {:ok, reply} = Chat.reply_thread(c.member, thread.id, c.room.id, message())
    assert reply.thread_id == thread.id
    assert {:ok, [only_root]} = Chat.history(c.owner, c.room.id)
    assert only_root.id == root.id
    assert only_root.thread.count == 1
    assert {:ok, %{messages: [^reply]}} = Chat.thread_history(c.owner, thread.id)
    assert {:ok, %{messages: []}} = Chat.thread_history(c.owner, thread.id, reply.id)
    assert {:error, _} = Chat.create_thread(c.owner, reply.id)
    assert {:error, _} = Chat.reply_thread(c.member, thread.id, c.voice.id, message())
  end

  test "closed threads reject replies and can reopen; ordinary members cannot close others threads",
       c do
    {:ok, root} = Chat.send_message(c.owner, c.room.id, message())
    {:ok, thread} = Chat.create_thread(c.owner, root.id)
    assert {:error, _} = Chat.archive_thread(c.member, thread.id, true)
    assert {:ok, %{archived: true}} = Chat.archive_thread(c.owner, thread.id, true)
    assert {:error, _} = Chat.reply_thread(c.member, thread.id, c.room.id, message())
    assert {:ok, %{archived: false}} = Chat.archive_thread(c.owner, thread.id, false)
    assert {:ok, _} = Chat.reply_thread(c.member, thread.id, c.room.id, message())
  end

  test "thread permissions follow parent immediately", c do
    {:ok, root} = Chat.send_message(c.owner, c.room.id, message())
    {:ok, thread} = Chat.create_thread(c.owner, root.id)

    {:ok, _} =
      Permissions.set_overrides(c.owner, c.room.id, %{c.member.id => rule([], ["create_threads"])})

    assert {:error, _} = Chat.create_thread(c.member, root.id)
    assert {:ok, _} = Chat.reply_thread(c.member, thread.id, c.room.id, message())
    {:ok, _} = Permissions.set_overrides(c.owner, c.room.id, %{c.member.id => rule([], ["view"])})
    assert {:error, _} = Chat.thread_history(c.member, thread.id)
    assert {:error, _} = Chat.reply_thread(c.member, thread.id, c.room.id, message())
  end
end
