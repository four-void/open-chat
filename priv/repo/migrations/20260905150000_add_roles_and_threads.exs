defmodule Openchat.Repo.Migrations.AddRolesAndThreads do
  use Ecto.Migration

  def change do
    alter table(:memberships) do
      add :data, :binary
    end

    create table(:roles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :server_id, references(:servers, type: :binary_id, on_delete: :delete_all), null: false
      add :data, :binary, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:roles, [:server_id])

    create table(:threads, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :room_id, references(:rooms, type: :binary_id, on_delete: :delete_all), null: false

      add :root_message_id, references(:messages, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id), null: false
      add :archived_at, :utc_datetime
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:threads, [:root_message_id])
    create index(:threads, [:room_id])

    alter table(:messages) do
      add :thread_id, references(:threads, type: :binary_id, on_delete: :delete_all)
    end

    create index(:messages, [:thread_id, :inserted_at, :id])
  end
end
