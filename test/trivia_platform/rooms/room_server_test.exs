defmodule TriviaPlatform.Rooms.RoomServerTest do
  use TriviaPlatform.DataCase, async: false

  alias TriviaPlatform.Rooms.{RoomServer, RoomRegistry}

  setup do
    # Seed some questions so games can start
    for i <- 1..10 do
      Repo.insert!(%TriviaPlatform.Questions.Question{
        category: "science",
        question_text: "Test question #{i}?",
        option_a: "A#{i}",
        option_b: "B#{i}",
        option_c: "C#{i}",
        option_d: "D#{i}",
        correct_answer: "a",
        difficulty: "medium"
      })
    end

    :ok
  end

  describe "start_room/3" do
    test "creates a room and returns code + host_id" do
      assert {:ok, code, host_id} = RoomServer.start_room("Host", "science", 5)
      assert is_binary(code)
      assert String.length(code) == 6
      assert is_binary(host_id)
    end

    test "room is registered in ETS" do
      {:ok, code, _host_id} = RoomServer.start_room("Host", "science", 5)
      assert {:ok, pid} = RoomRegistry.lookup(code)
      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "room starts in :waiting phase" do
      {:ok, code, _host_id} = RoomServer.start_room("Host", "science", 5)
      state = RoomServer.get_state(code)
      assert state.phase == :waiting
      assert state.players == []
      assert state.host_name == "Host"
      assert state.category == "science"
    end
  end

  describe "join/2" do
    setup do
      {:ok, code, host_id} = RoomServer.start_room("Host", "science", 5)
      %{code: code, host_id: host_id}
    end

    test "player can join a waiting room", %{code: code} do
      assert {:ok, player_id} = RoomServer.join(code, "Alice")
      assert is_binary(player_id)

      state = RoomServer.get_state(code)
      assert length(state.players) == 1
      assert hd(state.players).name == "Alice"
    end

    test "multiple players can join", %{code: code} do
      {:ok, _} = RoomServer.join(code, "Alice")
      {:ok, _} = RoomServer.join(code, "Bob")
      {:ok, _} = RoomServer.join(code, "Charlie")

      state = RoomServer.get_state(code)
      assert length(state.players) == 3
      names = Enum.map(state.players, & &1.name) |> Enum.sort()
      assert names == ["Alice", "Bob", "Charlie"]
    end

    test "joining broadcasts player_joined via PubSub", %{code: code} do
      Phoenix.PubSub.subscribe(TriviaPlatform.PubSub, "room:#{code}")
      {:ok, player_id} = RoomServer.join(code, "Alice")

      assert_receive {:player_joined, %{player_id: ^player_id, name: "Alice"}}
    end

    test "cannot join a non-existent room" do
      assert {:error, :not_found} = RoomServer.join("ZZZZZZ", "Alice")
    end

    test "cannot join a game in progress", %{code: code, host_id: host_id} do
      {:ok, _} = RoomServer.join(code, "Alice")
      :ok = RoomServer.start_game(code, host_id)

      assert {:error, :game_in_progress} = RoomServer.join(code, "Bob")
    end
  end

  describe "start_game/2" do
    setup do
      {:ok, code, host_id} = RoomServer.start_room("Host", "science", 3)
      {:ok, player_id} = RoomServer.join(code, "Alice")
      %{code: code, host_id: host_id, player_id: player_id}
    end

    test "starts the game and transitions to :question phase", %{code: code, host_id: host_id} do
      assert :ok = RoomServer.start_game(code, host_id)

      state = RoomServer.get_state(code)
      assert state.phase == :question
      assert state.total_questions == 3
    end

    test "broadcasts question_started", %{code: code, host_id: host_id} do
      Phoenix.PubSub.subscribe(TriviaPlatform.PubSub, "room:#{code}")
      :ok = RoomServer.start_game(code, host_id)

      assert_receive {:question_started, data}
      assert data.question_index == 0
      assert data.total_questions == 3
      assert data.timer == 15
      assert is_binary(data.question_text)
    end

    test "non-host cannot start game", %{code: code} do
      assert {:error, :unauthorized} = RoomServer.start_game(code, "fake-host-id")
    end

    test "cannot start game on non-existent room" do
      assert {:error, :not_found} = RoomServer.start_game("ZZZZZZ", "any-id")
    end
  end

  describe "submit_answer/3" do
    setup do
      {:ok, code, host_id} = RoomServer.start_room("Host", "science", 3)
      {:ok, player_id} = RoomServer.join(code, "Alice")
      Phoenix.PubSub.subscribe(TriviaPlatform.PubSub, "room:#{code}")
      :ok = RoomServer.start_game(code, host_id)
      # Consume the question_started message
      assert_receive {:question_started, _}
      %{code: code, host_id: host_id, player_id: player_id}
    end

    test "player can submit an answer", %{code: code, player_id: player_id} do
      RoomServer.submit_answer(code, player_id, "a")

      assert_receive {:answer_received, %{answered_count: 1, total: 1}}
    end

    test "submitting when all players answered triggers results", %{
      code: code,
      player_id: player_id
    } do
      RoomServer.submit_answer(code, player_id, "a")

      # Since there's only 1 player, this triggers results immediately
      assert_receive {:results, data}
      assert is_binary(data.correct_answer)
      assert is_list(data.scores)
    end

    test "duplicate answer from same player is ignored", %{
      code: code,
      player_id: player_id
    } do
      RoomServer.submit_answer(code, player_id, "a")
      RoomServer.submit_answer(code, player_id, "b")

      # Should only get one answer_received
      assert_receive {:answer_received, %{answered_count: 1, total: 1}}
      refute_receive {:answer_received, _}, 100
    end

    test "correct answer awards points based on time remaining", %{
      code: code,
      player_id: player_id
    } do
      # Answer immediately (time_remaining should be 15)
      RoomServer.submit_answer(code, player_id, "a")

      assert_receive {:results, data}

      if data.correct_answer == "a" do
        player = Enum.find(data.scores, &(&1.id == player_id))
        assert player.score > 0
        assert player.correct_answers == 1
      end
    end
  end

  describe "timer" do
    setup do
      {:ok, code, host_id} = RoomServer.start_room("Host", "science", 3)
      {:ok, _player_id} = RoomServer.join(code, "Alice")
      Phoenix.PubSub.subscribe(TriviaPlatform.PubSub, "room:#{code}")
      :ok = RoomServer.start_game(code, host_id)
      assert_receive {:question_started, _}
      %{code: code, host_id: host_id}
    end

    test "broadcasts timer_tick every second", %{code: _code} do
      assert_receive {:timer_tick, %{seconds: 14}}, 2_000
    end
  end

  describe "leave/2" do
    setup do
      {:ok, code, host_id} = RoomServer.start_room("Host", "science", 3)
      {:ok, player_id} = RoomServer.join(code, "Alice")
      %{code: code, host_id: host_id, player_id: player_id}
    end

    test "player can leave the room", %{code: code, player_id: player_id} do
      Phoenix.PubSub.subscribe(TriviaPlatform.PubSub, "room:#{code}")
      RoomServer.leave(code, player_id)

      assert_receive {:player_left, %{player_id: ^player_id}}

      state = RoomServer.get_state(code)
      assert state.players == []
    end
  end

  describe "get_state/1" do
    test "returns sanitized state" do
      {:ok, code, _host_id} = RoomServer.start_room("Host", "science", 5)
      state = RoomServer.get_state(code)

      assert state.room_code == code
      assert state.phase == :waiting
      assert state.host_name == "Host"
      assert state.category == "science"
      assert is_list(state.players)
      assert is_integer(state.timer_seconds)
      assert is_integer(state.player_count)
      assert is_integer(state.answered_count)
    end

    test "returns error for non-existent room" do
      assert {:error, :not_found} = RoomServer.get_state("ZZZZZZ")
    end
  end

  describe "full game flow" do
    test "complete game with multiple players scores and finishes" do
      {:ok, code, host_id} = RoomServer.start_room("Host", "science", 3)
      {:ok, alice_id} = RoomServer.join(code, "Alice")
      {:ok, bob_id} = RoomServer.join(code, "Bob")

      Phoenix.PubSub.subscribe(TriviaPlatform.PubSub, "room:#{code}")

      # Start game
      :ok = RoomServer.start_game(code, host_id)
      assert_receive {:question_started, q1}
      assert q1.question_index == 0

      # Both players answer question 1
      RoomServer.submit_answer(code, alice_id, q1[:option_a] && "a")
      RoomServer.submit_answer(code, bob_id, "b")

      assert_receive {:results, r1}
      assert r1.question_index == 0
      assert length(r1.scores) == 2

      # Wait for next question
      assert_receive {:question_started, q2}, 5_000
      assert q2.question_index == 1

      # Both answer question 2
      RoomServer.submit_answer(code, alice_id, "c")
      RoomServer.submit_answer(code, bob_id, "a")

      assert_receive {:results, r2}
      assert r2.question_index == 1

      # Wait for question 3
      assert_receive {:question_started, q3}, 5_000
      assert q3.question_index == 2

      # Both answer question 3
      RoomServer.submit_answer(code, alice_id, "a")
      RoomServer.submit_answer(code, bob_id, "d")

      assert_receive {:results, _r3}

      # Game should finish
      assert_receive {:game_finished, %{final_scores: scores}}, 5_000
      assert length(scores) == 2

      # Game should be saved to DB
      assert_receive {:game_saved, %{game_id: game_id}}, 5_000
      assert is_integer(game_id)

      # Verify DB persistence
      game = TriviaPlatform.Games.get_game_with_results(game_id)
      assert game.room_code == code
      assert game.host_name == "Host"
      assert game.category == "science"
      assert length(game.results) == 2
    end
  end
end
