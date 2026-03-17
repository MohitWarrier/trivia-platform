defmodule TriviaPlatform.Repo.Migrations.CreateGameResults do
  use Ecto.Migration

  def change do
    create table(:game_results) do
      add :player_name, :string, null: false
      add :final_score, :integer, null: false, default: 0
      add :correct_answers, :integer, null: false, default: 0
      add :rank, :integer, null: false
      add :game_id, references(:games, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:game_results, [:game_id])
  end
end
