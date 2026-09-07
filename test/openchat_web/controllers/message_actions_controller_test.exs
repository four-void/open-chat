defmodule OpenchatWeb.MessageActionsControllerTest do
  use OpenchatWeb.ConnCase, async: true
  import Openchat.PlatformFixtures
  alias Openchat.{Repo, Chat, Direct}

  test "room and private mutation routes select the correct message storage", %{conn: conn} do
    conn = post(conn, "/api/register", params())
    id = json_response(conn, 200)["user"]["id"]
    alice = Repo.get!(Openchat.Chat.User, id)
    bob = user()
    {:ok, server} = Chat.create_server(alice, "Messages API")
    {:ok, %{token: token}} = Chat.invite(alice, server.id)
    {:ok, _} = Chat.accept(bob, token)
    {:ok, [room | _]} = Chat.rooms(alice, server.id)

    for person <- [alice, bob] do
      {public, _} = :crypto.generate_key(:ecdh, :secp256r1)
      {:ok, _} = Direct.publish_identity(person, Base.encode64(public))
    end

    {:ok, dm} = Direct.start(alice, bob.id)
    {:ok, a} = Chat.send_message(alice, room.id, message())
    {:ok, b} = Direct.send_message(alice, dm.id, message())

    for path <- ["/api/messages/#{a.id}", "/api/direct/messages/#{b.id}"] do
      encrypted = message()

      assert %{"encrypted" => ^encrypted, "edited_at" => edited} =
               conn |> recycle() |> patch(path, %{encrypted: encrypted}) |> json_response(200)

      assert edited

      assert %{"reactions" => %{"👍" => [^id]}} =
               conn
               |> recycle()
               |> put(path <> "/reaction", %{emoji: "👍", enabled: true})
               |> json_response(200)

      assert %{"encrypted" => nil, "deleted_at" => deleted} =
               conn |> recycle() |> delete(path) |> json_response(200)

      assert deleted
    end
  end
end
