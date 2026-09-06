defmodule Openchat.RoleHierarchyTest do
  use Openchat.DataCase, async: true
  import Openchat.PlatformFixtures
  alias Openchat.{Chat, Permissions, Repo}

  defp role(owner, server, name, permissions) do
    {:ok, role} =
      Permissions.save_role(owner, server.id, nil, %{
        "name" => name,
        "color" => "#123456",
        "permissions" => permissions
      })

    role
  end

  setup do
    owner = user()
    admin = user()
    member = user()
    {:ok, server} = Chat.create_server(owner, "Notre serveur")

    for u <- [admin, member] do
      {:ok, %{token: token}} = Chat.invite(owner, server.id)
      {:ok, _} = Chat.accept(u, token)
    end

    high = role(owner, server, "Direction", ["administrator"])
    low = role(owner, server, "Équipe custom", ["send"])
    {:ok, _} = Permissions.assign_roles(owner, server.id, admin.id, [high.id])
    %{owner: owner, admin: admin, member: member, server: server, high: high, low: low}
  end

  test "creator owns the server and admin can manage lower roles, never owner or self", c do
    assert c.server.owner_id == c.owner.id
    assert "administrator" in Permissions.for_server(c.owner.id, c.server.id)
    assert {:ok, settings} = Permissions.settings(c.admin, c.server.id)
    assert settings.can_manage_roles
    assert settings.manageable_members == [c.member.id]
    assert {:ok, _} = Permissions.assign_roles(c.admin, c.server.id, c.member.id, [c.low.id])
    assert {:error, _} = Permissions.assign_roles(c.admin, c.server.id, c.member.id, [c.high.id])
    assert {:error, _} = Permissions.assign_roles(c.admin, c.server.id, c.owner.id, [])
    assert {:error, _} = Permissions.assign_roles(c.admin, c.server.id, c.admin.id, [])
    assert {:error, _} = Permissions.delete_role(c.admin, c.server.id, c.high.id)

    assert {:error, _} =
             Permissions.save_role(c.admin, c.server.id, c.high.id, %{
               "name" => "Changed",
               "color" => "#123456",
               "permissions" => []
             })

    assert {:ok, created} =
             Permissions.save_role(c.admin, c.server.id, nil, %{
               "name" => " Mon équipe ",
               "color" => "#123456",
               "permissions" => ["invite"]
             })

    assert created.name == "Mon équipe"
    assert created.position == 1
  end

  test "non administrators cannot manage roles even with the legacy manage_roles permission", c do
    manager = role(c.owner, c.server, "Responsable", ["manage_roles"])
    junior = role(c.owner, c.server, "Junior", [])
    {:ok, _} = Permissions.assign_roles(c.owner, c.server.id, c.member.id, [manager.id])

    assert {:error, _} =
             Permissions.save_role(c.member, c.server.id, junior.id, %{
               "name" => "Junior renommé",
               "color" => "#654321",
               "permissions" => ["send"]
             })

    assert {:error, _} =
             Permissions.save_role(c.member, c.server.id, junior.id, %{
               "name" => "Escalade",
               "color" => "#654321",
               "permissions" => ["administrator"]
             })

    assert {:error, _} = Permissions.set_everyone(c.member, c.server.id, ["invite"])
    assert {:error, _} = Permissions.set_everyone(c.owner, c.server.id, ["manage_roles"])
  end

  test "reordering validates the complete server list and protects hierarchy", c do
    junior = role(c.owner, c.server, "Junior", [])

    assert {:error, _} =
             Permissions.reorder_roles(c.admin, c.server.id, [c.low.id, c.high.id, junior.id])

    assert {:ok, _} =
             Permissions.reorder_roles(c.admin, c.server.id, [c.high.id, junior.id, c.low.id])

    assert {:error, _} =
             Permissions.reorder_roles(c.owner, c.server.id, [c.high.id, c.high.id, c.low.id])

    assert {:error, _} = Permissions.reorder_roles(c.owner, c.server.id, [c.low.id])

    assert {:ok, _} =
             Permissions.reorder_roles(c.owner, c.server.id, [c.low.id, c.high.id, junior.id])

    assert {:error, _} = Permissions.assign_roles(c.admin, c.server.id, c.member.id, [c.low.id])
  end

  test "deleting roles cleans memberships and channel exceptions without touching other servers",
       c do
    {:ok, _} = Permissions.assign_roles(c.owner, c.server.id, c.member.id, [c.low.id])
    {:ok, [room | _]} = Chat.rooms(c.owner, c.server.id)

    assert {:ok, _} =
             Permissions.set_overrides(c.owner, room.id, %{
               c.low.id => %{"allow" => ["send"], "deny" => []}
             })

    {:ok, other} = Chat.create_server(c.owner, "Autre serveur")
    foreign = role(c.owner, other, "Équipe custom", ["administrator"])
    assert {:error, _} = Permissions.delete_role(c.owner, c.server.id, foreign.id)
    assert {:error, _} = Permissions.reorder_roles(c.owner, c.server.id, [c.high.id, foreign.id])
    assert {:ok, _} = Permissions.delete_role(c.admin, c.server.id, c.low.id)

    assert Repo.get!(
             Openchat.Chat.Membership,
             Repo.get_by!(Openchat.Chat.Membership, server_id: c.server.id, user_id: c.member.id).id
           ).data["role_ids"] == []

    assert Repo.get!(Openchat.Chat.Room, room.id).data["overwrites"] == %{}
    assert Repo.get!(Openchat.Chat.Role, foreign.id)
    assert {:error, _} = Permissions.delete_role(c.admin, c.server.id, nil)
  end

  test "demoting an administrator immediately removes role management", c do
    {:ok, _} = Permissions.assign_roles(c.owner, c.server.id, c.admin.id, [])
    assert {:error, _} = Permissions.delete_role(c.admin, c.server.id, c.low.id)
    assert {:ok, %{can_manage_roles: false}} = Permissions.settings(c.admin, c.server.id)
  end

  test "channel creation is delegated separately and revocation applies immediately", c do
    assert {:error, _} = Chat.create_room(c.member, c.server.id, "interdit", "text")
    manager = role(c.owner, c.server, "Création de salons", ["manage_channels"])
    {:ok, _} = Permissions.assign_roles(c.owner, c.server.id, c.member.id, [manager.id])

    for kind <- ["text", "voice"] do
      assert {:ok, room} = Chat.create_room(c.member, c.server.id, "Nouveau salon", kind)
      assert room.kind == kind
    end

    assert {:ok, %{can_manage_roles: false}} = Permissions.settings(c.member, c.server.id)
    assert {:error, _} = Permissions.assign_roles(c.member, c.server.id, c.admin.id, [])
    {:ok, _} = Permissions.assign_roles(c.owner, c.server.id, c.member.id, [])
    assert {:error, _} = Chat.create_room(c.member, c.server.id, "interdit", "voice")
  end

  test "administrators can save, preserve and remove a role emoji", c do
    params = %{"name" => "Équipe", "color" => "#123456", "permissions" => ["send"]}

    for emoji <- ["🌿", "👩🏽‍💻", "🇫🇷", "🛡️"] do
      assert {:ok, saved} =
               Permissions.save_role(
                 c.admin,
                 c.server.id,
                 c.low.id,
                 Map.put(params, "emoji", emoji)
               )

      assert saved.emoji == emoji
      assert {:ok, preserved} = Permissions.save_role(c.admin, c.server.id, c.low.id, params)
      assert preserved.emoji == emoji
    end

    assert {:ok, cleared} =
             Permissions.save_role(c.admin, c.server.id, c.low.id, Map.put(params, "emoji", ""))

    assert cleared.emoji == ""

    for invalid <- ["🌿⭐", String.duplicate("a", 100), "\n", %{}] do
      assert {:error, _} =
               Permissions.save_role(
                 c.admin,
                 c.server.id,
                 c.low.id,
                 Map.put(params, "emoji", invalid)
               )
    end

    assert {:error, _} =
             Permissions.save_role(c.member, c.server.id, c.low.id, Map.put(params, "emoji", "👑"))
  end

  test "quick member actions update a single role without replacing other assignments", c do
    another = role(c.owner, c.server, "Autre rôle", ["send"])

    assert {:ok, _} =
             Permissions.set_member_role(c.admin, c.server.id, c.member.id, c.low.id, true)

    assert {:ok, _} =
             Permissions.set_member_role(c.admin, c.server.id, c.member.id, another.id, true)

    assert {:ok, _} =
             Permissions.set_member_role(c.admin, c.server.id, c.member.id, another.id, true)

    {:ok, members} = Chat.members(c.owner, c.server.id)
    ids = Enum.find(members, &(&1.id == c.member.id)).role_ids
    assert MapSet.new(ids) == MapSet.new([c.low.id, another.id])

    assert {:ok, _} =
             Permissions.set_member_role(c.admin, c.server.id, c.member.id, c.low.id, false)

    {:ok, members} = Chat.members(c.owner, c.server.id)
    assert Enum.find(members, &(&1.id == c.member.id)).role_ids == [another.id]
  end

  test "quick member actions enforce administrator status, hierarchy and server boundaries", c do
    {:ok, other} = Chat.create_server(c.owner, "Autre serveur")
    foreign = role(c.owner, other, "Étranger", [])

    for {actor, target, role_id, enabled} <- [
          {c.member, c.member.id, c.low.id, true},
          {c.admin, c.owner.id, c.low.id, true},
          {c.admin, c.admin.id, c.low.id, false},
          {c.admin, c.member.id, c.high.id, true},
          {c.admin, c.member.id, foreign.id, true},
          {c.admin, c.member.id, c.low.id, "true"}
        ] do
      assert {:error, _} =
               Permissions.set_member_role(actor, c.server.id, target, role_id, enabled)
    end

    {:ok, _} = Permissions.assign_roles(c.owner, c.server.id, c.admin.id, [])

    assert {:error, _} =
             Permissions.set_member_role(c.admin, c.server.id, c.member.id, c.low.id, true)
  end
end
