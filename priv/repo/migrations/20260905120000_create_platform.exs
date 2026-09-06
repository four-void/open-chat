defmodule Openchat.Repo.Migrations.CreatePlatform do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email_index, :binary, null: false
      add :password_hash, :binary, null: false
      add :data, :binary, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:email_index])

    create table(:sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :token_hash, :binary, null: false
      add :expires_at, :utc_datetime, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:sessions, [:token_hash])

    create table(:servers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :owner_id, references(:users, type: :binary_id), null: false
      add :data, :binary, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create table(:memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :server_id, references(:servers, type: :binary_id, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:memberships, [:server_id, :user_id])
    create index(:memberships, [:user_id])

    create table(:rooms, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :server_id, references(:servers, type: :binary_id, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :data, :binary, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:rooms, [:server_id])
    create constraint(:rooms, :valid_kind, check: "kind IN ('text', 'voice')")

    create table(:messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :room_id, references(:rooms, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id), null: false
      add :data, :binary, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:messages, [:room_id, :inserted_at, :id])

    create table(:invites, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :server_id, references(:servers, type: :binary_id, on_delete: :delete_all), null: false
      add :token_hash, :binary, null: false
      add :expires_at, :utc_datetime, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:invites, [:token_hash])
  end
end
