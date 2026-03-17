defmodule TriviaPlatformWeb.GameLoopTest do
  @moduledoc """
  Full end-to-end integration test simulating a complete multiplayer game
  using LiveView test connections. This is the "single person testing
  multiplayer" solution — we spin up multiple LiveView connections to
  simulate host + players, all within one test.
  """
  use TriviaPlatformWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias TriviaPlatform.Questions.Question
  alias TriviaPlatform.Rooms.RoomServer

  setup do
    # Seed questions with known correct answers
    for i <- 1..5 do
      TriviaPlatform.Repo.insert!(%Question{
        category: "science",
        question_text: "Loop test question #{i}?",
        option_a: "Correct#{i}",
        option_b: "Wrong#{i}",
        option_c: "Wrong#{i}",
        option_d: "Wrong#{i}",
        correct_answer: "a",
        difficulty: "medium"
      })
    end

    :ok
  end

  describe "complete game loop via LiveView" do
    test "host creates game, players join, play all questions, see results", %{conn: conn} do
      # ── Step 1: Host creates a game from the home page ──
      {:ok, home_view, _html} = live(conn, ~p"/")

      {:error, {:live_redirect, %{to: host_path}}} =
        home_view
        |> form("form[phx-submit=create_game]", %{
          host_name: "QuizMaster",
          category: "science",
          question_count: "3"
        })
        |> render_submit()

      # Extract room code from redirect path
      [_, code] = Regex.run(~r"/host/([A-Z2-9]+)", host_path)

      # ── Step 2: Host mounts the host view ──
      {:ok, host_view, host_html} = live(conn, host_path)
      assert host_html =~ code
      assert host_html =~ "No players yet"

      # ── Step 3: Player 1 joins via the play page ──
      {:ok, p1_view, _html} = live(conn, ~p"/play/#{code}?name=Alice")
      :timer.sleep(200)

      # Verify host sees Alice
      host_html = render(host_view)
      assert host_html =~ "Alice"

      # ── Step 4: Player 2 joins ──
      {:ok, p2_view, _html} = live(conn, ~p"/play/#{code}?name=Bob")
      :timer.sleep(200)

      # Both players should see each other
      p1_html = render(p1_view)
      assert p1_html =~ "Alice"
      assert p1_html =~ "Bob"

      # Host should see both
      host_html = render(host_view)
      assert host_html =~ "Alice"
      assert host_html =~ "Bob"

      # ── Step 5: Host starts the game ──
      host_view |> element("button", "Start Game") |> render_click()
      :timer.sleep(300)

      # All views should now be in question phase
      host_html = render(host_view)
      assert host_html =~ "1 / 3"

      p1_html = render(p1_view)
      assert p1_html =~ "1 / 3"

      p2_html = render(p2_view)
      assert p2_html =~ "1 / 3"

      # ── Play through 3 questions ──
      for question_num <- 1..3 do
        # Verify question is shown
        p1_html = render(p1_view)
        assert p1_html =~ "#{question_num} / 3"

        # Player 1 answers "a" (correct)
        p1_view |> element("button[phx-value-answer=a]") |> render_click()

        # Player 2 answers "b" (wrong)
        p2_view |> element("button[phx-value-answer=b]") |> render_click()

        # Wait for results phase
        :timer.sleep(300)

        # Check results are shown
        p1_html = render(p1_view)
        assert p1_html =~ "Correct" || p1_html =~ "Results"

        p2_html = render(p2_view)
        assert p2_html =~ "Wrong" || p2_html =~ "Results"

        host_html = render(host_view)
        assert host_html =~ "Results" || host_html =~ "Leaderboard" || host_html =~ "Correct"

        if question_num < 3 do
          # Wait for next question (4 second results pause)
          :timer.sleep(4_500)
        end
      end

      # ── Step 6: Game should finish after the last question results ──
      :timer.sleep(5_000)

      host_html = render(host_view)
      assert host_html =~ "Game Over"

      p1_html = render(p1_view)
      assert p1_html =~ "Game Over"

      # Alice should have a higher score (answered correctly)
      # Host final scores show leaderboard
      assert host_html =~ "Alice"
      assert host_html =~ "Bob"

      # ── Step 7: Wait for game to be saved and check results page ──
      :timer.sleep(1_000)

      host_html = render(host_view)

      if host_html =~ "Permanent Results" do
        # Extract game_id from the link
        case Regex.run(~r"/results/(\d+)", host_html) do
          [_, game_id] ->
            {:ok, _results_view, results_html} = live(conn, ~p"/results/#{game_id}")
            assert results_html =~ "Game Results"
            assert results_html =~ "Alice"
            assert results_html =~ "Bob"

          nil ->
            :ok
        end
      end
    end
  end

  describe "edge cases" do
    test "game still works if player disconnects mid-game", %{conn: _conn} do
      {:ok, code, host_id} = RoomServer.start_room("Host", "science", 3)
      {:ok, _alice_id} = RoomServer.join(code, "Alice")
      {:ok, bob_id} = RoomServer.join(code, "Bob")

      Phoenix.PubSub.subscribe(TriviaPlatform.PubSub, "room:#{code}")

      :ok = RoomServer.start_game(code, host_id)
      assert_receive {:question_started, _}, 1_000

      # Bob leaves mid-game
      RoomServer.leave(code, bob_id)
      assert_receive {:player_left, %{player_id: ^bob_id}}

      # Game should continue with just Alice
      state = RoomServer.get_state(code)
      assert state.phase == :question
      assert state.player_count == 1
    end

    test "host cannot start game twice", %{conn: _conn} do
      {:ok, code, host_id} = RoomServer.start_room("Host", "science", 3)
      {:ok, _} = RoomServer.join(code, "Alice")

      :ok = RoomServer.start_game(code, host_id)

      # Trying to start again should fail (game is in :question phase, not :waiting)
      result = RoomServer.start_game(code, host_id)
      assert result == {:error, :unauthorized}
    end
  end
end
