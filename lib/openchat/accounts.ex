defmodule Openchat.Accounts do
  import Ecto.Query
  alias Openchat.Repo
  alias Openchat.Chat.{User, Session}
  alias Openchat.Security.Crypto

  def register(params) do
    with email when is_binary(email) <- params["email"],
         true <- byte_size(email) <= 254 and Regex.match?(~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, email),
         password when is_binary(password) <- params["password"],
         true <- String.length(password) >= 12 and byte_size(password) <= 256,
         name when is_binary(name) <- params["name"],
         true <- String.length(String.trim(name)) in 2..40,
         true <- valid_vault?(params["vault"]),
         salt when is_binary(salt) <- params["salt"],
         {:ok, <<_::128>>} <- Base.decode64(salt) do
      %User{
        email_index: Crypto.blind(normalize(email)),
        password_hash: Crypto.password(password),
        data: %{
          "email" => normalize(email),
          "name" => String.trim(name),
          "salt" => salt,
          "vault" => params["vault"]
        }
      }
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.unique_constraint(:email_index)
      |> Repo.insert()
    else
      _ -> {:error, :invalid_registration}
    end
  end

  def authenticate(email, password)
      when is_binary(email) and is_binary(password) and byte_size(password) <= 256 do
    user = Repo.get_by(User, email_index: Crypto.blind(normalize(email)))
    valid = Crypto.verify(password, user && user.password_hash)
    if user && valid, do: {:ok, user}, else: {:error, :invalid_credentials}
  end

  def authenticate(_, _), do: {:error, :invalid_credentials}

  def create_session(user) do
    token = Crypto.token()

    Repo.insert!(%Session{
      user_id: user.id,
      token_hash: Crypto.digest(token),
      expires_at: DateTime.add(DateTime.utc_now(:second), 86400)
    })

    token
  end

  def session(token) when is_binary(token) do
    hash = Crypto.digest(token)

    Repo.one(
      from s in Session,
        join: u in User,
        on: u.id == s.user_id,
        where: s.token_hash == ^hash and s.expires_at > ^DateTime.utc_now(:second),
        select: {s, u}
    )
  end

  def session(_), do: nil

  def revoke(token) when is_binary(token) do
    hash = Crypto.digest(token)
    Repo.delete_all(from s in Session, where: s.token_hash == ^hash)

    OpenchatWeb.Endpoint.broadcast(
      "session:" <> Base.url_encode64(hash, padding: false),
      "disconnect",
      %{}
    )
  end

  def revoke(_), do: :ok

  def public(user),
    do:
      Map.merge(
        %{id: user.id, name: user.data["name"], username: user.username},
        Map.take(user.data, ["bio", "avatar", "color", "status"])
      )

  def update_profile(user, params) do
    fields = Map.take(params, ["name", "bio", "avatar", "color", "status"])

    valid =
      Enum.all?(fields, fn
        {"name", v} ->
          is_binary(v) and String.length(String.trim(v)) in 2..40

        {"bio", v} ->
          is_binary(v) and String.length(v) <= 500

        {"status", v} ->
          is_binary(v) and String.length(v) <= 80

        {"color", v} ->
          is_binary(v) and Regex.match?(~r/^#[0-9a-fA-F]{6}$/, v)

        {"avatar", v} ->
          is_binary(v) and
            (v == "" or
               (byte_size(v) <= 200_000 and
                  Regex.match?(~r/^data:image\/(png|jpeg|webp);base64,[A-Za-z0-9+\/=]+$/, v)))
      end)

    username =
      if Map.has_key?(params, "username"),
        do: normalize_username(params["username"]),
        else: user.username

    if valid and (not Map.has_key?(params, "username") or valid_username?(username)) do
      Repo.transact(fn ->
        current = Repo.one!(from u in User, where: u.id == ^user.id, lock: "FOR UPDATE")

        fields =
          if Map.has_key?(fields, "name"),
            do: Map.update!(fields, "name", &String.trim/1),
            else: fields

        changes = %{data: Map.merge(current.data, fields)}

        changes =
          if Map.has_key?(params, "username"),
            do: Map.put(changes, :username, username),
            else: changes

        current
        |> Ecto.Changeset.change(changes)
        |> Ecto.Changeset.unique_constraint(:username)
        |> Repo.update()
      end)
    else
      {:error, :invalid_profile}
    end
  end

  def normalize_username(value) when is_binary(value),
    do: value |> String.trim() |> String.replace_prefix("@", "") |> String.downcase()

  def normalize_username(_), do: nil
  def valid_username?(value), do: is_binary(value) and Regex.match?(~r/^[a-z0-9_]{3,24}$/, value)

  def username_available?(user, value) do
    username = normalize_username(value)

    valid_username?(username) and
      not Repo.exists?(from u in User, where: u.username == ^username and u.id != ^user.id)
  end

  def update_credentials(user, params) do
    Repo.transact(fn ->
      current = Repo.one!(from u in User, where: u.id == ^user.id, lock: "FOR UPDATE")

      with true <-
             is_binary(params["current_password"]) and
               byte_size(params["current_password"]) <= 256,
           true <- Crypto.verify(params["current_password"], current.password_hash),
           email when is_binary(email) <- params["email"],
           true <- byte_size(email) <= 254 and Regex.match?(~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, email),
           password when is_binary(password) <- params["password"],
           true <- byte_size(password) in 12..256,
           true <- valid_vault?(params["vault"]),
           salt when is_binary(salt) <- params["salt"],
           {:ok, <<_::128>>} <- Base.decode64(salt),
           true <- current.data["vault"] == params["previous"] do
        data =
          Map.merge(current.data, Map.take(params, ["vault", "salt"]))
          |> Map.put("email", normalize(email))

        current
        |> Ecto.Changeset.change(
          data: data,
          email_index: Crypto.blind(normalize(email)),
          password_hash: Crypto.password(password)
        )
        |> Ecto.Changeset.unique_constraint(:email_index)
        |> Repo.update()
      else
        _ -> {:error, :invalid_credentials}
      end
    end)
  end

  def revoke_all(user) do
    sessions = Repo.all(from s in Session, where: s.user_id == ^user.id)
    Repo.delete_all(from s in Session, where: s.user_id == ^user.id)

    for s <- sessions,
        do:
          OpenchatWeb.Endpoint.broadcast(
            "session:" <> Base.url_encode64(s.token_hash, padding: false),
            "disconnect",
            %{}
          )

    :ok
  end

  def private(user), do: Map.merge(public(user), Map.take(user.data, ["email", "salt", "vault"]))

  def update_vault(user, vault, previous) do
    if valid_vault?(vault) do
      Repo.transact(fn ->
        current = Repo.one!(from u in User, where: u.id == ^user.id, lock: "FOR UPDATE")

        if current.data["vault"] == previous do
          current
          |> Ecto.Changeset.change(data: Map.put(current.data, "vault", vault))
          |> Repo.update()
        else
          {:error, :stale_vault}
        end
      end)
    else
      {:error, :invalid_vault}
    end
  end

  def valid_vault?(%{"iv" => iv, "cipher" => cipher} = value)
      when map_size(value) == 2 and is_binary(iv) and is_binary(cipher) and
             byte_size(cipher) <= 100_000 do
    with {:ok, <<_::96>>} <- Base.decode64(iv),
         {:ok, bytes} <- Base.decode64(cipher),
         true <- byte_size(bytes) >= 16,
         do: true,
         else: (_ -> false)
  end

  def valid_vault?(_), do: false
  defp normalize(email), do: email |> String.trim() |> String.downcase()
end
