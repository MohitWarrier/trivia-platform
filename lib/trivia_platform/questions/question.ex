defmodule TriviaPlatform.Questions.Question do
  use Ecto.Schema
  import Ecto.Changeset

  schema "questions" do
    field :category, :string
    field :question_text, :string
    field :option_a, :string
    field :option_b, :string
    field :option_c, :string
    field :option_d, :string
    field :correct_answer, :string
    field :difficulty, :string, default: "medium"

    timestamps()
  end

  @required_fields ~w(category question_text option_a option_b option_c option_d correct_answer)a
  @optional_fields ~w(difficulty)a

  def changeset(question, attrs) do
    question
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:correct_answer, ~w(a b c d))
    |> validate_inclusion(:difficulty, ~w(easy medium hard))
    |> validate_inclusion(:category, categories())
  end

  def categories do
    ~w(science history geography entertainment sports)
  end
end
