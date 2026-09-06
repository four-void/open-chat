defmodule Openchat.Repo do
  use Ecto.Repo,
    otp_app: :openchat,
    adapter: Ecto.Adapters.Postgres
end
