defmodule TriviaPlatform.Repo.Migrations.CreateQuestions do
  use Ecto.Migration

  def change do
    create table(:questions) do
      add :category, :string, null: false
      add :question_text, :text, null: false
      add :option_a, :string, null: false
      add :option_b, :string, null: false
      add :option_c, :string, null: false
      add :option_d, :string, null: false
      add :correct_answer, :string, null: false
      add :difficulty, :string, null: false, default: "medium"

      timestamps()
    end

    create index(:questions, [:category])
    create index(:questions, [:difficulty])
  end
end
