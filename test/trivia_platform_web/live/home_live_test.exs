defmodule TriviaPlatformWeb.HomeLiveTest do
  use TriviaPlatformWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias TriviaPlatform.Questions.Question

  setup do
    for i <- 1..10 do
      TriviaPlatform.Repo.insert!(%Question{
        category: "science",
        question_text: "Question #{i}?",
        option_a: "A",
        option_b: "B",
        option_c: "C",
        option_d: "D",
        correct_answer: "a",
        difficulty: "medium"
      })
    end

    :ok
  end

  describe "mounting" do
    test "renders the home page with create and join forms", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/")

      assert html =~ "Trivia Platform"
      assert html =~ "Host a Game"
      assert html =~ "Join a Game"
      assert has_element?(view, "button", "Create Game")
      assert has_element?(view, "button", "Join Game")
    end

    test "shows category dropdown", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ "Science"
      assert html =~ "History"
    end
  end

  describe "create game" do
    test "creating a game redirects to host page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      {:error, {:live_redirect, %{to: path}}} =
        view
        |> form("form[phx-submit=create_game]", %{
          host_name: "TestHost",
          category: "science",
          question_count: "5"
        })
        |> render_submit()

      assert path =~ ~r"/host/[A-Z2-9]{6}"
    end

    test "shows error when name is empty", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html =
        view
        |> form("form[phx-submit=create_game]", %{
          host_name: "   ",
          category: "science",
          question_count: "5"
        })
        |> render_submit()

      assert html =~ "Please enter your name"
    end
  end

  describe "join game" do
    test "shows error for empty name", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html =
        view
        |> form("form[phx-submit=join_game]", %{
          player_name: "",
          room_code: "ABCDEF"
        })
        |> render_submit()

      assert html =~ "Please enter your name"
    end

    test "shows error for empty room code", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html =
        view
        |> form("form[phx-submit=join_game]", %{
          player_name: "Alice",
          room_code: ""
        })
        |> render_submit()

      assert html =~ "Please enter a room code"
    end

    test "shows error for non-existent room", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html =
        view
        |> form("form[phx-submit=join_game]", %{
          player_name: "Alice",
          room_code: "ZZZZZZ"
        })
        |> render_submit()

      assert html =~ "Room not found"
    end

    test "joining a valid room redirects to play page", %{conn: conn} do
      # Create a room first
      {:ok, code, _host_id} =
        TriviaPlatform.Rooms.RoomServer.start_room("Host", "science", 5)

      {:ok, view, _html} = live(conn, ~p"/")

      {:error, {:live_redirect, %{to: path}}} =
        view
        |> form("form[phx-submit=join_game]", %{
          player_name: "Alice",
          room_code: code
        })
        |> render_submit()

      assert path =~ "/play/#{code}"
    end
  end
end
