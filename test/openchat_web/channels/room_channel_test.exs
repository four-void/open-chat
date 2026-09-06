defmodule OpenchatWeb.RoomChannelTest do
  use Openchat.DataCase, async: false
  import Phoenix.ChannelTest
  import Openchat.PlatformFixtures
  @endpoint OpenchatWeb.Endpoint
  setup do
    owner = user()
    token = Openchat.Accounts.create_session(owner)
    socket_token = Phoenix.Token.sign(@endpoint, "socket", token)
    {:ok, socket} = connect(OpenchatWeb.UserSocket, %{"token" => socket_token})
    {:ok, server} = Openchat.Chat.create_server(owner, "Channel tests")
    {:ok, [room, _]} = Openchat.Chat.rooms(owner, server.id)
    %{owner: owner, token: token, socket: socket, room: room}
  end

  test "socket rejects forged authentication" do
    assert :error = connect(OpenchatWeb.UserSocket, %{"token" => "forged"})
  end

  test "authorized socket broadcasts ciphertext and rejects plaintext", %{
    socket: socket,
    room: room
  } do
    {:ok, _, joined} = subscribe_and_join(socket, OpenchatWeb.RoomChannel, "room:" <> room.id)
    payload = message()
    ref = push(joined, "message", payload)
    assert_reply ref, :ok, %{encrypted: ^payload}
    assert_broadcast "message", %{encrypted: ^payload}
    ref = push(joined, "message", %{"text" => "plaintext"})
    assert_reply ref, :error
  end

  test "nonmembers cannot subscribe to rooms", %{room: room} do
    stranger = user()
    token = Openchat.Accounts.create_session(stranger)

    {:ok, socket} =
      connect(OpenchatWeb.UserSocket, %{"token" => Phoenix.Token.sign(@endpoint, "socket", token)})

    assert {:error, %{reason: "forbidden"}} =
             subscribe_and_join(socket, OpenchatWeb.RoomChannel, "room:" <> room.id)
  end

  test "revoked sessions cannot keep sending", %{socket: socket, room: room, token: token} do
    {:ok, _, joined} = subscribe_and_join(socket, OpenchatWeb.RoomChannel, "room:" <> room.id)
    Openchat.Accounts.revoke(token)
    ref = push(joined, "message", message())
    assert_reply ref, :error
  end

  defp member_socket(owner, server_id) do
    member = user()
    {:ok, %{token: invite}} = Openchat.Chat.invite(owner, server_id)
    {:ok, _} = Openchat.Chat.accept(member, invite)
    token = Openchat.Accounts.create_session(member)

    {:ok, socket} =
      connect(OpenchatWeb.UserSocket, %{"token" => Phoenix.Token.sign(@endpoint, "socket", token)})

    {member, socket}
  end

  test "removing view access closes an already subscribed socket", %{owner: owner, room: room} do
    {_, socket} = member_socket(owner, room.server_id)
    {:ok, _, joined} = subscribe_and_join(socket, OpenchatWeb.RoomChannel, "room:" <> room.id)
    monitor = Process.monitor(joined.channel_pid)

    {:ok, _} =
      Openchat.Permissions.set_overrides(owner, room.id, %{
        "everyone" => %{"allow" => [], "deny" => ["view"]}
      })

    assert_push "access_changed", _
    assert_receive {:DOWN, ^monitor, :process, _, :normal}

    assert {:error, %{reason: "forbidden"}} =
             subscribe_and_join(socket, OpenchatWeb.RoomChannel, "room:" <> room.id)
  end

  test "read only permissions reject both main messages and thread replies", %{
    owner: owner,
    room: room
  } do
    {_, socket} = member_socket(owner, room.server_id)
    {:ok, root} = Openchat.Chat.send_message(owner, room.id, message())
    {:ok, thread} = Openchat.Chat.create_thread(owner, root.id)

    {:ok, _} =
      Openchat.Permissions.set_overrides(owner, room.id, %{
        "everyone" => %{"allow" => [], "deny" => ["send"]}
      })

    {:ok, _, joined} = subscribe_and_join(socket, OpenchatWeb.RoomChannel, "room:" <> room.id)
    ref = push(joined, "message", message())
    assert_reply ref, :error
    ref = push(joined, "thread_reply", %{"thread_id" => thread.id, "encrypted" => message()})
    assert_reply ref, :error
  end

  test "listeners can receive voice but cannot negotiate sending audio or screen", %{
    owner: owner,
    room: room
  } do
    {_, socket} = member_socket(owner, room.server_id)
    {:ok, rooms} = Openchat.Chat.rooms(owner, room.server_id)
    voice = Enum.find(rooms, &(&1.kind == "voice"))

    {:ok, _} =
      Openchat.Permissions.set_overrides(owner, voice.id, %{
        "everyone" => %{"allow" => [], "deny" => ["speak", "share"]}
      })

    {:ok, %{peer_id: peer_id}, joined} =
      subscribe_and_join(socket, OpenchatWeb.RoomChannel, "room:" <> voice.id)

    assert_push "presence_state", _

    ref =
      push(joined, "signal", %{
        "to" => peer_id,
        "data" => %{
          "description" => %{
            "type" => "offer",
            "sdp" => "v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\na=recvonly\r\n"
          }
        }
      })

    assert_reply ref, :ok

    for kind <- ["audio", "video"] do
      ref =
        push(joined, "signal", %{
          "to" => peer_id,
          "data" => %{
            "description" => %{
              "type" => "offer",
              "sdp" => "v=0\r\nm=#{kind} 9 UDP/TLS/RTP/SAVPF 111\r\na=sendrecv\r\n"
            }
          }
        })

      assert_reply ref, :error
    end

    ref = push(joined, "signal", %{"to" => peer_id, "data" => %{"sharing" => true}})
    assert_reply ref, :error
  end
end
