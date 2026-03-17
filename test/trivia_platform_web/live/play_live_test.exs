defmodule TriviaPlatformWeb.PlayLiveTest do
  use TriviaPlatformWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias TriviaPlatform.Rooms.RoomServer
  alias TriviaPlatform.Questions.Question

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
    %{code: code, host_id: host_id}
  end

  describe "mounting and joining" do
    test "player joins the room on mount", %{conn: conn, code: code} do
      {:ok, view, _html} = live(conn, ~p"/play/#{code}?name=Alice")

      # Wait for the :join_room message to be processed
      :timer.sleep(200)
      html = render(view)

      assert html =~ "Alice"
      assert html =~ "Waiting for host"
    end

    test "redirects to home if room not found", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/play/ZZZZZZ?name=Alice")
      :timer.sleep(200)

      assert_redirected(view, ~p"/")
    end

    test "uses 'Anonymous' when no name provided", %{conn: conn, code: code} do
      {:ok, view, _html} = live(conn, ~p"/play/#{code}")
      :timer.sleep(200)

      html = render(view)
      assert html =~ "Anonymous"
    end
  end

  describe "waiting phase" do
    test "shows other players in the waiting room", %{conn: conn, code: code} do
      # Another player joins first
      {:ok, _} = RoomServer.join(code, "Bob")

      {:ok, view, _html} = live(conn, ~p"/play/#{code}?name=Alice")
      :timer.sleep(200)

      html = render(view)
      assert html =~ "Bob"
      assert html =~ "Alice"
    end
  end

  describe "question phase" do
    test "shows question with answer buttons when game starts", %{
      conn: conn,
      code: code,
      host_id: host_id
    } do
      {:ok, view, _html} = live(conn, ~p"/play/#{code}?name=Alice")
      :timer.sleep(200)

      :ok = RoomServer.start_game(code, host_id)
      :timer.sleep(200)

      html = render(view)
      assert html =~ "1 / 3"
      # question text
      assert html =~ "?"
      # Answer buttons should be present
      assert has_element?(view, "button[phx-value-answer=a]")
      assert has_element?(view, "button[phx-value-answer=b]")
      assert has_element?(view, "button[phx-value-answer=c]")
      assert has_element?(view, "button[phx-value-answer=d]")
    end

    test "clicking an answer shows 'Answer submitted'", %{
      conn: conn,
      code: code,
      host_id: host_id
    } do
      {:ok, view, _html} = live(conn, ~p"/play/#{code}?name=Alice")
      :timer.sleep(200)

      :ok = RoomServer.start_game(code, host_id)
      :timer.sleep(200)

      view |> element("button[phx-value-answer=a]") |> render_click()

      # Since there's only 1 player, answering triggers results immediately
      :timer.sleep(200)
      html = render(view)

      # Either shows submitted confirmation or already moved to results
      assert html =~ "Correct" || html =~ "Wrong" || html =~ "Answer submitted"
    end
  end

  describe "results phase" do
    test "shows correct/wrong feedback after all answers submitted", %{
      conn: conn,
      code: code,
      host_id: host_id
    } do
      {:ok, view, _html} = live(conn, ~p"/play/#{code}?name=Alice")
      :timer.sleep(200)

      :ok = RoomServer.start_game(code, host_id)
      :timer.sleep(200)

      # Answer the question
      view |> element("button[phx-value-answer=a]") |> render_click()
      :timer.sleep(300)

      html = render(view)
      # Should be in results phase showing correct/wrong
      assert html =~ "Correct" || html =~ "Wrong"
    end
  end
end
