defmodule OpenchatWeb.ProfileTest do
  use OpenchatWeb.ConnCase, async: true
  import Openchat.PlatformFixtures

  test "profile page is directly accessible and APIs require authentication", %{conn: conn} do
    assert conn |> get("/profile") |> html_response(200)
    assert conn |> get("/api/profile/username?username=test_user") |> json_response(401)
    assert conn |> put("/api/profile", %{"username" => "test_user"}) |> json_response(401)
  end

  test "profile API reports duplicate usernames clearly", %{conn: conn} do
    {:ok, _} = Openchat.Accounts.update_profile(user(), %{"username" => "reserved_name"})
    signed = post(conn, "/api/register", params())
    session = recycle(signed)

    assert %{"available" => false} =
             session |> get("/api/profile/username?username=RESERVED_NAME") |> json_response(200)

    assert %{"error" => "Ce pseudo est déjà utilisé. Choisissez-en un autre."} =
             session
             |> put("/api/profile", %{"username" => "reserved_name"})
             |> json_response(422)

    assert %{"username" => "my_new_name"} =
             session |> put("/api/profile", %{"username" => "My_New_Name"}) |> json_response(200)
  end
end
