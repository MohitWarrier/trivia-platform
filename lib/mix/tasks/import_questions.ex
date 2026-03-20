defmodule Mix.Tasks.ImportQuestions do
  @moduledoc """
  Imports trivia questions from the Open Trivia Database API into PostgreSQL.

  ## Usage

      mix import_questions              # fetch ~50 per category (default)
      mix import_questions --count 20   # fetch 20 per category

  Questions are inserted into the `questions` table. Duplicates (matching
  question_text) are automatically skipped.
  """

  use Mix.Task

  @shortdoc "Imports questions from Open Trivia DB into the database"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    opts = parse_args(args)

    Mix.shell().info("Importing questions from Open Trivia DB...")

    {:ok, count} = TriviaPlatform.Questions.Importer.import(opts)
    total = TriviaPlatform.Repo.aggregate(TriviaPlatform.Questions.Question, :count)
    Mix.shell().info("Done! Imported #{count} new questions. Total in database: #{total}")
  end

  defp parse_args(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [count: :integer])
    opts
  end
end
