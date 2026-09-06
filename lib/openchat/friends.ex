defmodule Openchat.Friends do
  import Ecto.Query
  alias Openchat.{Repo, Accounts, Chat}
  alias Openchat.Chat.{Friendship, User}

  def list(user) do
    Repo.all(from f in Friendship, where: f.first_id == ^user.id or f.second_id == ^user.id)
    |> Enum.map(fn f ->
      peer = Repo.get!(User, if(f.first_id == user.id, do: f.second_id, else: f.first_id))

      %{
        id: f.id,
        peer: Accounts.public(peer),
        status:
          if(f.accepted,
            do: "accepted",
            else: if(f.requester_id == user.id, do: "outgoing", else: "incoming")
          )
      }
    end)
  end

  def accepted?(a, b),
    do:
      Repo.exists?(
        from f in Friendship,
          where:
            f.accepted and
              ((f.first_id == ^a and f.second_id == ^b) or
                 (f.first_id == ^b and f.second_id == ^a))
      )

  def request_username(user, value) do
    username = Accounts.normalize_username(value)

    with true <- Accounts.valid_username?(username),
         %User{} = target <- Repo.get_by(User, username: username) do
      request(user, target.id)
    else
      _ -> {:error, :unknown_username}
    end
  end

  def request(user, target) do
    with true <- Chat.uuid?(target) and target != user.id,
         %User{} <- Repo.get(User, target) do
      [first, second] = Enum.sort([user.id, target])

      result =
        %Friendship{first_id: first, second_id: second, requester_id: user.id}
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.unique_constraint([:first_id, :second_id])
        |> Repo.insert()

      notify(result)
    else
      _ -> {:error, :invalid_target}
    end
  end

  def change(user, id, action) do
    with true <- Chat.uuid?(id) do
      Repo.transact(fn ->
        f = Repo.one(from f in Friendship, where: f.id == ^id, lock: "FOR UPDATE")

        cond do
          is_nil(f) ->
            {:error, :missing}

          user.id not in [f.first_id, f.second_id] ->
            {:error, :forbidden}

          action == :delete ->
            Repo.delete(f)

          action == :accept and not f.accepted and f.requester_id != user.id ->
            f |> Ecto.Changeset.change(accepted: true) |> Repo.update()

          true ->
            {:error, :forbidden}
        end
      end)
      |> notify()
    else
      _ -> {:error, :invalid_id}
    end
  end

  defp notify({:ok, f} = result) do
    for id <- [f.first_id, f.second_id],
        do: OpenchatWeb.Endpoint.broadcast("inbox:" <> id, "friends_changed", %{})

    result
  end

  defp notify(result), do: result
end
