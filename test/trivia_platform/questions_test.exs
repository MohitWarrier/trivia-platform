defmodule TriviaPlatform.QuestionsTest do
  use TriviaPlatform.DataCase, async: true

  alias TriviaPlatform.Questions
  alias TriviaPlatform.Questions.Question

  setup do
    for i <- 1..5 do
      Repo.insert!(%Question{
        category: "science",
        question_text: "Science question #{i}?",
        option_a: "A",
        option_b: "B",
        option_c: "C",
        option_d: "D",
        correct_answer: "a",
        difficulty: "medium"
      })
    end

    for i <- 1..3 do
      Repo.insert!(%Question{
        category: "history",
        question_text: "History question #{i}?",
        option_a: "A",
        option_b: "B",
        option_c: "C",
        option_d: "D",
        correct_answer: "b",
        difficulty: "easy"
      })
    end

    :ok
  end

  describe "list_categories/0" do
    test "returns all valid categories" do
      categories = Questions.list_categories()
      assert "science" in categories
      assert "history" in categories
      assert "geography" in categories
      assert "entertainment" in categories
      assert "sports" in categories
      assert length(categories) == 5
    end
  end

  describe "get_random_questions/2" do
    test "returns requested number of questions for a category" do
      questions = Questions.get_random_questions("science", 3)
      assert length(questions) == 3
      assert Enum.all?(questions, &(&1.category == "science"))
    end

    test "returns all available if count exceeds available" do
      questions = Questions.get_random_questions("history", 10)
      assert length(questions) == 3
    end

    test "returns empty list for category with no questions" do
      questions = Questions.get_random_questions("geography", 5)
      assert questions == []
    end

    test "returns different orderings (randomness)" do
      # Run multiple times and check we get different orderings at least once
      results =
        for _ <- 1..10 do
          Questions.get_random_questions("science", 5)
          |> Enum.map(& &1.id)
        end

      unique_orderings = Enum.uniq(results)
      # With 5 questions, very unlikely to get same order 10 times
      assert length(unique_orderings) > 1
    end
  end
end
