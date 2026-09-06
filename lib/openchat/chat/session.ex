defmodule Openchat.Chat.Session do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "sessions" do
    field :user_id, :binary_id
    field :token_hash, :binary
    field :expires_at, :utc_datetime
    timestamps(type: :utc_datetime_usec)
  end
end
