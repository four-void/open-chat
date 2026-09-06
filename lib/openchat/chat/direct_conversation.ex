defmodule Openchat.Chat.DirectConversation do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "direct_conversations" do
    field :first_id, :binary_id
    field :second_id, :binary_id
    timestamps(type: :utc_datetime_usec)
  end
end
