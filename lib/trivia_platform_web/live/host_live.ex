defmodule TriviaPlatformWeb.HostLive do
  use TriviaPlatformWeb, :live_view

  alias TriviaPlatform.Rooms.RoomServer
  alias TriviaPlatformWeb.Presence

  @impl true
  def mount(%{"code" => code} = params, _session, socket) do
    host_id = params["host_id"]

    if connected?(socket) do
      Phoenix.PubSub.subscribe(TriviaPlatform.PubSub, "room:#{code}")
      Phoenix.PubSub.subscribe(TriviaPlatform.PubSub, "presence:room:#{code}")

      # Track host in Presence
      if host_id do
        Presence.track(self(), "presence:room:#{code}", "host:#{host_id}", %{
          name: "Host",
          role: :host,
          joined_at: System.system_time(:second)
        })
      end
    end

    case RoomServer.get_state(code) do
      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Room not found")
         |> push_navigate(to: ~p"/")}

      state ->
        {:ok,
         assign(socket,
           page_title: "Host - Room #{code}",
           room_code: code,
           host_id: host_id,
           phase: state.phase,
           players: state.players,
           timer_seconds: state.timer_seconds,
           current_question: nil,
           question_index: state.current_question_index,
           total_questions: state.total_questions,
           answered_count: state.answered_count,
           correct_answer: nil,
           scores: state.players,
           final_scores: [],
           game_id: nil
         )}
    end
  end

  @impl true
  def handle_event("start_game", _params, socket) do
    RoomServer.start_game(socket.assigns.room_code, socket.assigns.host_id)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:player_joined, %{name: _name}}, socket) do
    case RoomServer.get_state(socket.assigns.room_code) do
      {:error, _} -> {:noreply, socket}
      state -> {:noreply, assign(socket, players: state.players)}
    end
  end

  def handle_info({:player_left, _}, socket) do
    case RoomServer.get_state(socket.assigns.room_code) do
      {:error, _} -> {:noreply, socket}
      state -> {:noreply, assign(socket, players: state.players)}
    end
  end

  def handle_info({:question_started, data}, socket) do
    {:noreply,
     assign(socket,
       phase: :question,
       current_question: data,
       timer_seconds: data.timer,
       question_index: data.question_index,
       total_questions: data.total_questions,
       answered_count: 0,
       correct_answer: nil
     )}
  end

  def handle_info({:timer_tick, %{seconds: seconds}}, socket) do
    {:noreply, assign(socket, timer_seconds: seconds)}
  end

  def handle_info({:answer_received, %{answered_count: count}}, socket) do
    {:noreply, assign(socket, answered_count: count)}
  end

  def handle_info({:results, data}, socket) do
    {:noreply,
     assign(socket,
       phase: :results,
       correct_answer: data.correct_answer,
       scores: data.scores,
       question_index: data.question_index,
       total_questions: data.total_questions
     )}
  end

  def handle_info({:game_finished, %{final_scores: scores}}, socket) do
    {:noreply, assign(socket, phase: :finished, final_scores: scores)}
  end

  def handle_info({:game_saved, %{game_id: game_id}}, socket) do
    {:noreply, assign(socket, game_id: game_id)}
  end

  def handle_info({:player_rejoined, _data}, socket) do
    case RoomServer.get_state(socket.assigns.room_code) do
      {:error, _} -> {:noreply, socket}
      state -> {:noreply, assign(socket, players: state.players)}
    end
  end

  def handle_info({:player_disconnected, _data}, socket) do
    case RoomServer.get_state(socket.assigns.room_code) do
      {:error, _} -> {:noreply, socket}
      state -> {:noreply, assign(socket, players: state.players)}
    end
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col items-center px-4 py-8">
      <%!-- Room Code Header --%>
      <div class="text-center mb-8 animate-slide-up">
        <p class="text-xs font-semibold text-base-content/50 uppercase tracking-widest mb-1">
          Room Code
        </p>
        <div class="inline-flex items-center gap-2 bg-base-200 border-2 border-primary/30 rounded-2xl px-6 py-3">
          <p class="text-4xl sm:text-5xl font-mono font-black text-primary tracking-[0.3em]">
            {@room_code}
          </p>
        </div>
        <p class="text-sm text-base-content/50 mt-2">
          Share this code with players to join
        </p>
      </div>

      <%!-- Phase content --%>
      <div class="w-full max-w-2xl">
        <%= case @phase do %>
          <% :waiting -> %>
            <.waiting_phase players={@players} />
            <div class="text-center mt-8">
              <button
                phx-click="start_game"
                class={[
                  "btn btn-lg gap-2 px-10",
                  length(@players) >= 1 && "btn-primary animate-pulse-glow",
                  length(@players) < 1 && "btn-disabled"
                ]}
                disabled={length(@players) < 1}
              >
                <.icon name="hero-play-solid" class="size-6" /> Start Game
              </button>
              <p :if={length(@players) < 1} class="text-sm text-base-content/40 mt-3">
                Waiting for at least 1 player to join...
              </p>
            </div>
          <% :question -> %>
            <.question_phase
              question={@current_question}
              timer={@timer_seconds}
              index={@question_index}
              total={@total_questions}
              answered={@answered_count}
              player_count={length(@players)}
            />
          <% :results -> %>
            <.results_phase
              scores={@scores}
              correct_answer={@correct_answer}
              question={@current_question}
              index={@question_index}
              total={@total_questions}
            />
          <% :finished -> %>
            <.finished_phase scores={@final_scores} game_id={@game_id} />
        <% end %>
      </div>
    </div>
    """
  end

  defp waiting_phase(assigns) do
    ~H"""
    <div class="card bg-base-200 shadow-xl border border-base-300 animate-slide-up">
      <div class="card-body">
        <div class="flex items-center gap-2 mb-2">
          <.icon name="hero-users" class="size-5 text-primary" />
          <h2 class="card-title text-xl">Players ({length(@players)})</h2>
        </div>

        <div :if={@players == []} class="text-center py-12">
          <div class="inline-flex items-center justify-center w-16 h-16 rounded-full bg-base-300 mb-4">
            <.icon name="hero-user-plus" class="size-8 text-base-content/30" />
          </div>
          <p class="text-base-content/40 text-lg">No players yet</p>
          <p class="text-base-content/30 text-sm mt-1">Share the room code above!</p>
        </div>

        <div class="flex flex-wrap gap-3 mt-2">
          <div
            :for={{player, idx} <- Enum.with_index(@players)}
            class={[
              "animate-bounce-in flex items-center gap-2 rounded-full py-2 px-4 border",
              Map.get(player, :connected, true) && "bg-primary/10 border-primary/20",
              !Map.get(player, :connected, true) && "bg-base-300 border-base-300 opacity-50"
            ]}
            style={"animation-delay: #{idx * 100}ms"}
          >
            <div class="relative">
              <div class="w-8 h-8 rounded-full bg-primary flex items-center justify-center text-primary-content text-sm font-bold">
                {String.first(player.name) |> String.upcase()}
              </div>
              <div class={[
                "absolute -bottom-0.5 -right-0.5 w-3 h-3 rounded-full border-2 border-base-100",
                Map.get(player, :connected, true) && "bg-success",
                !Map.get(player, :connected, true) && "bg-base-content/30"
              ]} />
            </div>
            <span class="font-semibold text-base-content">{player.name}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp question_phase(assigns) do
    ~H"""
    <div class="space-y-6 animate-slide-up">
      <%!-- Progress bar --%>
      <div class="flex items-center gap-4">
        <span class="badge badge-primary badge-lg font-bold">
          {(@index || 0) + 1} / {@total}
        </span>
        <progress
          class="progress progress-primary flex-1"
          value={(@index || 0) + 1}
          max={@total}
        />
        <.timer_display seconds={@timer} />
      </div>

      <%!-- Question --%>
      <div class="card bg-base-200 shadow-xl border border-base-300">
        <div class="card-body text-center py-8">
          <h2 class="text-2xl sm:text-3xl font-bold leading-snug">
            {@question[:question_text]}
          </h2>
        </div>
      </div>

      <%!-- Answer options (display only for host) --%>
      <div class="grid grid-cols-2 gap-3">
        <div class="card bg-error/15 border border-error/30 p-4">
          <span class="badge badge-error badge-sm mb-1">A</span>
          <span class="font-medium">{@question[:option_a]}</span>
        </div>
        <div class="card bg-info/15 border border-info/30 p-4">
          <span class="badge badge-info badge-sm mb-1">B</span>
          <span class="font-medium">{@question[:option_b]}</span>
        </div>
        <div class="card bg-warning/15 border border-warning/30 p-4">
          <span class="badge badge-warning badge-sm mb-1">C</span>
          <span class="font-medium">{@question[:option_c]}</span>
        </div>
        <div class="card bg-success/15 border border-success/30 p-4">
          <span class="badge badge-success badge-sm mb-1">D</span>
          <span class="font-medium">{@question[:option_d]}</span>
        </div>
      </div>

      <%!-- Answer progress --%>
      <div class="card bg-base-200 border border-base-300">
        <div class="card-body py-4 flex-row items-center justify-center gap-3">
          <.icon name="hero-hand-raised" class="size-5 text-primary" />
          <span class="text-lg font-semibold">
            {@answered} / {@player_count}
          </span>
          <span class="text-base-content/50">players answered</span>
        </div>
      </div>
    </div>
    """
  end

  defp results_phase(assigns) do
    ~H"""
    <div class="space-y-6 animate-slide-up">
      <div class="text-center">
        <span class="badge badge-primary badge-lg font-bold">
          Question {(@index || 0) + 1} / {@total} — Results
        </span>
      </div>

      <div :if={@question} class="card bg-success/10 border-2 border-success/30 shadow-xl">
        <div class="card-body text-center py-6">
          <p class="text-base-content/60 text-sm">{@question[:question_text]}</p>
          <div class="flex items-center justify-center gap-2 mt-2">
            <.icon name="hero-check-circle-solid" class="size-7 text-success" />
            <p class="text-xl font-bold text-success">
              {answer_label(@correct_answer)} — {get_correct_option(@question, @correct_answer)}
            </p>
          </div>
        </div>
      </div>

      <.leaderboard scores={@scores} />
    </div>
    """
  end

  defp finished_phase(assigns) do
    ~H"""
    <div class="space-y-6 text-center animate-slide-up">
      <h2 class="text-4xl font-extrabold">Game Over!</h2>

      <%!-- Winner spotlight --%>
      <div :if={@scores != []} class="animate-bounce-in">
        <div class="card bg-gradient-to-br from-warning/20 to-primary/20 border-2 border-warning/30 shadow-xl p-8">
          <div class="text-5xl mb-3">
            <.icon name="hero-trophy-solid" class="size-12 text-warning mx-auto" />
          </div>
          <p class="text-sm text-base-content/50 uppercase tracking-widest font-semibold">Winner</p>
          <p class="text-4xl font-extrabold text-primary mt-1">{hd(@scores).name}</p>
          <p class="text-2xl font-bold mt-2">
            {hd(@scores).score} <span class="text-base-content/50 text-lg">points</span>
          </p>
        </div>
      </div>

      <.leaderboard scores={@scores} />

      <div class="flex gap-4 justify-center pt-4">
        <.link navigate={~p"/"} class="btn btn-primary btn-lg gap-2">
          <.icon name="hero-arrow-path" class="size-5" /> Play Again
        </.link>
        <.link :if={@game_id} navigate={~p"/results/#{@game_id}"} class="btn btn-outline btn-lg gap-2">
          <.icon name="hero-clipboard-document-list" class="size-5" /> Permanent Results
        </.link>
      </div>
    </div>
    """
  end

  defp leaderboard(assigns) do
    ~H"""
    <div class="card bg-base-200 shadow-xl border border-base-300">
      <div class="card-body">
        <div class="flex items-center gap-2 mb-2">
          <.icon name="hero-chart-bar" class="size-5 text-primary" />
          <h3 class="card-title">Leaderboard</h3>
        </div>
        <div class="overflow-x-auto">
          <table class="table">
            <thead>
              <tr class="text-base-content/50">
                <th class="w-12">#</th>
                <th>Player</th>
                <th class="text-right">Score</th>
                <th class="text-right">Correct</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={{player, idx} <- Enum.with_index(@scores, 1)} class="hover">
                <td>
                  <span :if={idx == 1} class="text-lg">
                    <.icon name="hero-trophy-solid" class="size-5 text-warning" />
                  </span>
                  <span :if={idx == 2} class="font-bold text-base-content/60">{idx}</span>
                  <span :if={idx == 3} class="font-bold text-accent">{idx}</span>
                  <span :if={idx > 3} class="text-base-content/40">{idx}</span>
                </td>
                <td class="font-semibold">{player.name}</td>
                <td class="text-right font-mono font-bold">{player.score}</td>
                <td class="text-right text-base-content/60">{player.correct_answers}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  defp timer_display(assigns) do
    ~H"""
    <div class={[
      "flex items-center justify-center w-14 h-14 rounded-full border-4 font-mono text-xl font-black transition-colors",
      @seconds > 5 && "border-primary text-primary",
      @seconds <= 5 && @seconds > 0 && "border-error text-error animate-pulse"
    ]}>
      {@seconds}
    </div>
    """
  end

  defp answer_label("a"), do: "A"
  defp answer_label("b"), do: "B"
  defp answer_label("c"), do: "C"
  defp answer_label("d"), do: "D"
  defp answer_label(_), do: "?"

  defp get_correct_option(nil, _), do: ""
  defp get_correct_option(question, "a"), do: question[:option_a]
  defp get_correct_option(question, "b"), do: question[:option_b]
  defp get_correct_option(question, "c"), do: question[:option_c]
  defp get_correct_option(question, "d"), do: question[:option_d]
  defp get_correct_option(_, _), do: ""
end
