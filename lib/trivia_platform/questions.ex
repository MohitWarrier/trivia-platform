defmodule TriviaPlatform.Questions do
  import Ecto.Query
  alias TriviaPlatform.Repo
  alias TriviaPlatform.Questions.Question

  def list_categories do
    Question.categories()
  end

  def get_random_questions(category, count) do
    Question
    |> where([q], q.category == ^category)
    |> order_by(fragment("RANDOM()"))
    |> limit(^count)
    |> Repo.all()
  end
end
