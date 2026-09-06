defmodule Openchat.Chat.Membership do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "memberships" do
    field :user_id, :binary_id
    field :server_id, :binary_id
    field :data, Openchat.Security.Encrypted
    timestamps(type: :utc_datetime_usec)
  end
end
