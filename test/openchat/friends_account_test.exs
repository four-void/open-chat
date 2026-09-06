defmodule Openchat.FriendsAccountTest do
  use Openchat.DataCase, async: true
  import Openchat.PlatformFixtures
  alias Openchat.{Accounts, Friends, Direct, Repo}

  test "only the recipient can accept, and only participants can remove a friendship" do
    a = user()
    b = user()
    outsider = user()
    assert {:error, _} = Friends.request(a, a.id)
    assert {:error, _} = Friends.request(a, "invalid")
    assert {:ok, f} = Friends.request(a, b.id)
    assert {:error, _} = Friends.request(b, a.id)
    assert [%{status: "outgoing"}] = Friends.list(a)
    assert [%{status: "incoming"}] = Friends.list(b)
    assert Friends.list(outsider) == []
    assert {:error, _} = Friends.change(a, f.id, :accept)
    assert {:error, _} = Friends.change(outsider, f.id, :accept)
    assert {:error, _} = Friends.change(outsider, f.id, :delete)
    refute Friends.accepted?(a.id, b.id)
    assert {:ok, _} = Friends.change(b, f.id, :accept)
    assert Friends.accepted?(a.id, b.id)

    for person <- [a, b] do
      {public, _} = :crypto.generate_key(:ecdh, :secp256r1)
      assert {:ok, _} = Direct.publish_identity(person, Base.encode64(public))
    end

    assert {:ok, _} = Direct.start(a, b.id)
    assert [%{id: id}] = Direct.contacts(a)
    assert id == b.id
    assert {:ok, _} = Friends.change(a, f.id, :delete)
    refute Friends.accepted?(a.id, b.id)
  end

  test "profile edits preserve private data and reject invalid fields" do
    a = user()

    assert {:ok, updated} =
             Accounts.update_profile(a, %{
               "name" => " Alex ",
               "bio" => "Bonjour",
               "color" => "#123456",
               "email" => "attacker@example.com",
               "vault" => %{}
             })

    assert updated.data["name"] == "Alex"
    assert updated.data["email"] == a.data["email"]
    assert updated.data["vault"] == a.data["vault"]
    refute Map.has_key?(Accounts.public(updated), "email")

    for fields <- [
          %{"name" => " "},
          %{"bio" => String.duplicate("a", 501)},
          %{"avatar" => "javascript:alert(1)"},
          %{"color" => "red"}
        ] do
      assert {:error, _} = Accounts.update_profile(a, fields)
    end
  end

  test "credential changes authenticate and atomically replace the vault with stale protection" do
    a = user()

    params = %{
      "current_password" => "a long test password",
      "email" => "new@example.fr",
      "password" => "a different long password",
      "salt" => Base.encode64(:crypto.strong_rand_bytes(16)),
      "vault" => vault(),
      "previous" => a.data["vault"]
    }

    assert {:error, _} =
             Accounts.update_credentials(a, Map.put(params, "current_password", "wrong"))

    assert {:error, _} = Accounts.update_credentials(a, Map.put(params, "previous", vault()))
    assert Repo.get!(Openchat.Chat.User, a.id).data == a.data
    assert {:ok, updated} = Accounts.update_credentials(a, params)
    assert updated.data["vault"] == params["vault"]
    assert {:ok, _} = Accounts.authenticate("new@example.fr", params["password"])
    assert {:error, _} = Accounts.authenticate(a.data["email"], params["current_password"])
    token = Accounts.create_session(updated)
    assert Accounts.session(token)
    Accounts.revoke_all(updated)
    refute Accounts.session(token)
  end
end
