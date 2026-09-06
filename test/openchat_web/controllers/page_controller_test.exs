defmodule OpenchatWeb.PageControllerTest do
  use OpenchatWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    document = conn |> html_response(200) |> LazyHTML.from_document()
    assert document |> LazyHTML.query("#app") |> Enum.count() == 1
  end
end
