defmodule TriviaPlatform.Games.Game do
  use Ecto.Schema
  import Ecto.Changeset

  schema "games" do
    field :room_code, :string
    field :host_name, :string
    field :category, :string
    field :question_count, :integer
    field :player_count, :integer
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime

    has_many :results, TriviaPlatform.Games.GameResult

    timestamps()
  end

  def changeset(game, attrs) do
    game
    |> cast(
      attrs,
      ~w(room_code host_name category question_count player_count started_at ended_at)a
    )
    |> validate_required(
      ~w(room_code host_name category question_count player_count started_at ended_at)a
    )
  end
end
