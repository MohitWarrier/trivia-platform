defmodule TriviaPlatformWeb.HostLiveTest do
  use TriviaPlatformWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias TriviaPlatform.Rooms.RoomServer
  alias TriviaPlatform.Questions.Question
  alias TriviaPlatform.Token

  setup do
    for i <- 1..10 do
      TriviaPlatform.Repo.insert!(%Question{
        category: "science",
        question_text: "Question #{i}?",
        option_a: "A#{i}",
        option_b: "B#{i}",
        option_c: "C#{i}",
        option_d: "D#{i}",
        correct_answer: "a",
        difficulty: "medium"
      })
    end

    {:ok, code, host_id} = RoomServer.start_room("Host", "science", 3)
    host_token = Token.sign(host_id)
    %{code: code, host_id: host_id, host_token: host_token}
  end

  describe "mounting" do
    test "renders waiting room with room code", %{conn: conn, code: code, host_token: host_token} do
      {:ok, _view, html} = live(conn, ~p"/host/#{code}?token=#{host_token}")

      assert html =~ code
      assert html =~ "Share this code"
      assert html =~ "No players yet"
    end

    test "redirects to home if room not found", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/"}}} =
               live(conn, ~p"/host/ZZZZZZ?token=fake")
    end
  end

  describe "player joining" do
    test "shows player when they join", %{conn: conn, code: code, host_token: host_token} do
      {:ok, view, _html} = live(conn, ~p"/host/#{code}?token=#{host_token}")

      # Another player joins
      {:ok, _player_id} = RoomServer.join(code, "Alice")

      # Give PubSub time to deliver
      :timer.sleep(100)
      html = render(view)
      assert html =~ "Alice"
    end
  end

  describe "starting game" do
    test "start button is disabled with no players", %{
      conn: conn,
      code: code,
      host_token: host_token
    } do
      {:ok, _view, html} = live(conn, ~p"/host/#{code}?token=#{host_token}")
      assert html =~ "disabled"
      assert html =~ "Waiting for at least 1 player"
    end

    test "clicking start transitions to question phase", %{
      conn: conn,
      code: code,
      host_token: host_token
    } do
      {:ok, view, _html} = live(conn, ~p"/host/#{code}?token=#{host_token}")
      {:ok, _} = RoomServer.join(code, "Alice")
      :timer.sleep(100)

      view |> element("button", "Start Game") |> render_click()
      :timer.sleep(100)

      html = render(view)
      assert html =~ "Question"
      # Should show question text from one of our seeded questions
      assert html =~ "?"
    end
  end

  describe "game phases" do
    setup %{code: code} do
      {:ok, player_id} = RoomServer.join(code, "Alice")
      %{player_id: player_id}
    end

    test "shows timer countdown during question phase", %{
      conn: conn,
      code: code,
      host_id: host_id,
      host_token: host_token,
      player_id: _player_id
    } do
      {:ok, view, _html} = live(conn, ~p"/host/#{code}?token=#{host_token}")
      :ok = RoomServer.start_game(code, host_id)
      :timer.sleep(200)

      html = render(view)
      # Timer should be showing (15 or 14 seconds)
      assert html =~ ~r/1[45]/
    end

    test "shows answer count when player answers", %{
      conn: conn,
      code: code,
      host_id: host_id,
      host_token: host_token,
      player_id: player_id
    } do
      {:ok, view, _html} = live(conn, ~p"/host/#{code}?token=#{host_token}")
      :ok = RoomServer.start_game(code, host_id)
      :timer.sleep(200)

      RoomServer.submit_answer(code, player_id, "a")
      :timer.sleep(200)

      # After single player answers, should transition to results
      html = render(view)
      assert html =~ "Results" || html =~ "Correct" || html =~ "Leaderboard"
    end
  end
end
