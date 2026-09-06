defmodule Openchat.Chat.Room do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "rooms" do
    field :server_id, :binary_id
    field :kind, :string
    field :data, Openchat.Security.Encrypted
    timestamps(type: :utc_datetime_usec)
  end
end
