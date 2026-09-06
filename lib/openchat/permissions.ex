defmodule Openchat.Permissions do
  @moduledoc "Server roles and Discord-style ordered channel overrides. Ownership cannot be delegated."
  import Ecto.Query
  alias Openchat.{Repo, Chat}
  alias Openchat.Chat.{Membership, Server, Role, Room}

  @keys ~w(view send connect speak share create_threads manage_threads manage_channels invite manage_roles administrator)
  @defaults ~w(view send connect speak share create_threads)
  def keys, do: @keys
  def defaults, do: @defaults

  def valid?(values),
    do: is_list(values) and length(values) <= length(@keys) and Enum.all?(values, &(&1 in @keys))

  def for_server(user_id, server_id) do
    with true <- Chat.uuid?(server_id),
         %Server{} = server <- Repo.get(Server, server_id),
         %Membership{} = member <- Repo.get_by(Membership, user_id: user_id, server_id: server_id) do
      ids = (member.data || %{})["role_ids"] || []
      roles = Repo.all(from r in Role, where: r.server_id == ^server_id and r.id in ^ids)
      base = Map.get(server.data, "permissions", @defaults)

      permissions =
        Enum.reduce(roles, MapSet.new(base), fn role, acc ->
          MapSet.union(acc, MapSet.new(role.data["permissions"] || []))
        end)

      if server.owner_id == user_id or MapSet.member?(permissions, "administrator"),
        do: @keys,
        else: MapSet.to_list(permissions)
    else
      _ -> []
    end
  end

  def for_room(user_id, %Room{} = room) do
    base = for_server(user_id, room.server_id)

    if "administrator" in base do
      @keys
    else
      case Repo.get_by(Membership, user_id: user_id, server_id: room.server_id) do
        nil ->
          []

        membership ->
          overwrites = room.data["overwrites"] || %{}
          everyone = Map.get(overwrites, "everyone", %{})
          role_ids = (membership.data || %{})["role_ids"] || []
          role_overrides = Enum.map(role_ids, &Map.get(overwrites, &1, %{}))

          combined = %{
            "deny" => Enum.flat_map(role_overrides, &Map.get(&1, "deny", [])),
            "allow" => Enum.flat_map(role_overrides, &Map.get(&1, "allow", []))
          }

          base
          |> MapSet.new()
          |> apply_override(everyone)
          |> apply_override(combined)
          |> apply_override(Map.get(overwrites, user_id, %{}))
          |> MapSet.to_list()
      end
    end
  end

  def allowed?(user_id, room, permission), do: permission in for_room(user_id, room)

  defp apply_override(base, rule),
    do:
      base
      |> MapSet.difference(MapSet.new(Map.get(rule, "deny", [])))
      |> MapSet.union(MapSet.new(Map.get(rule, "allow", [])))

  def settings(user, server_id) do
    if Chat.member?(user.id, server_id) do
      server = Repo.get!(Server, server_id)

      roles =
        Repo.all(
          from r in Role,
            where: r.server_id == ^server_id,
            order_by: [desc: r.position, asc: r.id]
        )

      {:ok,
       %{
         roles:
           Enum.map(
             roles,
             &Map.put(role_json(&1), :editable, editable_role?(user.id, server, &1))
           ),
         owner_id: server.owner_id,
         manageable_members:
           Repo.all(from m in Membership, where: m.server_id == ^server_id)
           |> Enum.filter(&manageable_member?(user.id, server, &1.user_id))
           |> Enum.map(& &1.user_id),
         everyone: Map.get(server.data, "permissions", @defaults),
         permissions: for_server(user.id, server_id),
         can_manage_roles: manager?(user.id, server_id)
       }}
    else
      {:error, :forbidden}
    end
  end

  def role_json(r),
    do: %{
      id: r.id,
      position: r.position,
      name: r.data["name"],
      color: r.data["color"],
      emoji: r.data["emoji"] || "",
      permissions: r.data["permissions"]
    }

  defp manager?(user_id, server_id), do: "administrator" in for_server(user_id, server_id)

  defp rank(user_id, server_id) do
    case Repo.get_by(Membership, user_id: user_id, server_id: server_id) do
      nil ->
        0

      m ->
        ids = (m.data || %{})["role_ids"] || []

        Repo.one(
          from r in Role,
            where: r.server_id == ^server_id and r.id in ^ids,
            select: max(r.position)
        ) || 0
    end
  end

  defp editable_role?(user_id, server, role) do
    manager?(user_id, server.id) and
      (server.owner_id == user_id or role.position < rank(user_id, server.id))
  end

  defp manageable_member?(user_id, server, target) do
    target != server.owner_id and manager?(user_id, server.id) and
      (server.owner_id == user_id or
         (target != user_id and rank(target, server.id) < rank(user_id, server.id)))
  end

  defp grantable?(user_id, server, values) do
    server.owner_id == user_id or Enum.all?(values, &(&1 in for_server(user_id, server.id)))
  end

  # Serialize hierarchy changes per server so authorization and writes use the same state.
  defp mutate(user, server_id, fun) do
    result =
      if Chat.uuid?(server_id) do
        Repo.transact(fn ->
          server = Repo.one(from s in Server, where: s.id == ^server_id, lock: "FOR UPDATE")
          if server && manager?(user.id, server_id), do: fun.(server), else: {:error, :forbidden}
        end)
      else
        {:error, :forbidden}
      end

    if match?({:ok, _}, result), do: notify(server_id)
    result
  end

  def save_role(user, server_id, id, params) do
    mutate(user, server_id, fn server ->
      role = role_for_update(id, server_id)

      with true <- valid?(params["permissions"]),
           name when is_binary(name) <- params["name"],
           true <- String.length(String.trim(name)) in 2..40,
           color when is_binary(color) <- params["color"],
           true <- Regex.match?(~r/^#[0-9a-fA-F]{6}$/, color),
           %Role{} <- role,
           emoji <- Map.get(params, "emoji", (role.data || %{})["emoji"] || ""),
           true <- valid_emoji?(emoji),
           true <- is_nil(id) or editable_role?(user.id, server, role),
           true <- grantable?(user.id, server, params["permissions"]),
           true <- not is_nil(id) or server.owner_id == user.id or rank(user.id, server_id) > 0 do
        role =
          if is_nil(id) do
            # New roles start at the bottom, below every existing role.
            Repo.update_all(from(r in Role, where: r.server_id == ^server_id), inc: [position: 1])
            %{role | position: 1}
          else
            role
          end

        data =
          Map.take(params, ["name", "color", "permissions"])
          |> Map.put("name", String.trim(name))
          |> Map.put("emoji", emoji)

        case role |> Ecto.Changeset.change(data: data) |> Repo.insert_or_update() do
          {:ok, r} -> {:ok, role_json(r)}
          error -> error
        end
      else
        _ -> {:error, :forbidden}
      end
    end)
  end

  # One optional Unicode grapheme supports skin tones, flags and joined emoji.
  defp valid_emoji?(value) when is_binary(value) and byte_size(value) <= 64,
    do:
      String.valid?(value) and String.length(value) <= 1 and not Regex.match?(~r/\p{Cc}/u, value)

  defp valid_emoji?(_), do: false

  defp role_for_update(nil, server_id), do: %Role{server_id: server_id}

  defp role_for_update(id, server_id) do
    if Chat.uuid?(id), do: Repo.get_by(Role, id: id, server_id: server_id)
  end

  def set_everyone(user, server_id, values) do
    mutate(user, server_id, fn server ->
      if valid?(values) and "administrator" not in values and "manage_roles" not in values and
           grantable?(user.id, server, values) do
        case Repo.update(
               Ecto.Changeset.change(server, data: Map.put(server.data, "permissions", values))
             ) do
          {:ok, _} -> {:ok, %{ok: true}}
          error -> error
        end
      else
        {:error, :forbidden}
      end
    end)
  end

  def assign_roles(user, server_id, target, ids) do
    mutate(user, server_id, fn server -> assign_member_roles(user, server, target, ids) end)
  end

  # Toggle exactly one role against the current membership under the server lock.
  # Concurrent administrators cannot overwrite each other's unrelated assignments.
  def set_member_role(user, server_id, target, role_id, enabled) when is_boolean(enabled) do
    mutate(user, server_id, fn server ->
      with true <- Chat.uuid?(target) and Chat.uuid?(role_id),
           %Role{} = role <- Repo.get_by(Role, id: role_id, server_id: server_id),
           true <- editable_role?(user.id, server, role),
           %Membership{} = member <-
             Repo.get_by(Membership, user_id: target, server_id: server_id) do
        current = (member.data || %{})["role_ids"] || []
        ids = if enabled, do: Enum.uniq([role_id | current]), else: List.delete(current, role_id)
        assign_member_roles(user, server, target, ids)
      else
        _ -> {:error, :forbidden}
      end
    end)
  end

  def set_member_role(_, _, _, _, _), do: {:error, :invalid}

  defp assign_member_roles(user, server, target, ids) do
    server_id = server.id

    with true <- Chat.uuid?(target),
         true <- is_list(ids) and length(ids) <= 30 and Enum.all?(ids, &Chat.uuid?/1),
         true <- manageable_member?(user.id, server, target),
         %Membership{} = membership <-
           Repo.get_by(Membership, user_id: target, server_id: server_id) do
      ids = Enum.uniq(ids)
      old = (membership.data || %{})["role_ids"] || []

      changed =
        MapSet.symmetric_difference(MapSet.new(ids), MapSet.new(old)) |> MapSet.to_list()

      roles = Repo.all(from r in Role, where: r.server_id == ^server_id and r.id in ^ids)

      changed_roles =
        Repo.all(from r in Role, where: r.server_id == ^server_id and r.id in ^changed)

      if length(roles) == length(ids) and length(changed_roles) == length(changed) and
           Enum.all?(
             changed_roles,
             &(editable_role?(user.id, server, &1) and
                 grantable?(user.id, server, &1.data["permissions"]))
           ) do
        Repo.update!(
          Ecto.Changeset.change(membership,
            data: Map.put(membership.data || %{}, "role_ids", ids)
          )
        )

        {:ok, %{ok: true}}
      else
        {:error, :forbidden}
      end
    else
      _ -> {:error, :forbidden}
    end
  end

  def reorder_roles(user, server_id, ids) do
    mutate(user, server_id, fn server ->
      roles =
        Repo.all(
          from r in Role,
            where: r.server_id == ^server_id,
            order_by: [desc: r.position, asc: r.id]
        )

      if is_list(ids) and length(ids) == length(roles) and
           MapSet.new(ids) == MapSet.new(roles, & &1.id) do
        original = Enum.map(roles, & &1.id)
        movable = Enum.filter(roles, &editable_role?(user.id, server, &1)) |> MapSet.new(& &1.id)

        safe =
          Enum.zip(original, ids)
          |> Enum.all?(fn {a, b} ->
            a == b or (MapSet.member?(movable, a) and MapSet.member?(movable, b))
          end)

        if safe do
          for {id, index} <- Enum.with_index(ids),
              do:
                Repo.update_all(from(r in Role, where: r.id == ^id and r.server_id == ^server_id),
                  set: [position: length(ids) - index]
                )

          {:ok, %{ok: true}}
        else
          {:error, :forbidden}
        end
      else
        {:error, :invalid_order}
      end
    end)
  end

  def delete_role(user, server_id, id) do
    mutate(user, server_id, fn server ->
      with %Role{} = role <- role_for_update(id, server_id),
           true <- not is_nil(id) and editable_role?(user.id, server, role) do
        for m <- Repo.all(from m in Membership, where: m.server_id == ^server_id) do
          data = Map.update(m.data || %{}, "role_ids", [], &List.delete(&1, id))
          Repo.update!(Ecto.Changeset.change(m, data: data))
        end

        for r <- Repo.all(from r in Room, where: r.server_id == ^server_id) do
          data = Map.update(r.data, "overwrites", %{}, &Map.delete(&1, id))
          Repo.update!(Ecto.Changeset.change(r, data: data))
        end

        Repo.delete!(role)
        {:ok, %{ok: true}}
      else
        _ -> {:error, :forbidden}
      end
    end)
  end

  def room_settings(user, room_id) do
    with {:ok, room} <- Chat.room(user.id, room_id),
         true <- allowed?(user.id, room, "manage_channels") do
      {:ok, %{overwrites: room.data["overwrites"] || %{}}}
    else
      _ -> {:error, :forbidden}
    end
  end

  def set_overrides(user, room_id, overwrites) do
    with {:ok, room} <- Chat.room(user.id, room_id),
         true <- allowed?(user.id, room, "manage_channels"),
         true <- valid_overrides?(room.server_id, overwrites),
         true <-
           Chat.owner?(user.id, room.server_id) or safe_overrides?(user.id, room, overwrites) do
      Repo.update!(
        Ecto.Changeset.change(room, data: Map.put(room.data, "overwrites", overwrites))
      )

      notify(room.server_id)
      {:ok, %{ok: true}}
    else
      _ -> {:error, :forbidden}
    end
  end

  # Managers cannot use an override to grant permissions they do not themselves hold.
  defp safe_overrides?(user_id, room, overrides) do
    held = for_room(user_id, room)
    candidate = for_room(user_id, %{room | data: Map.put(room.data, "overwrites", overrides)})

    MapSet.subset?(MapSet.new(candidate), MapSet.new(held)) and
      Enum.all?(overrides, fn {_, rule} -> Enum.all?(rule["allow"], &(&1 in held)) end)
  end

  defp valid_overrides?(server_id, overrides)
       when is_map(overrides) and map_size(overrides) <= 100 do
    roles = Repo.all(from r in Role, where: r.server_id == ^server_id, select: r.id)
    members = Repo.all(from m in Membership, where: m.server_id == ^server_id, select: m.user_id)
    targets = ["everyone" | roles ++ members]

    Enum.all?(overrides, fn {target, rule} ->
      target in targets and is_map(rule) and Enum.sort(Map.keys(rule)) == ["allow", "deny"] and
        valid?(rule["allow"]) and valid?(rule["deny"]) and "administrator" not in rule["allow"] and
        "administrator" not in rule["deny"] and
        "manage_roles" not in rule["allow"] and "manage_roles" not in rule["deny"] and
        MapSet.disjoint?(MapSet.new(rule["allow"]), MapSet.new(rule["deny"]))
    end)
  end

  defp valid_overrides?(_, _), do: false

  def notify(server_id) do
    OpenchatWeb.Endpoint.broadcast("server:" <> server_id, "refresh", %{})

    for id <- Repo.all(from r in Room, where: r.server_id == ^server_id, select: r.id) do
      OpenchatWeb.Endpoint.broadcast("room:" <> id, "access_changed", %{})
    end
  end
end
