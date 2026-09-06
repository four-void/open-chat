defmodule Openchat.Repo.Migrations.AddUsernames do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :username, :string
    end

    create unique_index(:users, [:username])

    create constraint(:users, :username_format,
             check: "username IS NULL OR username ~ '^[a-z0-9_]{3,24}$'"
           )
  end
end
