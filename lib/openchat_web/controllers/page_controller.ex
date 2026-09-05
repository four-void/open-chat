defmodule OpenchatWeb.PageController do
  use OpenchatWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
