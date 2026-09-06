defmodule Openchat.Repo.Migrations.AddRolePositions do
  use Ecto.Migration

  def up do
    alter table(:roles) do
      add :position, :integer, null: false, default: 1
    end

    execute "UPDATE roles SET position = ranked.position FROM (SELECT id, row_number() OVER (PARTITION BY server_id ORDER BY inserted_at, id)::integer AS position FROM roles) ranked WHERE roles.id = ranked.id"

    create constraint(:roles, :positive_position, check: "position > 0")
  end

  def down do
    drop constraint(:roles, :positive_position)

    alter table(:roles) do
      remove :position
    end
  end
end
