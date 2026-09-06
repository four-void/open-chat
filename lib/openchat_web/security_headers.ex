defmodule OpenchatWeb.SecurityHeaders do
  import Plug.Conn
  def init(opts), do: opts

  def call(conn, _) do
    conn
    |> put_resp_header(
      "content-security-policy",
      "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; media-src 'self' blob:; connect-src 'self' ws://localhost:4000 ws://127.0.0.1:4000; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; form-action 'self'"
    )
    |> put_resp_header("referrer-policy", "no-referrer")
    |> put_resp_header(
      "permissions-policy",
      "camera=(), microphone=(self), display-capture=(self)"
    )
    |> put_resp_header("cache-control", "no-store")
  end
end
