defmodule Openchat.Repo.Migrations.CreateFriendships do
  use Ecto.Migration

  def change do
    create table(:friendships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :first_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :second_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :requester_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :accepted, :boolean, null: false, default: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:friendships, [:first_id, :second_id])
    create constraint(:friendships, :ordered_pair, check: "first_id < second_id")
  end
end
