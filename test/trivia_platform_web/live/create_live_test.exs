defmodule TriviaPlatformWeb.CreateLiveTest do
  use TriviaPlatformWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "mounting" do
    test "renders the custom question builder", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/create")

      assert html =~ "Custom"
      assert html =~ "Add Question"
      assert html =~ "Your Name"
    end
  end

  describe "adding questions" do
    test "adds a question to the list", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/create")

      html =
        view
        |> form("form", %{
          question_text: "What is 1+1?",
          option_a: "1",
          option_b: "2",
          option_c: "3",
          option_d: "4",
          correct_answer: "b"
        })
        |> render_submit()

      assert html =~ "What is 1+1?"
      assert html =~ "1 added" || html =~ "Your Questions (1)"
    end

    test "shows error for missing question text", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/create")

      html =
        view
        |> form("form", %{
          question_text: "",
          option_a: "A",
          option_b: "B",
          option_c: "C",
          option_d: "D",
          correct_answer: "a"
        })
        |> render_submit()

      assert html =~ "Question text is required"
    end

    test "shows error when no correct answer selected", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/create")

      html =
        view
        |> form("form", %{
          question_text: "Test?",
          option_a: "A",
          option_b: "B",
          option_c: "C",
          option_d: "D"
        })
        |> render_submit()

      assert html =~ "Select the correct answer"
    end

    test "can remove a question", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/create")

      # Add a question
      view
      |> form("form", %{
        question_text: "Remove me?",
        option_a: "A",
        option_b: "B",
        option_c: "C",
        option_d: "D",
        correct_answer: "a"
      })
      |> render_submit()

      html = render(view)
      assert html =~ "Remove me?"

      # Remove it
      html =
        view
        |> element("button[phx-click=remove_question]")
        |> render_click()

      refute html =~ "Remove me?"
    end
  end

  describe "creating a game" do
    test "shows error when fewer than 3 questions", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/create")

      # Add only 2 questions
      for q <- ["Q1?", "Q2?"] do
        view
        |> form("form", %{
          question_text: q,
          option_a: "A",
          option_b: "B",
          option_c: "C",
          option_d: "D",
          correct_answer: "a"
        })
        |> render_submit()
      end

      # Try to create — button is disabled but test the event directly
      html = render(view)
      assert html =~ "Add at least 3 questions"
    end

    test "creates game and redirects to host page with 3+ questions", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/create")

      # Set host name
      view |> element("input[name=host_name]") |> render_blur(%{"value" => "TestHost"})

      # Add 3 questions
      for q <- ["Q1?", "Q2?", "Q3?"] do
        view
        |> form("form", %{
          question_text: q,
          option_a: "A",
          option_b: "B",
          option_c: "C",
          option_d: "D",
          correct_answer: "a"
        })
        |> render_submit()
      end

      # Create game
      assert {:error, {:live_redirect, %{to: path}}} =
               view |> element("button[phx-click=create_game]") |> render_click()

      assert path =~ ~r"/host/[A-Z2-9]{6}"
      assert path =~ "token="
    end
  end
end
