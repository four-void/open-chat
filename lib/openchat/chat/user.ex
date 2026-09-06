defmodule Openchat.Chat.User do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "users" do
    field :username, :string
    field :email_index, :binary
    field :password_hash, :binary
    field :data, Openchat.Security.Encrypted
    timestamps(type: :utc_datetime_usec)
  end
end
