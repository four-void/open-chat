defmodule Openchat.Chat.Server do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "servers" do
    field :owner_id, :binary_id
    field :data, Openchat.Security.Encrypted
    timestamps(type: :utc_datetime_usec)
  end
end
