defmodule Openchat.UsernamesTest do
  use Openchat.DataCase, async: true
  import Openchat.PlatformFixtures
  alias Openchat.{Accounts, Friends, Repo}

  test "usernames are normalized, unique and preserve the account identity" do
    a = user()
    b = user()
    assert {:ok, updated} = Accounts.update_profile(a, %{"username" => " @Camille_42 "})
    assert updated.username == "camille_42"
    assert updated.id == a.id
    assert updated.data == a.data
    assert Accounts.public(updated).username == "camille_42"
    refute Accounts.username_available?(b, "CAMILLE_42")
    assert Accounts.username_available?(a, "camille_42")
    assert {:error, changeset} = Accounts.update_profile(b, %{"username" => "Camille_42"})
    assert Keyword.has_key?(changeset.errors, :username)
    assert Repo.get!(Openchat.Chat.User, b.id).username == nil
    assert {:ok, renamed} = Accounts.update_profile(updated, %{"username" => "camille_new"})
    assert renamed.id == a.id
    assert Accounts.username_available?(b, "camille_42")
    assert {:ok, saved} = Accounts.update_profile(a, %{"bio" => "Hello"})
    assert saved.username == "camille_new"
  end

  test "invalid usernames are rejected without changing the profile" do
    a = user()

    for username <- [
          nil,
          "",
          "ab",
          "has space",
          "été",
          "test.name",
          "@@camille",
          String.duplicate("a", 25)
        ] do
      assert {:error, _} =
               Accounts.update_profile(a, %{"username" => username, "name" => "Changed"})

      refute Accounts.username_available?(a, username)
    end

    assert Repo.get!(Openchat.Chat.User, a.id).data == a.data
  end

  test "friends can be added by username and remain linked after renaming" do
    a = user()
    b = user()
    {:ok, b} = Accounts.update_profile(b, %{"username" => "my_friend"})
    assert {:ok, f} = Friends.request_username(a, " @MY_FRIEND ")
    assert {:error, _} = Friends.request_username(b, "my_friend")
    assert {:error, :unknown_username} = Friends.request_username(a, "nobody_here")
    assert {:ok, _} = Friends.change(b, f.id, :accept)
    {:ok, _} = Accounts.update_profile(b, %{"username" => "new_friend"})
    assert [%{peer: %{username: "new_friend"}, status: "accepted"}] = Friends.list(a)
    assert Friends.accepted?(a.id, b.id)
  end
end
