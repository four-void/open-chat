defmodule Openchat.MessageActions do
  import Ecto.Query
  alias Openchat.{Repo, Chat, Direct, Permissions, Accounts}
  alias Openchat.Chat.{Message, DirectMessage}
  @emojis ~w(👍 ❤️ 😂 🎉 😮 😢 👀 🔥 ✅ 🙏 🚀 👎)
  def emojis, do: @emojis

  def change(user, kind, id, action, params) when kind in [:room, :direct] do
    schema = if kind == :room, do: Message, else: DirectMessage

    result =
      if Chat.uuid?(id) do
        Repo.transact(fn ->
          with message when not is_nil(message) <-
                 Repo.one(from m in schema, where: m.id == ^id, lock: "FOR UPDATE"),
               {:ok, access} <- access(user, kind, message),
               {:ok, fields} <- changes(user, message, access, action, params) do
            Repo.update(Ecto.Changeset.change(message, fields))
          else
            _ -> {:error, :forbidden}
          end
        end)
      else
        {:error, :invalid}
      end

    case result do
      {:ok, m} ->
        json = if kind == :room, do: Chat.message_json(m), else: Direct.message_json(m)
        broadcast(kind, m, Map.put(json, :mutation, true))
        {:ok, json}

      error ->
        error
    end
  end

  defp access(user, :room, m) do
    with {:ok, room} <- Chat.room(user.id, m.room_id), true <- room.kind == "text" do
      {:ok, %{send: Permissions.allowed?(user.id, room, "send")}}
    else
      _ -> {:error, :forbidden}
    end
  end

  defp access(user, :direct, m) do
    with {:ok, _} <- Direct.conversation(user.id, m.conversation_id), do: {:ok, %{send: true}}
  end

  defp changes(user, m, access, :edit, %{"encrypted" => payload}) do
    if m.user_id == user.id and is_nil(m.deleted_at) and access.send and valid_payload?(payload),
      do: {:ok, [data: payload, edited_at: DateTime.utc_now()]},
      else: {:error, :forbidden}
  end

  defp changes(user, m, _, :delete, _) do
    if m.user_id == user.id and is_nil(m.deleted_at),
      do: {:ok, [data: %{}, activity: %{}, deleted_at: DateTime.utc_now()]},
      else: {:error, :forbidden}
  end

  defp changes(user, m, access, :react, %{"emoji" => emoji, "enabled" => enabled})
       when is_boolean(enabled) do
    if is_nil(m.deleted_at) and access.send and emoji in @emojis do
      activity = m.activity || %{}
      reactions = activity["reactions"] || %{}
      ids = reactions[emoji] || []
      ids = if enabled, do: Enum.uniq([user.id | ids]), else: List.delete(ids, user.id)
      # Keep the encrypted metadata field bounded.
      if length(ids) <= 1000 do
        reactions =
          if ids == [], do: Map.delete(reactions, emoji), else: Map.put(reactions, emoji, ids)

        {:ok, [activity: Map.put(activity, "reactions", reactions)]}
      else
        {:error, :too_many_reactions}
      end
    else
      {:error, :forbidden}
    end
  end

  defp changes(_, _, _, _, _), do: {:error, :invalid}

  defp valid_payload?(%{"iv" => iv, "cipher" => cipher, "nonce" => nonce} = p)
       when map_size(p) == 3 and is_binary(cipher) and byte_size(cipher) <= 16000,
       do: Chat.uuid?(nonce) and Accounts.valid_vault?(%{"iv" => iv, "cipher" => cipher})

  defp valid_payload?(_), do: false

  defp broadcast(:room, m, json),
    do: OpenchatWeb.Endpoint.broadcast("room:" <> m.room_id, "message", json)

  defp broadcast(:direct, m, json) do
    c = Repo.get!(Openchat.Chat.DirectConversation, m.conversation_id)

    for id <- [c.first_id, c.second_id],
        do: OpenchatWeb.Endpoint.broadcast("inbox:" <> id, "direct_message", json)
  end
end
