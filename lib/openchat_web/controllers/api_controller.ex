defmodule OpenchatWeb.ApiController do
  use OpenchatWeb, :controller
  alias Openchat.{Accounts, Chat}
  plug :authenticate when action not in [:session, :register, :login]
  plug :rate_limit

  def session(conn, _) do
    case Accounts.session(get_session(conn, :token)) do
      {_session, user} -> authenticated(conn, user)
      nil -> json(conn, %{user: nil})
    end
  end

  def register(conn, params) do
    case Accounts.register(params) do
      {:ok, user} ->
        establish(conn, user)

      _ ->
        error(
          conn,
          422,
          "Inscription impossible. Vérifiez vos informations (mot de passe : 12 caractères minimum)."
        )
    end
  end

  def login(conn, params) do
    case Accounts.authenticate(params["email"], params["password"]) do
      {:ok, user} -> establish(conn, user)
      _ -> error(conn, 401, "Identifiants incorrects.")
    end
  end

  def logout(conn, _) do
    Accounts.revoke(get_session(conn, :token))
    conn |> clear_session() |> configure_session(drop: true) |> json(%{ok: true})
  end

  def vault(conn, %{"vault" => vault, "previous" => previous}),
    do:
      reply(conn, Accounts.update_vault(conn.assigns.user, vault, previous), fn _ ->
        %{ok: true}
      end)

  def vault(conn, _), do: error(conn, 422, "Coffre invalide.")
  def servers(conn, _), do: json(conn, %{servers: Chat.servers(conn.assigns.user)})

  def create_server(conn, params),
    do: reply(conn, Chat.create_server(conn.assigns.user, params["name"]))

  def rooms(conn, %{"id" => id}),
    do: reply(conn, Chat.rooms(conn.assigns.user, id), &%{rooms: &1})

  def members(conn, %{"id" => id}),
    do: reply(conn, Chat.members(conn.assigns.user, id), &%{members: &1})

  def create_room(conn, %{"id" => id} = params),
    do: reply(conn, Chat.create_room(conn.assigns.user, id, params["name"], params["kind"]))

  def messages(conn, %{"id" => id} = params),
    do: reply(conn, Chat.history(conn.assigns.user, id, params["before"]), &%{messages: &1})

  def invite(conn, %{"id" => id}), do: reply(conn, Chat.invite(conn.assigns.user, id))
  def accept(conn, params), do: reply(conn, Chat.accept(conn.assigns.user, params["token"]))

  def roles(conn, %{"id" => id}),
    do: reply(conn, Openchat.Permissions.settings(conn.assigns.user, id))

  def save_role(conn, %{"id" => id} = params),
    do:
      reply(
        conn,
        Openchat.Permissions.save_role(conn.assigns.user, id, params["role_id"], params)
      )

  def reorder_roles(conn, %{"id" => id} = params),
    do: reply(conn, Openchat.Permissions.reorder_roles(conn.assigns.user, id, params["role_ids"]))

  def delete_role(conn, %{"id" => id, "role_id" => role_id}),
    do: reply(conn, Openchat.Permissions.delete_role(conn.assigns.user, id, role_id))

  def everyone(conn, %{"id" => id} = params),
    do:
      reply(conn, Openchat.Permissions.set_everyone(conn.assigns.user, id, params["permissions"]))

  def set_member_role(conn, %{"id" => id, "user_id" => target, "role_id" => role_id} = params),
    do:
      reply(
        conn,
        Openchat.Permissions.set_member_role(
          conn.assigns.user,
          id,
          target,
          role_id,
          params["enabled"]
        )
      )

  def assign_roles(conn, %{"id" => id, "user_id" => target} = params),
    do:
      reply(
        conn,
        Openchat.Permissions.assign_roles(conn.assigns.user, id, target, params["role_ids"])
      )

  def room_permissions(conn, %{"id" => id}),
    do: reply(conn, Openchat.Permissions.room_settings(conn.assigns.user, id))

  def save_room_permissions(conn, %{"id" => id} = params),
    do:
      reply(conn, Openchat.Permissions.set_overrides(conn.assigns.user, id, params["overwrites"]))

  def create_thread(conn, %{"id" => id}),
    do: reply(conn, Chat.create_thread(conn.assigns.user, id))

  def threads(conn, %{"id" => id}),
    do: reply(conn, Chat.threads(conn.assigns.user, id), &%{threads: &1})

  def thread_messages(conn, %{"id" => id} = params),
    do: reply(conn, Chat.thread_history(conn.assigns.user, id, params["before"]))

  def archive_thread(conn, %{"id" => id} = params),
    do: reply(conn, Chat.archive_thread(conn.assigns.user, id, params["archived"]))

  def direct_identity(conn, params),
    do:
      reply(
        conn,
        Openchat.Direct.publish_identity(conn.assigns.user, params["public_key"]),
        fn _ -> %{ok: true} end
      )

  def direct_contacts(conn, _),
    do: json(conn, %{contacts: Openchat.Direct.contacts(conn.assigns.user)})

  def direct_list(conn, _),
    do: json(conn, %{conversations: Openchat.Direct.list(conn.assigns.user)})

  def direct_start(conn, params),
    do: reply(conn, Openchat.Direct.start(conn.assigns.user, params["user_id"]))

  def direct_history(conn, %{"id" => id} = params),
    do: reply(conn, Openchat.Direct.history(conn.assigns.user, id, params["before"]))

  def direct_send(conn, %{"id" => id} = params),
    do: reply(conn, Openchat.Direct.send_message(conn.assigns.user, id, params["encrypted"]))

  def profile(conn, params) do
    case Accounts.update_profile(conn.assigns.user, params) do
      {:ok, user} ->
        json(conn, Accounts.private(user))

      {:error, %Ecto.Changeset{} = changeset} ->
        if Keyword.has_key?(changeset.errors, :username),
          do: error(conn, 422, "Ce pseudo est déjà utilisé. Choisissez-en un autre."),
          else: error(conn, 422, "Profil invalide.")

      _ ->
        error(
          conn,
          422,
          "Vérifiez le profil : le pseudo doit contenir 3 à 24 lettres sans accent, chiffres ou underscores."
        )
    end
  end

  def username_available(conn, params),
    do:
      json(conn, %{available: Accounts.username_available?(conn.assigns.user, params["username"])})

  def credentials(conn, params) do
    case Accounts.update_credentials(conn.assigns.user, params) do
      {:ok, user} ->
        Accounts.revoke_all(user)
        establish(conn, user)

      _ ->
        error(
          conn,
          422,
          "Modification impossible. Vérifiez le mot de passe actuel, l’e-mail et rechargez en cas de modification depuis un autre appareil."
        )
    end
  end

  def friends(conn, _), do: json(conn, %{friends: Openchat.Friends.list(conn.assigns.user)})

  def friend_request(conn, params) do
    result =
      if Map.has_key?(params, "username"),
        do: Openchat.Friends.request_username(conn.assigns.user, params["username"]),
        else: Openchat.Friends.request(conn.assigns.user, params["user_id"])

    case result do
      {:ok, _} ->
        json(conn, %{ok: true})

      {:error, :unknown_username} ->
        error(conn, 422, "Aucune personne ne correspond à ce pseudo.")

      _ ->
        error(conn, 422, "Demande impossible : vérifiez le pseudo ou vos demandes déjà envoyées.")
    end
  end

  def friend_accept(conn, %{"id" => id}),
    do:
      reply(conn, Openchat.Friends.change(conn.assigns.user, id, :accept), fn _ -> %{ok: true} end)

  def friend_delete(conn, %{"id" => id}),
    do:
      reply(conn, Openchat.Friends.change(conn.assigns.user, id, :delete), fn _ -> %{ok: true} end)

  def edit_message(conn, %{"id" => id} = params), do: message_action(conn, id, :edit, params)
  def delete_message(conn, %{"id" => id} = params), do: message_action(conn, id, :delete, params)
  def react_message(conn, %{"id" => id} = params), do: message_action(conn, id, :react, params)
  defp message_action(conn, id, action, params) do
    kind = if conn.path_info |> Enum.take(2) == ["api", "direct"], do: :direct, else: :room
    reply(conn, Openchat.MessageActions.change(conn.assigns.user, kind, id, action, params))
  end

  def ice(conn, _) do
    urls = Application.get_env(:openchat, :turn_urls, [])
    secret = Application.get_env(:openchat, :turn_secret)

    servers =
      if urls != [] and is_binary(secret) do
        username = "#{System.system_time(:second) + 3600}:#{conn.assigns.user.id}"

        [
          %{
            urls: urls,
            username: username,
            credential: Base.encode64(:crypto.mac(:hmac, :sha, secret, username))
          }
        ]
      else
        []
      end

    json(conn, %{iceServers: servers, relayConfigured: servers != []})
  end

  defp establish(conn, user) do
    Accounts.revoke(get_session(conn, :token))
    Plug.CSRFProtection.delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> put_session(:token, Accounts.create_session(user))
    |> authenticated(user)
  end

  defp authenticated(conn, user) do
    {session, _} = Accounts.session(get_session(conn, :token))

    json(conn, %{
      user: Accounts.private(user),
      session_id: session.id,
      session_expires_at: session.expires_at,
      csrf_token: Plug.CSRFProtection.get_csrf_token(),
      socket_token: Phoenix.Token.sign(conn, "socket", get_session(conn, :token))
    })
  end

  defp authenticate(conn, _) do
    case Accounts.session(get_session(conn, :token)) do
      {_session, user} -> assign(conn, :user, user)
      nil -> conn |> error(401, "Connectez-vous pour continuer.") |> halt()
    end
  end

  defp rate_limit(conn, _) do
    auth? = action_name(conn) in [:login, :register]
    key = if auth?, do: {:auth, conn.remote_ip}, else: {:api, conn.remote_ip}

    if Openchat.Security.Limiter.allow?(key, if(auth?, do: 12, else: 300)) do
      conn
    else
      conn |> error(429, "Trop de requêtes. Réessayez dans une minute.") |> halt()
    end
  end

  defp reply(conn, result, fun \\ &Function.identity/1)
  defp reply(conn, {:ok, value}, fun), do: json(conn, fun.(value))

  defp reply(conn, {:error, _}, _),
    do: error(conn, 422, "Action refusée : droits insuffisants ou données invalides.")

  defp error(conn, status, message), do: conn |> put_status(status) |> json(%{error: message})
end
