defmodule Openchat.Chat.Friendship do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "friendships" do
    field :first_id, :binary_id
    field :second_id, :binary_id
    field :requester_id, :binary_id
    field :accepted, :boolean, default: false
    timestamps(type: :utc_datetime_usec)
  end
end
