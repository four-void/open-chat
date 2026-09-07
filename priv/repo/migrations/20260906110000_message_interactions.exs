defmodule Openchat.Repo.Migrations.MessageInteractions do
  use Ecto.Migration

  def change do
    for table <- [:messages, :direct_messages] do
      alter table(table) do
        add :activity, :binary
        add :edited_at, :utc_datetime_usec
        add :deleted_at, :utc_datetime_usec
      end
    end
  end
end
