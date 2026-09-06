defmodule OpenchatWeb.ApiControllerTest do
  use OpenchatWeb.ConnCase, async: true
  import Openchat.PlatformFixtures

  test "anonymous requests cannot read servers", %{conn: conn} do
    assert conn |> get("/api/servers") |> json_response(401)
  end

  test "registration establishes an encrypted HttpOnly session and logout revokes it", %{
    conn: conn
  } do
    conn = post(conn, "/api/register", params())
    assert %{"user" => %{"id" => _}, "socket_token" => _} = json_response(conn, 200)
    assert conn.resp_cookies["_openchat_key"].http_only
    session_conn = recycle(conn)
    assert session_conn |> get("/api/servers") |> json_response(200) == %{"servers" => []}
    assert session_conn |> delete("/api/session") |> json_response(200) == %{"ok" => true}
    assert session_conn |> get("/api/servers") |> json_response(401)
  end

  test "session metadata remains stable on refresh and rotates after login", %{conn: conn} do
    registration = params()
    signed = post(conn, "/api/register", registration)
    first = json_response(signed, 200)
    refreshed = signed |> recycle() |> get("/api/session") |> json_response(200)
    assert first["session_id"] == refreshed["session_id"]
    assert first["session_expires_at"] == refreshed["session_expires_at"]
    assert first["user"] == refreshed["user"]
    {:ok, expiry, _} = DateTime.from_iso8601(first["session_expires_at"])
    assert DateTime.compare(expiry, DateTime.utc_now()) == :gt
    logged = signed |> recycle() |> post("/api/login", registration)
    next = json_response(logged, 200)
    refute next["session_id"] == first["session_id"]
    logged |> recycle() |> delete("/api/session")
    assert %{"user" => nil} = logged |> recycle() |> get("/api/session") |> json_response(200)
  end

  test "CSRF remains valid after authentication rotates the session", %{conn: conn} do
    page = get(conn, "/")
    document = page |> html_response(200) |> LazyHTML.from_document()

    token =
      document |> LazyHTML.query("meta[name=csrf-token]") |> LazyHTML.attribute("content") |> hd()

    conn =
      page
      |> recycle()
      |> Plug.Conn.put_private(:plug_skip_csrf_protection, false)
      |> put_req_header("x-csrf-token", token)
      |> post("/api/register", params())

    response = json_response(conn, 200)

    conn =
      conn
      |> recycle()
      |> Plug.Conn.put_private(:plug_skip_csrf_protection, false)
      |> put_req_header("x-csrf-token", response["csrf_token"])
      |> post("/api/servers", %{"name" => "CSRF protected server"})

    assert %{"id" => _} = json_response(conn, 200)
  end

  test "mutation without CSRF token is rejected", %{conn: conn} do
    conn = Plug.Conn.put_private(conn, :plug_skip_csrf_protection, false)
    assert_error_sent 403, fn -> post(conn, "/api/register", params()) end
  end
end
