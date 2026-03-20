defmodule TriviaPlatform.Rooms.RoomServerCustomTest do
  use TriviaPlatform.DataCase, async: false

  alias TriviaPlatform.Rooms.RoomServer

  @custom_questions [
    %{
      question_text: "What color is the sky?",
      option_a: "Blue",
      option_b: "Green",
      option_c: "Red",
      option_d: "Yellow",
      correct_answer: "a"
    },
    %{
      question_text: "What is 2 + 2?",
      option_a: "3",
      option_b: "4",
      option_c: "5",
      option_d: "6",
      correct_answer: "b"
    },
    %{
      question_text: "Which planet is closest to the Sun?",
      option_a: "Earth",
      option_b: "Venus",
      option_c: "Mercury",
      option_d: "Mars",
      correct_answer: "c"
    }
  ]

  describe "start_custom_room/2" do
    test "creates a room with custom questions" do
      {:ok, code, host_id} = RoomServer.start_custom_room("Host", @custom_questions)

      assert is_binary(code)
      assert String.length(code) == 6
      assert is_binary(host_id)

      state = RoomServer.get_state(code)
      assert state.category == "custom"
      assert state.total_questions == 3
    end

    test "rejects fewer than 3 questions" do
      two_questions = Enum.take(@custom_questions, 2)

      assert_raise FunctionClauseError, fn ->
        RoomServer.start_custom_room("Host", two_questions)
      end
    end

    test "sanitizes host name" do
      {:ok, code, _host_id} =
        RoomServer.start_custom_room("  LongNameThatExceeds20Characters  ", @custom_questions)

      state = RoomServer.get_state(code)
      assert state.host_name == "LongNameThatExceeds2"
    end
  end

  describe "custom game flow" do
    setup do
      {:ok, code, host_id} = RoomServer.start_custom_room("Host", @custom_questions)
      {:ok, player_id} = RoomServer.join(code, "Alice")
      %{code: code, host_id: host_id, player_id: player_id}
    end

    test "can start game with custom questions", %{code: code, host_id: host_id} do
      assert :ok = RoomServer.start_game(code, host_id)
      state = RoomServer.get_state(code)
      assert state.phase == :question
    end

    test "plays through all custom questions", %{
      code: code,
      host_id: host_id,
      player_id: player_id
    } do
      Phoenix.PubSub.subscribe(TriviaPlatform.PubSub, "room:#{code}")

      :ok = RoomServer.start_game(code, host_id)
      assert_receive {:question_started, %{question_text: "What color is the sky?"}}, 1_000

      # Answer first question correctly
      RoomServer.submit_answer(code, player_id, "a")
      assert_receive {:results, %{correct_answer: "a"}}, 2_000

      # Wait for next question
      assert_receive {:question_started, %{question_text: "What is 2 + 2?"}}, 5_000

      # Answer second question correctly
      RoomServer.submit_answer(code, player_id, "b")
      assert_receive {:results, %{correct_answer: "b"}}, 2_000

      # Wait for last question
      assert_receive {:question_started, %{question_text: text}}, 5_000
      assert text == "Which planet is closest to the Sun?"

      # Answer third question
      RoomServer.submit_answer(code, player_id, "c")
      assert_receive {:results, %{correct_answer: "c"}}, 2_000

      # Game should finish
      assert_receive {:game_finished, %{final_scores: scores}}, 5_000
      assert [%{name: "Alice", score: score}] = scores
      assert score > 0
    end

    test "custom game saves to database with category 'custom'", %{
      code: code,
      host_id: host_id,
      player_id: player_id
    } do
      Phoenix.PubSub.subscribe(TriviaPlatform.PubSub, "room:#{code}")

      :ok = RoomServer.start_game(code, host_id)

      for _ <- 1..3 do
        assert_receive {:question_started, _}, 5_000
        RoomServer.submit_answer(code, player_id, "a")
        assert_receive {:results, _}, 2_000
      end

      assert_receive {:game_finished, _}, 5_000
      assert_receive {:game_saved, %{game_id: game_id}}, 5_000

      game = TriviaPlatform.Games.get_game_with_results(game_id)
      assert game.category == "custom"
      assert game.question_count == 3
      assert length(game.results) == 1
    end
  end
end
