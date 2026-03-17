defmodule TriviaPlatform.Games.GameResult do
  use Ecto.Schema
  import Ecto.Changeset

  schema "game_results" do
    field :player_name, :string
    field :final_score, :integer, default: 0
    field :correct_answers, :integer, default: 0
    field :rank, :integer

    belongs_to :game, TriviaPlatform.Games.Game

    timestamps()
  end

  def changeset(result, attrs) do
    result
    |> cast(attrs, ~w(player_name final_score correct_answers rank game_id)a)
    |> validate_required(~w(player_name final_score correct_answers rank game_id)a)
    |> foreign_key_constraint(:game_id)
  end
end
