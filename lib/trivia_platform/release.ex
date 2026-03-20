defmodule TriviaPlatform.Release do
  @moduledoc """
  Release tasks that can be run via remote console in production.

  ## Usage (Fly.io)

      fly ssh console
      > bin/trivia_platform rpc "TriviaPlatform.Release.migrate()"
      > bin/trivia_platform rpc "TriviaPlatform.Release.import_questions()"
  """

  @app :trivia_platform

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def import_questions(opts \\ []) do
    Application.ensure_all_started(@app)
    TriviaPlatform.Questions.Importer.import(opts)
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
