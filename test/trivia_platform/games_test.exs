defmodule TriviaPlatform.GamesTest do
  use TriviaPlatform.DataCase, async: true

  alias TriviaPlatform.Games
  alias TriviaPlatform.Games

  defp create_game_attrs(overrides \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Map.merge(
      %{
        room_code: "TEST#{:rand.uniform(9999)}",
        host_name: "TestHost",
        category: "science",
        question_count: 5,
        player_count: 2,
        started_at: now |> DateTime.add(-60),
        ended_at: now
      },
      overrides
    )
  end

  describe "save_game/1" do
    test "saves a game with valid attributes" do
      attrs = create_game_attrs()
      assert {:ok, game} = Games.save_game(attrs)
      assert game.room_code == attrs.room_code
      assert game.host_name == "TestHost"
      assert game.category == "science"
      assert game.question_count == 5
      assert game.player_count == 2
    end

    test "fails with missing required fields" do
      assert {:error, changeset} = Games.save_game(%{})
      refute changeset.valid?
    end
  end

  describe "save_game_results/2" do
    test "saves results for a game" do
      {:ok, game} = Games.save_game(create_game_attrs())

      results = [
        %{player_name: "Alice", final_score: 1500, correct_answers: 5, rank: 1},
        %{player_name: "Bob", final_score: 800, correct_answers: 3, rank: 2}
      ]

      assert {2, _} = Games.save_game_results(game, results)
    end
  end

  describe "get_game_with_results/1" do
    test "returns game with preloaded results ordered by rank" do
      {:ok, game} = Games.save_game(create_game_attrs())

      results = [
        %{player_name: "Bob", final_score: 800, correct_answers: 3, rank: 2},
        %{player_name: "Alice", final_score: 1500, correct_answers: 5, rank: 1}
      ]

      Games.save_game_results(game, results)

      loaded_game = Games.get_game_with_results(game.id)
      assert loaded_game.id == game.id
      assert length(loaded_game.results) == 2
      assert hd(loaded_game.results).player_name == "Alice"
      assert hd(loaded_game.results).rank == 1
    end

    test "returns nil for non-existent game" do
      assert nil == Games.get_game_with_results(999_999)
    end
  end

  describe "list_recent_games/1" do
    test "returns games ordered by ended_at descending" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, _g1} =
        Games.save_game(
          create_game_attrs(%{
            room_code: "OLDER1",
            started_at: now |> DateTime.add(-120),
            ended_at: now |> DateTime.add(-60)
          })
        )

      {:ok, _g2} =
        Games.save_game(
          create_game_attrs(%{
            room_code: "NEWER1",
            started_at: now |> DateTime.add(-30),
            ended_at: now
          })
        )

      games = Games.list_recent_games(10)
      assert length(games) >= 2
      assert hd(games).room_code == "NEWER1"
    end

    test "respects the limit" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      for i <- 1..5 do
        Games.save_game(
          create_game_attrs(%{
            room_code: "LIM#{i}XX",
            started_at: now |> DateTime.add(-i * 60),
            ended_at: now |> DateTime.add(-i * 30)
          })
        )
      end

      games = Games.list_recent_games(3)
      assert length(games) == 3
    end
  end
end
