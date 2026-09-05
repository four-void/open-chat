defmodule Openchat.Repo do
  use Ecto.Repo,
    otp_app: :openchat,
    adapter: Ecto.Adapters.SQLite3
end
