defmodule TriviaPlatform.Questions.Importer do
  @moduledoc """
  Fetches trivia questions from the Open Trivia Database API and inserts them
  into PostgreSQL. Handles HTML entity decoding, category mapping, duplicate
  detection, and API rate limiting.
  """

  require Logger

  alias TriviaPlatform.Repo
  alias TriviaPlatform.Questions.Question

  import Ecto.Query

  # Open Trivia DB category IDs mapped to our categories
  @category_map %{
    9 => "science",
    17 => "science",
    18 => "science",
    19 => "science",
    23 => "history",
    22 => "geography",
    11 => "entertainment",
    12 => "entertainment",
    14 => "entertainment",
    15 => "entertainment",
    21 => "sports",
    27 => "geography",
    20 => "history"
  }

  @api_base "https://opentdb.com/api.php"
  @rate_limit_ms 5_500

  @doc """
  Imports questions from Open Trivia DB into PostgreSQL.

  Options:
    - `:count` — questions per category request (max 50, default 50)

  Returns `{:ok, imported_count}` or `{:error, reason}`.
  """
  def import(opts \\ []) do
    count = min(opts[:count] || 50, 50)
    categories = Map.keys(@category_map)

    Logger.info(
      "Starting import from Open Trivia DB (#{length(categories)} categories, #{count} per request)"
    )

    existing = load_existing_texts()

    {total, _} =
      Enum.reduce(categories, {0, existing}, fn cat_id, {imported_so_far, seen} ->
        case fetch_category(cat_id, count) do
          {:ok, results} ->
            {new_count, updated_seen} = insert_results(results, cat_id, seen)

            Logger.info(
              "Category #{cat_id} (#{@category_map[cat_id]}): " <>
                "fetched #{length(results)}, inserted #{new_count} new"
            )

            # Rate limit between requests
            Process.sleep(@rate_limit_ms)
            {imported_so_far + new_count, updated_seen}

          {:error, reason} ->
            Logger.warning("Failed to fetch category #{cat_id}: #{inspect(reason)}")
            Process.sleep(@rate_limit_ms)
            {imported_so_far, seen}
        end
      end)

    Logger.info("Import complete: #{total} new questions added")
    {:ok, total}
  end

  defp fetch_category(category_id, count) do
    url = "#{@api_base}?amount=#{count}&category=#{category_id}&type=multiple"

    case Req.get(url, receive_timeout: 15_000) do
      {:ok, %{status: 200, body: %{"response_code" => 0, "results" => results}}} ->
        {:ok, results}

      {:ok, %{status: 200, body: %{"response_code" => code}}} ->
        {:error, "API response code: #{code}"}

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp insert_results(results, cat_id, seen) do
    our_category = Map.fetch!(@category_map, cat_id)

    Enum.reduce(results, {0, seen}, fn result, {count, seen_set} ->
      question_text = decode_html(result["question"])

      if MapSet.member?(seen_set, question_text) do
        {count, seen_set}
      else
        correct = decode_html(result["correct_answer"])
        incorrects = Enum.map(result["incorrect_answers"], &decode_html/1)

        # Shuffle correct answer into a random position
        {options, correct_letter} = shuffle_options(correct, incorrects)

        attrs = %{
          category: our_category,
          question_text: question_text,
          option_a: Enum.at(options, 0),
          option_b: Enum.at(options, 1),
          option_c: Enum.at(options, 2),
          option_d: Enum.at(options, 3),
          correct_answer: correct_letter,
          difficulty: result["difficulty"] || "medium"
        }

        case insert_question(attrs) do
          {:ok, _} ->
            {count + 1, MapSet.put(seen_set, question_text)}

          {:error, _} ->
            {count, seen_set}
        end
      end
    end)
  end

  defp insert_question(attrs) do
    %Question{}
    |> Question.changeset(attrs)
    |> Repo.insert()
  end

  defp shuffle_options(correct, incorrects) do
    all = [correct | incorrects]
    shuffled = Enum.shuffle(all)
    correct_index = Enum.find_index(shuffled, &(&1 == correct))
    letter = Enum.at(~w(a b c d), correct_index)
    {shuffled, letter}
  end

  defp load_existing_texts do
    Question
    |> select([q], q.question_text)
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Decodes common HTML entities found in Open Trivia DB responses.
  """
  def decode_html(text) do
    text
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#039;", "'")
    |> String.replace("&shy;", "")
    |> String.replace("&eacute;", "é")
    |> String.replace("&ouml;", "ö")
    |> String.replace("&uuml;", "ü")
    |> String.replace("&ntilde;", "ñ")
    |> String.replace("&rsquo;", "'")
    |> String.replace("&lsquo;", "'")
    |> String.replace("&rdquo;", "\u201D")
    |> String.replace("&ldquo;", "\u201C")
    |> String.replace("&hellip;", "…")
    |> String.replace("&pi;", "π")
  end
end
