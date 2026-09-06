defmodule Openchat.Repo.Migrations.AddDirectMessages do
  use Ecto.Migration

  def change do
    create table(:direct_conversations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :first_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :second_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:direct_conversations, [:first_id, :second_id])
    create index(:direct_conversations, [:second_id])
    create constraint(:direct_conversations, :ordered_participants, check: "first_id < second_id")

    create table(:direct_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :conversation_id,
          references(:direct_conversations, type: :binary_id, on_delete: :delete_all), null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :data, :binary, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:direct_messages, [:conversation_id, :inserted_at, :id])
  end
end
