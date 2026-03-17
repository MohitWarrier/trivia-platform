defmodule TriviaPlatform.Repo.Migrations.CreateGames do
  use Ecto.Migration

  def change do
    create table(:games) do
      add :room_code, :string, null: false
      add :host_name, :string, null: false
      add :category, :string, null: false
      add :question_count, :integer, null: false
      add :player_count, :integer, null: false
      add :started_at, :utc_datetime, null: false
      add :ended_at, :utc_datetime, null: false

      timestamps()
    end
  end
end
