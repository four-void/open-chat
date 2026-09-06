defmodule Openchat.Chat.Thread do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "threads" do
    field :room_id, :binary_id
    field :root_message_id, :binary_id
    field :user_id, :binary_id
    field :archived_at, :utc_datetime
    timestamps(type: :utc_datetime_usec)
  end
end
