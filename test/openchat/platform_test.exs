defmodule Openchat.PlatformTest do
  use Openchat.DataCase, async: true
  import Openchat.PlatformFixtures
  alias Openchat.{Accounts, Chat, Repo}

  test "private account fields are encrypted in SQL and passwords never stored verbatim" do
    params = params()
    {:ok, user} = Accounts.register(params)

    [[data, password_hash, email_index]] =
      Repo.query!("SELECT data, password_hash, email_index FROM users WHERE id = $1", [
        Ecto.UUID.dump!(user.id)
      ]).rows

    refute :binary.match(data, params["email"]) != :nomatch
    refute :binary.match(data, params["name"]) != :nomatch
    refute password_hash == params["password"]
    refute email_index == params["email"]
    assert {:ok, _} = Accounts.authenticate(String.upcase(params["email"]), params["password"])
    assert {:error, _} = Accounts.authenticate(params["email"], "wrong password")
    assert {:error, _} = Accounts.register(params)
    assert {:error, _} = Accounts.register(%{})

    assert {:error, _} =
             Accounts.register(Map.put(params(), "vault", %{"iv" => nil, "cipher" => "AAAA"}))
  end

  test "sessions expire and can be revoked" do
    user = user()
    token = Accounts.create_session(user)
    assert {session, ^user} = Accounts.session(token)

    Repo.update!(
      Ecto.Changeset.change(session, expires_at: DateTime.add(DateTime.utc_now(:second), -1))
    )

    assert Accounts.session(token) == nil
    token = Accounts.create_session(user)
    Accounts.revoke(token)
    assert Accounts.session(token) == nil
  end

  test "membership protects rooms, history and messages; invitations grant access" do
    owner = user()
    outsider = user()
    {:ok, server} = Chat.create_server(owner, "Un serveur privé")
    {:ok, [text, voice]} = Chat.rooms(owner, server.id)
    assert {:error, _} = Chat.rooms(outsider, server.id)
    assert {:error, _} = Chat.history(outsider, text.id)
    assert {:error, _} = Chat.send_message(outsider, text.id, message())
    assert {:error, _} = Chat.create_room(outsider, server.id, "intrusion", "text")
    assert {:error, _} = Chat.invite(outsider, server.id)
    assert {:error, _} = Chat.rooms(owner, "not-a-uuid")
    {:ok, %{token: token}} = Chat.invite(owner, server.id)
    assert {:ok, _} = Chat.accept(outsider, token)
    assert {:ok, _} = Chat.accept(outsider, token)
    assert {:error, _} = Chat.create_room(outsider, server.id, "intrusion", "text")
    assert {:error, _} = Chat.send_message(owner, voice.id, message())
    assert {:error, _} = Chat.send_message(owner, text.id, %{"text" => "plaintext"})
    payload = message()
    assert {:ok, sent} = Chat.send_message(outsider, text.id, payload)
    assert {:ok, [^sent]} = Chat.history(owner, text.id)

    [[stored]] =
      Repo.query!("SELECT data FROM messages WHERE id = $1", [Ecto.UUID.dump!(sent.id)]).rows

    refute :binary.match(stored, payload["cipher"]) != :nomatch
    assert {:ok, []} = Chat.history(owner, text.id, sent.id)
  end

  test "expired invitations cannot be used" do
    owner = user()
    {:ok, server} = Chat.create_server(owner, "Test server")
    {:ok, %{token: token}} = Chat.invite(owner, server.id)

    Repo.update_all(Openchat.Chat.Invite,
      set: [expires_at: DateTime.add(DateTime.utc_now(:second), -1)]
    )

    assert {:error, _} = Chat.accept(user(), token)
  end

  test "concurrent vault updates cannot overwrite keys silently" do
    user = user()
    next = vault()
    assert {:ok, _} = Accounts.update_vault(user, next, user.data["vault"])
    assert {:error, :stale_vault} = Accounts.update_vault(user, vault(), user.data["vault"])
    assert Repo.get!(Openchat.Chat.User, user.id).data["vault"] == next
  end
end
