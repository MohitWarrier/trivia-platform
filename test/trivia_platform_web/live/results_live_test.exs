defmodule TriviaPlatformWeb.ResultsLiveTest do
  use TriviaPlatformWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias TriviaPlatform.Games

  setup do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, game} =
      Games.save_game(%{
        room_code: "TSTRES",
        host_name: "TestHost",
        category: "science",
        question_count: 5,
        player_count: 2,
        started_at: now |> DateTime.add(-60),
        ended_at: now
      })

    Games.save_game_results(game, [
      %{player_name: "Alice", final_score: 1500, correct_answers: 5, rank: 1},
      %{player_name: "Bob", final_score: 800, correct_answers: 3, rank: 2}
    ])

    %{game: game}
  end

  describe "mounting" do
    test "renders game results", %{conn: conn, game: game} do
      {:ok, _view, html} = live(conn, ~p"/results/#{game.id}")

      assert html =~ "Game Results"
      assert html =~ "Alice"
      assert html =~ "Bob"
      assert html =~ "1500"
      assert html =~ "800"
      assert html =~ "Science"
      assert html =~ "TSTRES"
    end

    test "shows winner highlight", %{conn: conn, game: game} do
      {:ok, _view, html} = live(conn, ~p"/results/#{game.id}")
      assert html =~ "Winner"
      assert html =~ "Alice"
    end

    test "redirects to home for non-existent game", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/results/999999")
    end
  end
end
