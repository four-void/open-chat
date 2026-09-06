defmodule Openchat.Chat do
  import Ecto.Query
  alias Openchat.Repo
  alias Openchat.Chat.{User, Server, Membership, Room, Message, Invite}
  alias Openchat.Security.Crypto
  alias Openchat.Permissions
  alias Openchat.Chat.Thread

  def uuid?(id), do: match?({:ok, _}, Ecto.UUID.cast(id))

  def member?(user_id, server_id) do
    uuid?(server_id) and
      Repo.exists?(
        from m in Membership, where: m.user_id == ^user_id and m.server_id == ^server_id
      )
  end

  def owner?(user_id, server_id) do
    uuid?(server_id) and
      Repo.exists?(from s in Server, where: s.id == ^server_id and s.owner_id == ^user_id)
  end

  def servers(user) do
    Repo.all(
      from s in Server,
        join: m in Membership,
        on: m.server_id == s.id,
        where: m.user_id == ^user.id,
        order_by: s.inserted_at
    )
    |> Enum.map(&server_json/1)
  end

  def server_json(s), do: %{id: s.id, name: s.data["name"], owner_id: s.owner_id}

  def room_json(r, user_id) do
    %{
      id: r.id,
      server_id: r.server_id,
      kind: r.kind,
      name: r.data["name"],
      permissions: Permissions.for_room(user_id, r),
      restricted: Map.get(r.data, "overwrites", %{}) != %{}
    }
  end

  def create_server(user, name) do
    if valid_name?(name) do
      Repo.transact(fn ->
        server = Repo.insert!(%Server{owner_id: user.id, data: %{"name" => String.trim(name)}})
        Repo.insert!(%Membership{user_id: user.id, server_id: server.id})
        Repo.insert!(%Room{server_id: server.id, kind: "text", data: %{"name" => "général"}})
        Repo.insert!(%Room{server_id: server.id, kind: "voice", data: %{"name" => "Le salon"}})
        {:ok, server_json(server)}
      end)
    else
      {:error, :invalid_name}
    end
  end

  def rooms(user, server_id) do
    if member?(user.id, server_id),
      do:
        {:ok,
         Repo.all(from r in Room, where: r.server_id == ^server_id, order_by: r.inserted_at)
         |> Enum.filter(&Permissions.allowed?(user.id, &1, "view"))
         |> Enum.map(&room_json(&1, user.id))},
      else: {:error, :forbidden}
  end

  def members(user, server_id) do
    if member?(user.id, server_id) do
      {:ok,
       Repo.all(
         from u in User,
           join: m in Membership,
           on: m.user_id == u.id,
           where: m.server_id == ^server_id,
           select: {u, m}
       )
       |> Enum.map(fn {u, m} ->
         Map.put(Openchat.Accounts.public(u), :role_ids, (m.data || %{})["role_ids"] || [])
       end)}
    else
      {:error, :forbidden}
    end
  end

  def create_room(user, server_id, name, kind) do
    if "manage_channels" in Permissions.for_server(user.id, server_id) and valid_name?(name) and
         kind in ["text", "voice"] do
      room =
        Repo.insert!(%Room{
          server_id: server_id,
          kind: kind,
          data: %{"name" => String.trim(name)}
        })

      OpenchatWeb.Endpoint.broadcast("server:" <> server_id, "refresh", %{})
      {:ok, room_json(room, user.id)}
    else
      {:error, :forbidden}
    end
  end

  def room(user_id, id) do
    with true <- uuid?(id),
         %Room{} = room <- Repo.get(Room, id),
         true <- Permissions.allowed?(user_id, room, "view"),
         do: {:ok, room},
         else: (_ -> {:error, :forbidden})
  end

  def history(user, room_id, before_id \\ nil) do
    with {:ok, room} <- room(user.id, room_id), true <- room.kind == "text" do
      query =
        from m in Message,
          where: m.room_id == ^room_id and is_nil(m.thread_id),
          order_by: [desc: m.inserted_at, desc: m.id],
          limit: 50

      query =
        case before_id && uuid?(before_id) &&
               Repo.get_by(Message, id: before_id, room_id: room_id) do
          %Message{} = cursor ->
            from m in query,
              where:
                m.inserted_at < ^cursor.inserted_at or
                  (m.inserted_at == ^cursor.inserted_at and m.id < ^cursor.id)

          _ ->
            query
        end

      {:ok, query |> Repo.all() |> Enum.reverse() |> decorate_threads()}
    else
      _ -> {:error, :forbidden}
    end
  end

  def send_message(user, room_id, payload) do
    with {:ok, room} <- room(user.id, room_id),
         true <- room.kind == "text",
         true <- Permissions.allowed?(user.id, room, "send"),
         true <- valid_message?(payload) do
      message = Repo.insert!(%Message{room_id: room_id, user_id: user.id, data: payload})
      {:ok, message_json(message)}
    else
      _ -> {:error, :invalid_message}
    end
  end

  def message_json(m),
    do: %{
      id: m.id,
      room_id: m.room_id,
      user_id: m.user_id,
      encrypted: if(m.deleted_at, do: nil, else: m.data),
      edited_at: m.edited_at,
      deleted_at: m.deleted_at,
      updated_at: m.updated_at,
      reactions: (m.activity || %{})["reactions"] || %{},
      inserted_at: m.inserted_at,
      thread_id: m.thread_id,
      thread: nil
    }

  def decorate_threads(messages) do
    ids = Enum.map(messages, & &1.id)
    threads = Repo.all(from t in Thread, where: t.root_message_id in ^ids)
    thread_ids = Enum.map(threads, & &1.id)

    counts =
      Repo.all(
        from m in Message,
          where: m.thread_id in ^thread_ids,
          group_by: m.thread_id,
          select: {m.thread_id, count(m.id)}
      )
      |> Map.new()

    by_root =
      Map.new(threads, fn t ->
        {t.root_message_id,
         %{id: t.id, count: Map.get(counts, t.id, 0), archived: not is_nil(t.archived_at)}}
      end)

    Enum.map(messages, fn m -> Map.put(message_json(m), :thread, Map.get(by_root, m.id)) end)
  end

  def create_thread(user, message_id) do
    with true <- uuid?(message_id),
         %Message{thread_id: nil, deleted_at: nil} = root <- Repo.get(Message, message_id),
         {:ok, room} <- room(user.id, root.room_id),
         true <- room.kind == "text",
         true <- Permissions.allowed?(user.id, room, "create_threads"),
         true <- Permissions.allowed?(user.id, room, "send") do
      Repo.insert!(%Thread{room_id: room.id, root_message_id: root.id, user_id: user.id},
        on_conflict: :nothing,
        conflict_target: [:root_message_id]
      )

      thread = Repo.get_by!(Thread, root_message_id: root.id)
      notify_thread(thread)
      {:ok, thread_json(thread)}
    else
      _ -> {:error, :forbidden}
    end
  end

  def threads(user, room_id) do
    with {:ok, _} <- room(user.id, room_id) do
      {:ok,
       Repo.all(
         from t in Thread,
           where: t.room_id == ^room_id,
           order_by: [desc: t.inserted_at],
           limit: 100
       )
       |> Enum.map(&thread_json/1)}
    end
  end

  def thread(user, id) do
    with true <- uuid?(id),
         %Thread{} = thread <- Repo.get(Thread, id),
         {:ok, room} <- room(user.id, thread.room_id),
         do: {:ok, thread, room},
         else: (_ -> {:error, :forbidden})
  end

  def thread_json(t) do
    %{
      id: t.id,
      room_id: t.room_id,
      user_id: t.user_id,
      root: Repo.get!(Message, t.root_message_id) |> message_json(),
      archived: not is_nil(t.archived_at),
      count: Repo.aggregate(from(m in Message, where: m.thread_id == ^t.id), :count)
    }
  end

  def thread_history(user, id, before_id \\ nil) do
    with {:ok, thread, _} <- thread(user, id) do
      query =
        from m in Message,
          where: m.thread_id == ^id,
          order_by: [desc: m.inserted_at, desc: m.id],
          limit: 50

      query =
        case before_id && uuid?(before_id) && Repo.get_by(Message, id: before_id, thread_id: id) do
          %Message{} = cursor ->
            from m in query,
              where:
                m.inserted_at < ^cursor.inserted_at or
                  (m.inserted_at == ^cursor.inserted_at and m.id < ^cursor.id)

          _ ->
            query
        end

      {:ok,
       %{
         thread: thread_json(thread),
         messages: query |> Repo.all() |> Enum.reverse() |> Enum.map(&message_json/1)
       }}
    end
  end

  def reply_thread(user, id, room_id, payload) do
    with {:ok, thread, room} <- thread(user, id),
         true <- thread.room_id == room_id,
         true <- Permissions.allowed?(user.id, room, "send"),
         true <- is_nil(thread.archived_at),
         true <- valid_message?(payload) do
      message =
        Repo.insert!(%Message{room_id: room_id, user_id: user.id, thread_id: id, data: payload})

      notify_thread(thread)
      {:ok, message_json(message)}
    else
      _ -> {:error, :forbidden}
    end
  end

  def archive_thread(user, id, archived) when is_boolean(archived) do
    with {:ok, thread, room} <- thread(user, id),
         true <-
           thread.user_id == user.id or Permissions.allowed?(user.id, room, "manage_threads") do
      thread =
        Repo.update!(
          Ecto.Changeset.change(thread, archived_at: if(archived, do: DateTime.utc_now(:second)))
        )

      notify_thread(thread)
      {:ok, thread_json(thread)}
    else
      _ -> {:error, :forbidden}
    end
  end

  def archive_thread(_, _, _), do: {:error, :invalid}

  defp notify_thread(thread),
    do:
      OpenchatWeb.Endpoint.broadcast("room:" <> thread.room_id, "thread_changed", %{
        thread_id: thread.id,
        root_message_id: thread.root_message_id
      })

  defp valid_message?(%{"iv" => iv, "cipher" => cipher, "nonce" => nonce} = p)
       when map_size(p) == 3 and is_binary(cipher) and byte_size(cipher) <= 16000 do
    uuid?(nonce) and Openchat.Accounts.valid_vault?(%{"iv" => iv, "cipher" => cipher})
  end

  defp valid_message?(_), do: false

  def invite(user, server_id) do
    if "invite" in Permissions.for_server(user.id, server_id) do
      token = Crypto.token()

      Repo.insert!(%Invite{
        server_id: server_id,
        token_hash: Crypto.digest(token),
        expires_at: DateTime.add(DateTime.utc_now(:second), 86400)
      })

      {:ok, %{token: token}}
    else
      {:error, :forbidden}
    end
  end

  def accept(user, token) when is_binary(token) and byte_size(token) <= 100 do
    hash = Crypto.digest(token)

    case Repo.one(
           from i in Invite,
             where: i.token_hash == ^hash and i.expires_at > ^DateTime.utc_now(:second)
         ) do
      nil ->
        {:error, :invalid_invite}

      invite ->
        Repo.insert!(%Membership{user_id: user.id, server_id: invite.server_id},
          on_conflict: :nothing,
          conflict_target: [:server_id, :user_id]
        )

        OpenchatWeb.Endpoint.broadcast("server:" <> invite.server_id, "refresh", %{})
        {:ok, Repo.get!(Server, invite.server_id) |> server_json()}
    end
  end

  def accept(_, _), do: {:error, :invalid_invite}
  defp valid_name?(name) when is_binary(name), do: String.length(String.trim(name)) in 2..60
  defp valid_name?(_), do: false
end
