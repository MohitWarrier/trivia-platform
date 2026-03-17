defmodule TriviaPlatformWeb.PlayLive do
  use TriviaPlatformWeb, :live_view

  alias TriviaPlatform.Rooms.RoomServer
  alias TriviaPlatform.Token
  alias TriviaPlatformWeb.Presence

  @impl true
  def mount(%{"code" => code} = params, _session, socket) do
    player_name = params["name"] || "Anonymous"

    # Verify signed token for reconnection (prevents player ID forgery)
    reconnect_id =
      case params["token"] do
        nil ->
          nil

        token ->
          case Token.verify(token) do
            {:ok, player_id} -> player_id
            {:error, _} -> nil
          end
      end

    socket =
      assign(socket,
        page_title: "Playing - Room #{code}",
        room_code: code,
        player_name: player_name,
        player_id: nil,
        reconnect_id: reconnect_id,
        reconnect_token: nil,
        phase: :joining,
        players: [],
        timer_seconds: 15,
        current_question: nil,
        question_index: 0,
        total_questions: 0,
        answered: false,
        my_answer: nil,
        correct_answer: nil,
        scores: [],
        final_scores: [],
        game_id: nil,
        error: nil
      )

    if connected?(socket) do
      send(self(), :join_room)
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(:join_room, socket) do
    code = socket.assigns.room_code
    name = socket.assigns.player_name
    reconnect_id = socket.assigns.reconnect_id

    # Try reconnection first if we have a player_id
    result =
      if reconnect_id do
        case RoomServer.rejoin(code, reconnect_id) do
          {:ok, _name} -> {:reconnected, reconnect_id}
          {:error, _} -> RoomServer.join(code, name)
        end
      else
        RoomServer.join(code, name)
      end

    case result do
      {:reconnected, player_id} ->
        Phoenix.PubSub.subscribe(TriviaPlatform.PubSub, "room:#{code}")
        track_presence(socket, code, player_id, name)
        state = RoomServer.get_state(code)

        {:noreply,
         assign(socket,
           player_id: player_id,
           player_name: name,
           reconnect_token: Token.sign(player_id),
           phase: state.phase,
           players: state.players,
           total_questions: state.total_questions
         )}

      {:ok, player_id} ->
        Phoenix.PubSub.subscribe(TriviaPlatform.PubSub, "room:#{code}")
        track_presence(socket, code, player_id, name)
        state = RoomServer.get_state(code)

        {:noreply,
         assign(socket,
           player_id: player_id,
           reconnect_token: Token.sign(player_id),
           phase: state.phase,
           players: state.players,
           total_questions: state.total_questions
         )}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "Room not found")
         |> push_navigate(to: ~p"/")}

      {:error, :game_in_progress} ->
        {:noreply,
         socket
         |> put_flash(:error, "Game already in progress")
         |> push_navigate(to: ~p"/")}
    end
  end

  def handle_info({:player_joined, _data}, socket) do
    case RoomServer.get_state(socket.assigns.room_code) do
      {:error, _} -> {:noreply, socket}
      state -> {:noreply, assign(socket, players: state.players)}
    end
  end

  def handle_info({:player_left, _data}, socket) do
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
       answered: false,
       my_answer: nil,
       correct_answer: nil
     )}
  end

  def handle_info({:timer_tick, %{seconds: seconds}}, socket) do
    {:noreply, assign(socket, timer_seconds: seconds)}
  end

  def handle_info({:answer_received, _data}, socket) do
    {:noreply, socket}
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

  # Presence diff — someone went online/offline
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, socket}
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

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("answer", %{"answer" => answer}, socket) do
    unless socket.assigns.answered do
      RoomServer.submit_answer(socket.assigns.room_code, socket.assigns.player_id, answer)
    end

    {:noreply, assign(socket, answered: true, my_answer: answer)}
  end

  @impl true
  def terminate(_reason, socket) do
    if socket.assigns[:player_id] && socket.assigns[:room_code] do
      # Mark as disconnected (not leave) — allows reconnection during active games
      RoomServer.mark_disconnected(socket.assigns.room_code, socket.assigns.player_id)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col items-center px-4 py-8">
      <%!-- Player header --%>
      <div class="flex items-center gap-3 mb-6 animate-slide-up">
        <div class="badge badge-outline badge-lg gap-1">
          <.icon name="hero-signal" class="size-3" />
          {@room_code}
        </div>
        <div class="badge badge-primary badge-lg gap-1">
          <.icon name="hero-user-mini" class="size-3" />
          {@player_name}
        </div>
      </div>

      <div class="w-full max-w-xl">
        <%= case @phase do %>
          <% :joining -> %>
            <div class="text-center py-20 animate-slide-up">
              <span class="loading loading-spinner loading-lg text-primary"></span>
              <p class="mt-4 text-base-content/50 text-lg">Joining room...</p>
            </div>
          <% :waiting -> %>
            <.waiting_phase players={@players} />
          <% :question -> %>
            <.question_phase
              question={@current_question}
              timer={@timer_seconds}
              index={@question_index}
              total={@total_questions}
              answered={@answered}
              my_answer={@my_answer}
            />
          <% :results -> %>
            <.results_phase
              scores={@scores}
              correct_answer={@correct_answer}
              my_answer={@my_answer}
              question={@current_question}
              player_id={@player_id}
              index={@question_index}
              total={@total_questions}
            />
          <% :finished -> %>
            <.finished_phase
              scores={@final_scores}
              player_id={@player_id}
              player_name={@player_name}
              game_id={@game_id}
            />
        <% end %>
      </div>
    </div>
    """
  end

  defp waiting_phase(assigns) do
    ~H"""
    <div class="text-center space-y-6 animate-slide-up">
      <div class="py-12">
        <span class="loading loading-dots loading-lg text-primary"></span>
        <p class="text-xl font-semibold mt-4">Waiting for host to start...</p>
        <p class="text-base-content/40 text-sm mt-1">Get ready!</p>
      </div>

      <div class="card bg-base-200 border border-base-300">
        <div class="card-body">
          <div class="flex items-center justify-center gap-2 mb-3">
            <.icon name="hero-users" class="size-5 text-primary" />
            <h3 class="font-semibold">Players ({length(@players)})</h3>
          </div>
          <div class="flex flex-wrap gap-2 justify-center">
            <div
              :for={player <- @players}
              class="badge badge-primary badge-lg gap-1 py-3"
            >
              {player.name}
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp question_phase(assigns) do
    ~H"""
    <div class="space-y-5 animate-slide-up">
      <%!-- Progress + Timer --%>
      <div class="flex items-center gap-4">
        <span class="badge badge-primary badge-lg font-bold">
          {(@index || 0) + 1} / {@total}
        </span>
        <progress
          class="progress progress-primary flex-1"
          value={(@index || 0) + 1}
          max={@total}
        />
        <div class={[
          "flex items-center justify-center w-12 h-12 rounded-full border-4 font-mono text-lg font-black transition-colors",
          @timer > 5 && "border-primary text-primary",
          @timer <= 5 && @timer > 0 && "border-error text-error animate-pulse"
        ]}>
          {@timer}
        </div>
      </div>

      <%!-- Question --%>
      <div class="card bg-base-200 shadow-xl border border-base-300">
        <div class="card-body text-center py-6">
          <h2 class="text-xl sm:text-2xl font-bold leading-snug">
            {@question[:question_text]}
          </h2>
        </div>
      </div>

      <%!-- Answers or submitted state --%>
      <%= if @answered do %>
        <div class="text-center py-8 animate-bounce-in">
          <div class="inline-flex items-center gap-2 bg-success/10 border-2 border-success/30 rounded-2xl py-4 px-8">
            <.icon name="hero-check-circle-solid" class="size-8 text-success" />
            <span class="text-xl font-bold text-success">Answer submitted!</span>
          </div>
          <p class="text-base-content/40 mt-3">Waiting for other players...</p>
        </div>
      <% else %>
        <div class="grid grid-cols-1 gap-3">
          <button
            phx-click="answer"
            phx-value-answer="a"
            class="answer-btn btn btn-lg h-auto py-4 bg-error/10 border-2 border-error/40 hover:bg-error/20 justify-start text-left gap-3"
          >
            <span class="badge badge-error font-bold">A</span>
            <span class="flex-1 text-base-content">{@question[:option_a]}</span>
          </button>
          <button
            phx-click="answer"
            phx-value-answer="b"
            class="answer-btn btn btn-lg h-auto py-4 bg-info/10 border-2 border-info/40 hover:bg-info/20 justify-start text-left gap-3"
          >
            <span class="badge badge-info font-bold">B</span>
            <span class="flex-1 text-base-content">{@question[:option_b]}</span>
          </button>
          <button
            phx-click="answer"
            phx-value-answer="c"
            class="answer-btn btn btn-lg h-auto py-4 bg-warning/10 border-2 border-warning/40 hover:bg-warning/20 justify-start text-left gap-3"
          >
            <span class="badge badge-warning font-bold">C</span>
            <span class="flex-1 text-base-content">{@question[:option_c]}</span>
          </button>
          <button
            phx-click="answer"
            phx-value-answer="d"
            class="answer-btn btn btn-lg h-auto py-4 bg-success/10 border-2 border-success/40 hover:bg-success/20 justify-start text-left gap-3"
          >
            <span class="badge badge-success font-bold">D</span>
            <span class="flex-1 text-base-content">{@question[:option_d]}</span>
          </button>
        </div>
      <% end %>
    </div>
    """
  end

  defp results_phase(assigns) do
    my_score = Enum.find(assigns.scores, fn s -> s.id == assigns.player_id end)
    assigns = assign(assigns, :my_score, my_score)

    ~H"""
    <div class="space-y-5 text-center animate-slide-up">
      <span class="badge badge-primary badge-lg font-bold">
        Question {(@index || 0) + 1} / {@total} — Results
      </span>

      <%!-- Correct/Wrong feedback --%>
      <div class="animate-bounce-in">
        <div
          :if={@my_answer == @correct_answer}
          class="card bg-success/10 border-2 border-success/30 shadow-xl p-6"
        >
          <.icon name="hero-check-circle-solid" class="size-12 text-success mx-auto" />
          <p class="text-3xl font-extrabold text-success mt-2">Correct!</p>
          <p :if={@my_score} class="text-lg text-base-content/60 mt-1">
            +{@my_score.score} points
          </p>
        </div>
        <div
          :if={@my_answer != @correct_answer}
          class="card bg-error/10 border-2 border-error/30 shadow-xl p-6"
        >
          <.icon name="hero-x-circle-solid" class="size-12 text-error mx-auto" />
          <p class="text-3xl font-extrabold text-error mt-2">Wrong!</p>
          <p :if={@question} class="text-base-content/50 mt-1">
            Answer: {get_correct_text(@question, @correct_answer)}
          </p>
        </div>
      </div>

      <%!-- Mini leaderboard --%>
      <div class="card bg-base-200 border border-base-300">
        <div class="card-body py-3 px-4">
          <div
            :for={{player, idx} <- Enum.with_index(@scores, 1)}
            class={[
              "flex justify-between items-center py-2 border-b border-base-300 last:border-0",
              player.id == @player_id && "font-bold text-primary"
            ]}
          >
            <span class="flex items-center gap-2">
              <span :if={idx == 1}>
                <.icon name="hero-trophy-solid" class="size-4 text-warning" />
              </span>
              <span :if={idx > 1} class="text-base-content/40 text-sm w-5 text-center">{idx}</span>
              {player.name}
            </span>
            <span class="font-mono">{player.score}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp finished_phase(assigns) do
    my_rank =
      Enum.find_index(assigns.scores, fn s -> s.id == assigns.player_id end)

    my_score = Enum.find(assigns.scores, fn s -> s.id == assigns.player_id end)

    assigns =
      assigns
      |> assign(:my_rank, if(my_rank, do: my_rank + 1, else: nil))
      |> assign(:my_score, my_score)

    ~H"""
    <div class="space-y-6 text-center animate-slide-up">
      <h2 class="text-4xl font-extrabold">Game Over!</h2>

      <%!-- Personal result --%>
      <div class="animate-bounce-in">
        <div
          :if={@my_rank == 1}
          class="card bg-gradient-to-br from-warning/20 to-primary/20 border-2 border-warning/30 shadow-xl p-8"
        >
          <.icon name="hero-trophy-solid" class="size-16 text-warning mx-auto" />
          <p class="text-4xl font-extrabold text-warning mt-3">You Won!</p>
          <p :if={@my_score} class="text-2xl font-bold mt-2">
            {@my_score.score} points
          </p>
        </div>

        <div
          :if={@my_rank && @my_rank != 1}
          class="card bg-base-200 border border-base-300 shadow-xl p-8"
        >
          <p class="text-sm text-base-content/50 uppercase tracking-widest font-semibold">
            Your Rank
          </p>
          <p class="text-5xl font-extrabold text-primary mt-2">#{@my_rank}</p>
          <p :if={@my_score} class="text-lg text-base-content/60 mt-2">
            {@my_score.score} points | {@my_score.correct_answers} correct
          </p>
        </div>
      </div>

      <%!-- Full leaderboard --%>
      <div class="card bg-base-200 border border-base-300">
        <div class="card-body">
          <h3 class="card-title justify-center gap-2">
            <.icon name="hero-chart-bar" class="size-5 text-primary" /> Final Leaderboard
          </h3>
          <div
            :for={{player, idx} <- Enum.with_index(@scores, 1)}
            class={[
              "flex justify-between items-center py-3 border-b border-base-300 last:border-0",
              player.id == @player_id && "font-bold text-primary"
            ]}
          >
            <span class="flex items-center gap-2">
              <span :if={idx == 1}>
                <.icon name="hero-trophy-solid" class="size-5 text-warning" />
              </span>
              <span :if={idx == 2} class="text-base-content/60 w-6 text-center font-bold">2</span>
              <span :if={idx == 3} class="text-accent w-6 text-center font-bold">3</span>
              <span :if={idx > 3} class="text-base-content/40 w-6 text-center">{idx}</span>
              {player.name}
            </span>
            <span class="font-mono">{player.score}</span>
          </div>
        </div>
      </div>

      <div class="flex gap-4 justify-center pt-2">
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

  defp track_presence(_socket, code, player_id, name) do
    Presence.track(self(), "presence:room:#{code}", player_id, %{
      name: name,
      joined_at: System.system_time(:second)
    })

    Phoenix.PubSub.subscribe(TriviaPlatform.PubSub, "presence:room:#{code}")
  end

  defp get_correct_text(nil, _), do: ""
  defp get_correct_text(question, "a"), do: question[:option_a]
  defp get_correct_text(question, "b"), do: question[:option_b]
  defp get_correct_text(question, "c"), do: question[:option_c]
  defp get_correct_text(question, "d"), do: question[:option_d]
  defp get_correct_text(_, _), do: ""
end
