defmodule Openchat.Chat.Role do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "roles" do
    field :server_id, :binary_id
    field :position, :integer, default: 1
    field :data, Openchat.Security.Encrypted
    timestamps(type: :utc_datetime_usec)
  end
end
