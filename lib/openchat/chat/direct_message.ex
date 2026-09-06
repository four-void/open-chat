defmodule Openchat.Chat.DirectMessage do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "direct_messages" do
    field :conversation_id, :binary_id
    field :user_id, :binary_id
    field :data, Openchat.Security.Encrypted
    field :activity, Openchat.Security.Encrypted
    field :edited_at, :utc_datetime_usec
    field :deleted_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end
end
