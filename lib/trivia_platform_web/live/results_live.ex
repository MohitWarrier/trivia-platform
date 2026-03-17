defmodule TriviaPlatformWeb.ResultsLive do
  use TriviaPlatformWeb, :live_view

  alias TriviaPlatform.Games

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Games.get_game_with_results(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Game not found")
         |> push_navigate(to: ~p"/")}

      game ->
        {:ok,
         assign(socket,
           page_title: "Results - #{game.room_code}",
           game: game,
           results: game.results
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col items-center px-4 py-8">
      <%!-- Header --%>
      <div class="text-center mb-8 animate-slide-up">
        <div class="inline-flex items-center justify-center w-14 h-14 rounded-full bg-primary/10 mb-4">
          <.icon name="hero-clipboard-document-list-solid" class="size-7 text-primary" />
        </div>
        <h1 class="text-3xl font-extrabold">Game Results</h1>
        <div class="flex flex-wrap items-center justify-center gap-2 mt-3">
          <span class="badge badge-primary badge-lg">{@game.category |> String.capitalize()}</span>
          <span class="badge badge-outline badge-lg">{@game.question_count} questions</span>
          <span class="badge badge-outline badge-lg">{@game.player_count} players</span>
        </div>
        <p class="text-base-content/40 text-sm mt-2">
          Hosted by {@game.host_name} | Room {@game.room_code}
        </p>
      </div>

      <div class="w-full max-w-xl space-y-6">
        <%!-- Winner highlight --%>
        <div :if={@results != []} class="animate-bounce-in">
          <div class="card bg-gradient-to-br from-warning/20 to-primary/20 border-2 border-warning/30 shadow-xl text-center p-8">
            <.icon name="hero-trophy-solid" class="size-12 text-warning mx-auto" />
            <p class="text-sm text-base-content/50 uppercase tracking-widest font-semibold mt-3">
              Winner
            </p>
            <p class="text-4xl font-extrabold text-primary mt-1">{hd(@results).player_name}</p>
            <p class="text-2xl font-bold mt-2">
              {hd(@results).final_score} <span class="text-base-content/50 text-lg">points</span>
            </p>
            <p class="text-base-content/50 mt-1">{hd(@results).correct_answers} correct answers</p>
          </div>
        </div>

        <%!-- Full leaderboard --%>
        <div class="card bg-base-200 shadow-xl border border-base-300 animate-slide-up">
          <div class="card-body">
            <div class="flex items-center gap-2 mb-2">
              <.icon name="hero-chart-bar" class="size-5 text-primary" />
              <h3 class="card-title">Final Leaderboard</h3>
            </div>
            <div class="overflow-x-auto">
              <table class="table">
                <thead>
                  <tr class="text-base-content/50">
                    <th class="w-16">Rank</th>
                    <th>Player</th>
                    <th class="text-right">Score</th>
                    <th class="text-right">Correct</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={result <- @results} class={["hover", result.rank == 1 && "font-bold"]}>
                    <td>
                      <span :if={result.rank == 1}>
                        <.icon name="hero-trophy-solid" class="size-5 text-warning" />
                      </span>
                      <span :if={result.rank == 2} class="font-bold text-base-content/60">
                        {result.rank}
                      </span>
                      <span :if={result.rank == 3} class="font-bold text-accent">{result.rank}</span>
                      <span :if={result.rank > 3} class="text-base-content/40">{result.rank}</span>
                    </td>
                    <td class="font-semibold">{result.player_name}</td>
                    <td class="text-right font-mono font-bold">{result.final_score}</td>
                    <td class="text-right text-base-content/60">{result.correct_answers}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>

        <div class="text-center pt-2">
          <.link navigate={~p"/"} class="btn btn-primary btn-lg gap-2">
            <.icon name="hero-arrow-path" class="size-5" /> Play Again
          </.link>
        </div>
      </div>
    </div>
    """
  end
end
