defmodule Openchat.Direct do
  import Ecto.Query
  alias Openchat.{Accounts, Chat, Repo}
  alias Openchat.Chat.{User, Membership, DirectConversation, DirectMessage}

  # Identity is immutable: silently replacing it would make existing history unreadable.
  def publish_identity(user, public_key) do
    if valid_key?(public_key) do
      Repo.transact(fn ->
        current = Repo.one!(from u in User, where: u.id == ^user.id, lock: "FOR UPDATE")

        case current.data["dm_public_key"] do
          nil ->
            current
            |> Ecto.Changeset.change(data: Map.put(current.data, "dm_public_key", public_key))
            |> Repo.update()

          ^public_key ->
            {:ok, current}

          _ ->
            {:error, :identity_conflict}
        end
      end)
    else
      {:error, :invalid_key}
    end
  end

  defp valid_key?(key) when is_binary(key) and byte_size(key) == 88 do
    with {:ok, <<4, _::binary-size(64)>> = bytes} <- Base.decode64(key) do
      try do
        {_public, private} = :crypto.generate_key(:ecdh, :secp256r1)
        is_binary(:crypto.compute_key(:ecdh, bytes, private, :secp256r1))
      rescue
        _ -> false
      end
    else
      _ -> false
    end
  end

  defp valid_key?(_), do: false

  def contacts(user) do
    own_servers = from m in Membership, where: m.user_id == ^user.id, select: m.server_id

    Repo.all(
      from u in User,
        join: m in Membership,
        on: m.user_id == u.id,
        where: m.server_id in subquery(own_servers) and u.id != ^user.id,
        distinct: true
    )
    |> Kernel.++(
      Repo.all(
        from u in User,
          where:
            u.id in ^(Openchat.Friends.list(user)
                      |> Enum.filter(&(&1.status == "accepted"))
                      |> Enum.map(& &1.peer.id))
      )
    )
    |> Enum.uniq_by(& &1.id)
    |> Enum.map(&Map.put(Accounts.public(&1), :ready, is_binary(&1.data["dm_public_key"])))
    |> Enum.sort_by(&String.downcase(&1.name))
  end

  defp shared_server?(a, b) do
    Repo.exists?(
      from x in Membership,
        join: y in Membership,
        on: x.server_id == y.server_id,
        where: x.user_id == ^a and y.user_id == ^b
    )
  end

  def start(user, target_id) do
    with true <- Chat.uuid?(target_id) and target_id != user.id,
         %User{} = target <- Repo.get(User, target_id),
         %User{} = current <- Repo.get(User, user.id),
         true <-
           is_binary(current.data["dm_public_key"]) and is_binary(target.data["dm_public_key"]),
         [first, second] <- Enum.sort([user.id, target_id]),
         existing <- Repo.get_by(DirectConversation, first_id: first, second_id: second),
         true <-
           not is_nil(existing) or shared_server?(user.id, target_id) or
             Openchat.Friends.accepted?(user.id, target_id) do
      Repo.insert!(%DirectConversation{first_id: first, second_id: second},
        on_conflict: :nothing,
        conflict_target: [:first_id, :second_id]
      )

      conversation = Repo.get_by!(DirectConversation, first_id: first, second_id: second)
      {:ok, json(conversation, user.id)}
    else
      _ -> {:error, :forbidden}
    end
  end

  def list(user) do
    Repo.all(
      from c in DirectConversation,
        where: c.first_id == ^user.id or c.second_id == ^user.id,
        order_by: [desc: c.updated_at, desc: c.id]
    )
    |> Enum.map(&json(&1, user.id))
  end

  def conversation(user_id, id) do
    with true <- Chat.uuid?(id),
         %DirectConversation{} = c <- Repo.get(DirectConversation, id),
         true <- user_id in [c.first_id, c.second_id],
         do: {:ok, c},
         else: (_ -> {:error, :forbidden})
  end

  def json(c, user_id) do
    other = Repo.get!(User, if(c.first_id == user_id, do: c.second_id, else: c.first_id))

    %{
      id: c.id,
      peer: Accounts.public(other),
      public_key: other.data["dm_public_key"],
      updated_at: c.updated_at
    }
  end

  def history(user, id, before_id \\ nil) do
    with {:ok, c} <- conversation(user.id, id) do
      query =
        from m in DirectMessage,
          where: m.conversation_id == ^id,
          order_by: [desc: m.inserted_at, desc: m.id],
          limit: 50

      query =
        case before_id && Chat.uuid?(before_id) &&
               Repo.get_by(DirectMessage, id: before_id, conversation_id: id) do
          %DirectMessage{} = cursor ->
            from m in query,
              where:
                m.inserted_at < ^cursor.inserted_at or
                  (m.inserted_at == ^cursor.inserted_at and m.id < ^cursor.id)

          _ ->
            query
        end

      {:ok,
       %{
         conversation: json(c, user.id),
         messages: query |> Repo.all() |> Enum.reverse() |> Enum.map(&message_json/1)
       }}
    end
  end

  def send_message(user, id, payload) do
    with {:ok, c} <- conversation(user.id, id), true <- valid_message?(payload) do
      result =
        Repo.transact(fn ->
          message =
            Repo.insert!(%DirectMessage{conversation_id: id, user_id: user.id, data: payload})

          # Record recent conversation activity without storing a plaintext preview.
          Repo.update_all(from(c in DirectConversation, where: c.id == ^id),
            set: [updated_at: DateTime.utc_now()]
          )

          {:ok, message_json(message)}
        end)

      case result do
        {:ok, message} ->
          for participant <- [c.first_id, c.second_id],
              do:
                OpenchatWeb.Endpoint.broadcast("inbox:" <> participant, "direct_message", message)

          {:ok, message}

        error ->
          error
      end
    else
      _ -> {:error, :forbidden}
    end
  end

  def message_json(m),
    do: %{
      id: m.id,
      conversation_id: m.conversation_id,
      user_id: m.user_id,
      encrypted: if(m.deleted_at, do: nil, else: m.data),
      edited_at: m.edited_at,
      deleted_at: m.deleted_at,
      updated_at: m.updated_at,
      reactions: (m.activity || %{})["reactions"] || %{},
      inserted_at: m.inserted_at
    }

  defp valid_message?(%{"iv" => iv, "cipher" => cipher, "nonce" => nonce} = p)
       when map_size(p) == 3 and is_binary(cipher) and byte_size(cipher) <= 16000 do
    Chat.uuid?(nonce) and Accounts.valid_vault?(%{"iv" => iv, "cipher" => cipher})
  end

  defp valid_message?(_), do: false
end
