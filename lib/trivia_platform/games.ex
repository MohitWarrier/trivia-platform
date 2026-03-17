defmodule TriviaPlatform.Games do
  import Ecto.Query
  alias TriviaPlatform.Repo
  alias TriviaPlatform.Games.{Game, GameResult}

  def save_game(attrs) do
    %Game{}
    |> Game.changeset(attrs)
    |> Repo.insert()
  end

  def save_game_results(game, results_list) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    entries =
      Enum.map(results_list, fn result ->
        result
        |> Map.put(:game_id, game.id)
        |> Map.put(:inserted_at, now)
        |> Map.put(:updated_at, now)
      end)

    Repo.insert_all(GameResult, entries)
  end

  def get_game_with_results(game_id) do
    Game
    |> Repo.get(game_id)
    |> Repo.preload(results: from(r in GameResult, order_by: r.rank))
  end

  def list_recent_games(limit \\ 10) do
    Game
    |> order_by(desc: :ended_at)
    |> limit(^limit)
    |> Repo.all()
  end
end
