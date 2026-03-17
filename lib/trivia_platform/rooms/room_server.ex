defmodule TriviaPlatform.Rooms.RoomServer do
  use GenServer, restart: :transient
  require Logger

  alias TriviaPlatform.Rooms.{RoomRegistry, RoomCode}
  alias TriviaPlatform.Questions
  alias TriviaPlatform.Games

  @tick_interval 1_000
  @results_pause 4_000
  @shutdown_delay 60_000
  @question_time 15

  defstruct [
    :room_code,
    :host_id,
    :category,
    :question_count,
    :host_name,
    :started_at,
    :timer_ref,
    phase: :waiting,
    players: %{},
    disconnected_players: %{},
    questions: [],
    current_question_index: 0,
    current_answers: %{},
    timer_seconds: @question_time
  ]

  # ── Client API ──

  def start_room(host_name, category, question_count \\ 10) do
    host_name = host_name |> String.trim() |> String.slice(0, 20)
    question_count = max(3, min(20, question_count))

    with {:ok, code} <- RoomCode.generate() do
      host_id = generate_id()

      case DynamicSupervisor.start_child(
             TriviaPlatform.Rooms.RoomSupervisor,
             {__MODULE__, {code, host_id, host_name, category, question_count}}
           ) do
        {:ok, _pid} -> {:ok, code, host_id}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def start_custom_room(host_name, questions) when is_list(questions) and length(questions) >= 3 do
    host_name = host_name |> String.trim() |> String.slice(0, 20)

    with {:ok, code} <- RoomCode.generate() do
      host_id = generate_id()

      case DynamicSupervisor.start_child(
             TriviaPlatform.Rooms.RoomSupervisor,
             {__MODULE__, {code, host_id, host_name, :custom, questions}}
           ) do
        {:ok, _pid} -> {:ok, code, host_id}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def start_link({code, host_id, host_name, category, question_count_or_questions}) do
    GenServer.start_link(__MODULE__, {code, host_id, host_name, category, question_count_or_questions})
  end

  def join(room_code, player_name) do
    player_name = player_name |> String.trim() |> String.slice(0, 20)

    with {:ok, pid} <- RoomRegistry.lookup(room_code) do
      GenServer.call(pid, {:join, player_name})
    end
  end

  def rejoin(room_code, player_id) do
    with {:ok, pid} <- RoomRegistry.lookup(room_code) do
      GenServer.call(pid, {:rejoin, player_id})
    end
  end

  def get_state(room_code) do
    with {:ok, pid} <- RoomRegistry.lookup(room_code) do
      GenServer.call(pid, :get_state)
    end
  end

  def start_game(room_code, host_id) do
    with {:ok, pid} <- RoomRegistry.lookup(room_code) do
      GenServer.call(pid, {:start_game, host_id})
    end
  end

  def submit_answer(room_code, player_id, answer) when answer in ~w(a b c d) do
    with {:ok, pid} <- RoomRegistry.lookup(room_code) do
      GenServer.cast(pid, {:submit_answer, player_id, answer})
    end
  end

  def submit_answer(_room_code, _player_id, _answer), do: :ok

  def leave(room_code, player_id) do
    with {:ok, pid} <- RoomRegistry.lookup(room_code) do
      GenServer.cast(pid, {:leave, player_id})
    end
  end

  def mark_disconnected(room_code, player_id) do
    with {:ok, pid} <- RoomRegistry.lookup(room_code) do
      GenServer.cast(pid, {:mark_disconnected, player_id})
    end
  end

  # ── Server Callbacks ──

  @impl true
  def init({code, host_id, host_name, :custom, questions}) when is_list(questions) do
    RoomRegistry.register(code, self())

    state = %__MODULE__{
      room_code: code,
      host_id: host_id,
      host_name: host_name,
      category: "custom",
      question_count: length(questions),
      questions: questions
    }

    {:ok, state}
  end

  def init({code, host_id, host_name, category, question_count}) do
    RoomRegistry.register(code, self())

    state = %__MODULE__{
      room_code: code,
      host_id: host_id,
      host_name: host_name,
      category: category,
      question_count: question_count
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:join, player_name}, _from, %{phase: :waiting} = state) do
    player_id = generate_id()

    player = %{
      name: player_name,
      score: 0,
      correct_answers: 0,
      current_answer: nil,
      connected: true
    }

    new_state = put_in(state.players[player_id], player)
    broadcast(state.room_code, {:player_joined, %{player_id: player_id, name: player_name}})
    {:reply, {:ok, player_id}, new_state}
  end

  def handle_call({:join, _player_name}, _from, state) do
    {:reply, {:error, :game_in_progress}, state}
  end

  # Rejoin: allow a disconnected player to reconnect mid-game
  def handle_call({:rejoin, player_id}, _from, state) do
    cond do
      # Player is still in the active players list (tab refresh, not full disconnect)
      Map.has_key?(state.players, player_id) ->
        new_state = put_in(state.players[player_id][:connected], true)
        broadcast(state.room_code, {:player_rejoined, %{player_id: player_id}})
        {:reply, {:ok, state.players[player_id].name}, new_state}

      # Player was moved to disconnected list
      Map.has_key?(state.disconnected_players, player_id) ->
        player = state.disconnected_players[player_id] |> Map.put(:connected, true)

        new_state =
          state
          |> Map.update!(:players, &Map.put(&1, player_id, player))
          |> Map.update!(:disconnected_players, &Map.delete(&1, player_id))

        broadcast(state.room_code, {:player_rejoined, %{player_id: player_id}})
        {:reply, {:ok, player.name}, new_state}

      true ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:get_state, _from, state) do
    {:reply, sanitize_state(state), state}
  end

  def handle_call({:start_game, host_id}, _from, %{phase: :waiting, host_id: host_id} = state) do
    connected_count = state.players |> Enum.count(fn {_id, p} -> p.connected end)

    if connected_count == 0 do
      {:reply, {:error, :no_players}, state}
    else
      # Custom rooms already have questions loaded from init
      questions =
        if state.questions != [] do
          state.questions
        else
          Questions.get_random_questions(state.category, state.question_count)
        end

      cond do
        Enum.empty?(questions) ->
          {:reply, {:error, :no_questions}, state}

        length(questions) < 3 ->
          {:reply, {:error, :insufficient_questions}, state}

        true ->
          new_state =
            %{state | questions: questions, started_at: DateTime.utc_now(), phase: :question}
            |> reset_for_question()
            |> start_timer()

          broadcast_question(new_state)
          {:reply, :ok, new_state}
      end
    end
  end

  def handle_call({:start_game, _host_id}, _from, state) do
    {:reply, {:error, :unauthorized}, state}
  end

  @impl true
  def handle_cast({:submit_answer, player_id, answer}, %{phase: :question} = state) do
    if Map.has_key?(state.players, player_id) && !Map.has_key?(state.current_answers, player_id) do
      new_answers =
        Map.put(state.current_answers, player_id, %{
          answer: answer,
          time_remaining: state.timer_seconds
        })

      new_state = %{state | current_answers: new_answers}

      # Count connected players for "all answered" check
      connected_count = state.players |> Enum.count(fn {_id, p} -> p.connected end)

      broadcast(
        state.room_code,
        {:answer_received,
         %{
           answered_count: map_size(new_answers),
           total: connected_count
         }}
      )

      # If all connected players answered, skip timer
      if map_size(new_answers) >= connected_count do
        cancel_timer(new_state)
        new_state = transition_to_results(new_state)
        {:noreply, new_state}
      else
        {:noreply, new_state}
      end
    else
      {:noreply, state}
    end
  end

  def handle_cast({:submit_answer, _player_id, _answer}, state) do
    {:noreply, state}
  end

  def handle_cast({:mark_disconnected, player_id}, state) do
    if Map.has_key?(state.players, player_id) do
      if state.phase == :waiting do
        # In waiting phase, just remove the player
        new_players = Map.delete(state.players, player_id)
        new_state = %{state | players: new_players}
        broadcast(state.room_code, {:player_left, %{player_id: player_id}})
        {:noreply, new_state}
      else
        # During game, move to disconnected list (allows rejoin)
        player = state.players[player_id] |> Map.put(:connected, false)

        new_state =
          state
          |> Map.update!(:players, &Map.delete(&1, player_id))
          |> Map.update!(:disconnected_players, &Map.put(&1, player_id, player))

        broadcast(state.room_code, {:player_disconnected, %{player_id: player_id}})

        # Check if all remaining connected players have answered
        new_state = maybe_advance_on_disconnect(new_state)
        {:noreply, new_state}
      end
    else
      {:noreply, state}
    end
  end

  def handle_cast({:leave, player_id}, state) do
    new_players = Map.delete(state.players, player_id)
    new_answers = Map.delete(state.current_answers, player_id)
    new_state = %{state | players: new_players, current_answers: new_answers}

    broadcast(state.room_code, {:player_left, %{player_id: player_id}})

    if map_size(new_players) == 0 && state.phase != :waiting do
      {:stop, :normal, new_state}
    else
      {:noreply, new_state}
    end
  end

  @impl true
  def handle_info(:tick, %{phase: :question} = state) do
    new_seconds = state.timer_seconds - 1

    if new_seconds <= 0 do
      new_state = transition_to_results(%{state | timer_seconds: 0})
      {:noreply, new_state}
    else
      new_state = %{state | timer_seconds: new_seconds} |> start_timer()
      broadcast(state.room_code, {:timer_tick, %{seconds: new_seconds}})
      {:noreply, new_state}
    end
  end

  def handle_info(:show_next_question, state) do
    next_index = state.current_question_index + 1

    if next_index >= length(state.questions) do
      new_state = transition_to_finished(state)
      {:noreply, new_state}
    else
      new_state =
        %{state | current_question_index: next_index, phase: :question}
        |> reset_for_question()
        |> start_timer()

      broadcast_question(new_state)
      {:noreply, new_state}
    end
  end

  def handle_info(:shutdown, state) do
    {:stop, :normal, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    RoomRegistry.unregister(state.room_code)
    :ok
  end

  # ── Private Helpers ──

  defp maybe_advance_on_disconnect(%{phase: :question} = state) do
    connected_count = state.players |> Enum.count(fn {_id, p} -> p.connected end)

    if connected_count == 0 do
      # No connected players, but don't crash — they might reconnect
      state
    else
      if map_size(state.current_answers) >= connected_count do
        cancel_timer(state)
        transition_to_results(state)
      else
        state
      end
    end
  end

  defp maybe_advance_on_disconnect(state), do: state

  defp transition_to_results(state) do
    question = Enum.at(state.questions, state.current_question_index)
    correct = question.correct_answer

    # Calculate scores for all players (including disconnected ones who answered)
    all_answers = state.current_answers

    # Merge active + disconnected for scoring
    all_players =
      Map.merge(state.players, state.disconnected_players)

    updated_players =
      Enum.reduce(all_answers, all_players, fn {player_id, answer_data}, players ->
        if Map.has_key?(players, player_id) && answer_data.answer == correct do
          points = max(answer_data.time_remaining * 100, 100)

          players
          |> update_in([player_id, :score], &(&1 + points))
          |> update_in([player_id, :correct_answers], &(&1 + 1))
        else
          players
        end
      end)

    # Split back into active and disconnected
    active_ids = Map.keys(state.players)

    active_players =
      updated_players |> Enum.filter(fn {id, _} -> id in active_ids end) |> Map.new()

    disconnected =
      updated_players |> Enum.reject(fn {id, _} -> id in active_ids end) |> Map.new()

    new_state = %{
      state
      | players: active_players,
        disconnected_players: disconnected,
        phase: :results
    }

    broadcast(
      state.room_code,
      {:results,
       %{
         correct_answer: correct,
         question_text: question.question_text,
         scores: format_scores(Map.merge(active_players, disconnected)),
         question_index: state.current_question_index,
         total_questions: length(state.questions)
       }}
    )

    # Schedule next question or finish
    Process.send_after(self(), :show_next_question, @results_pause)

    new_state
  end

  defp transition_to_finished(state) do
    all_players = Map.merge(state.players, state.disconnected_players)
    new_state = %{state | phase: :finished}
    scores = format_scores(all_players)

    # Save to database under supervision
    Task.Supervisor.start_child(TriviaPlatform.TaskSupervisor, fn ->
      save_game_to_db(state, all_players)
    end)

    broadcast(state.room_code, {:game_finished, %{final_scores: scores}})

    # Auto-cleanup after delay
    Process.send_after(self(), :shutdown, @shutdown_delay)

    new_state
  end

  defp save_game_to_db(state, all_players) do
    ended_at = DateTime.utc_now() |> DateTime.truncate(:second)
    started_at = state.started_at |> DateTime.truncate(:second)

    case Games.save_game(%{
           room_code: state.room_code,
           host_name: state.host_name,
           category: state.category,
           question_count: length(state.questions),
           player_count: map_size(all_players),
           started_at: started_at,
           ended_at: ended_at
         }) do
      {:ok, game} ->
        ranked_players =
          all_players
          |> Enum.sort_by(fn {_id, p} -> p.score end, :desc)
          |> Enum.with_index(1)
          |> Enum.map(fn {{_id, player}, rank} ->
            %{
              player_name: player.name,
              final_score: player.score,
              correct_answers: player.correct_answers,
              rank: rank
            }
          end)

        Games.save_game_results(game, ranked_players)
        broadcast(state.room_code, {:game_saved, %{game_id: game.id}})

      {:error, changeset} ->
        Logger.error(
          "Failed to save game for room #{state.room_code}: #{inspect(changeset.errors)}"
        )
    end
  end

  defp reset_for_question(state) do
    %{state | current_answers: %{}, timer_seconds: @question_time}
  end

  defp start_timer(state) do
    ref = Process.send_after(self(), :tick, @tick_interval)
    %{state | timer_ref: ref}
  end

  defp cancel_timer(%{timer_ref: nil}), do: :ok
  defp cancel_timer(%{timer_ref: ref}), do: Process.cancel_timer(ref)

  defp broadcast(room_code, message) do
    Phoenix.PubSub.broadcast(TriviaPlatform.PubSub, "room:#{room_code}", message)
  end

  defp broadcast_question(state) do
    question = Enum.at(state.questions, state.current_question_index)

    broadcast(
      state.room_code,
      {:question_started,
       %{
         question_text: question.question_text,
         option_a: question.option_a,
         option_b: question.option_b,
         option_c: question.option_c,
         option_d: question.option_d,
         question_index: state.current_question_index,
         total_questions: length(state.questions),
         timer: @question_time
       }}
    )
  end

  defp sanitize_state(state) do
    all_players = Map.merge(state.players, state.disconnected_players)

    %{
      room_code: state.room_code,
      host_id: state.host_id,
      host_name: state.host_name,
      phase: state.phase,
      category: state.category,
      players: format_scores(all_players),
      timer_seconds: state.timer_seconds,
      current_question_index: state.current_question_index,
      total_questions: length(state.questions),
      answered_count: map_size(state.current_answers),
      player_count: map_size(all_players)
    }
  end

  defp format_scores(players) do
    players
    |> Enum.map(fn {id, player} ->
      %{
        id: id,
        name: player.name,
        score: player.score,
        correct_answers: player.correct_answers,
        connected: Map.get(player, :connected, true)
      }
    end)
    |> Enum.sort_by(& &1.score, :desc)
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end
