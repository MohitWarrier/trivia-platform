defmodule TriviaPlatformWeb.CreateLive do
  use TriviaPlatformWeb, :live_view

  alias TriviaPlatform.Rooms.{RoomServer, RateLimiter}
  alias TriviaPlatform.Token

  @max_questions 30

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Create Custom Game",
       host_name: "",
       questions: [],
       # Current question being edited
       form: reset_form(),
       error: nil,
       create_error: nil
     )}
  end

  @impl true
  def handle_event("update_host_name", %{"value" => name}, socket) do
    {:noreply, assign(socket, host_name: name)}
  end

  def handle_event("validate_question", params, socket) do
    {:noreply, assign(socket, form: params, error: nil)}
  end

  def handle_event("add_question", params, socket) do
    question_text = String.trim(params["question_text"] || "")
    option_a = String.trim(params["option_a"] || "")
    option_b = String.trim(params["option_b"] || "")
    option_c = String.trim(params["option_c"] || "")
    option_d = String.trim(params["option_d"] || "")
    correct = params["correct_answer"]

    cond do
      question_text == "" ->
        {:noreply, assign(socket, error: "Question text is required")}

      option_a == "" or option_b == "" or option_c == "" or option_d == "" ->
        {:noreply, assign(socket, error: "All four options are required")}

      correct not in ~w(a b c d) ->
        {:noreply, assign(socket, error: "Select the correct answer")}

      length(Enum.uniq([option_a, option_b, option_c, option_d])) < 4 ->
        {:noreply, assign(socket, error: "All four options must be different")}

      length(socket.assigns.questions) >= @max_questions ->
        {:noreply, assign(socket, error: "Maximum #{@max_questions} questions")}

      true ->
        question = %{
          question_text: question_text,
          option_a: option_a,
          option_b: option_b,
          option_c: option_c,
          option_d: option_d,
          correct_answer: correct
        }

        {:noreply,
         socket
         |> update(:questions, &(&1 ++ [question]))
         |> assign(form: reset_form(), error: nil)}
    end
  end

  def handle_event("remove_question", %{"index" => index_str}, socket) do
    case Integer.parse(index_str) do
      {index, _} when index >= 0 and index < length(socket.assigns.questions) ->
        questions = List.delete_at(socket.assigns.questions, index)
        {:noreply, assign(socket, questions: questions)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("create_game", _params, socket) do
    host_name = String.trim(socket.assigns.host_name)
    questions = socket.assigns.questions
    rate_key = socket.id || "anonymous"

    cond do
      host_name == "" ->
        {:noreply, assign(socket, create_error: "Please enter your name")}

      length(questions) < 3 ->
        {:noreply, assign(socket, create_error: "Add at least 3 questions")}

      RateLimiter.check(rate_key) == {:error, :rate_limited} ->
        {:noreply, assign(socket, create_error: "Too many rooms created. Please wait a minute.")}

      true ->
        case RoomServer.start_custom_room(host_name, questions) do
          {:ok, code, host_id} ->
            host_token = Token.sign(host_id)
            {:noreply, push_navigate(socket, to: ~p"/host/#{code}?token=#{host_token}")}

          {:error, _reason} ->
            {:noreply, assign(socket, create_error: "Failed to create room. Try again.")}
        end
    end
  end

  defp reset_form do
    %{
      "question_text" => "",
      "option_a" => "",
      "option_b" => "",
      "option_c" => "",
      "option_d" => "",
      "correct_answer" => nil
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col items-center px-4 py-8 sm:py-12">
      <%!-- Header --%>
      <div class="text-center mb-8 animate-slide-up">
        <.link navigate={~p"/"} class="btn btn-ghost btn-sm gap-1 mb-4">
          <.icon name="hero-arrow-left-mini" class="size-4" /> Back
        </.link>
        <h1 class="text-3xl sm:text-4xl font-extrabold text-base-content">
          Custom <span class="text-primary">Trivia</span>
        </h1>
        <p class="text-base-content/60 mt-2">
          Create your own questions — any topic, any difficulty
        </p>
      </div>

      <div class="w-full max-w-2xl space-y-6">
        <%!-- Host name --%>
        <div class="card bg-base-200 shadow-xl border border-base-300 animate-slide-up">
          <div class="card-body py-4">
            <label class="label"><span class="label-text font-medium">Your Name</span></label>
            <input
              type="text"
              value={@host_name}
              phx-blur="update_host_name"
              phx-keyup="update_host_name"
              name="host_name"
              placeholder="Enter your name"
              class="input input-bordered w-full focus:input-primary"
              maxlength="20"
            />
          </div>
        </div>

        <%!-- Question form --%>
        <div class="card bg-base-200 shadow-xl border border-base-300 animate-slide-up">
          <div class="card-body">
            <div class="flex items-center gap-2 mb-2">
              <.icon name="hero-plus-circle" class="size-5 text-primary" />
              <h2 class="card-title text-xl">Add Question</h2>
              <span class="badge badge-primary badge-sm">{length(@questions)} added</span>
            </div>

            <form phx-submit="add_question" phx-change="validate_question" class="space-y-3">
              <div class="form-control">
                <label class="label"><span class="label-text font-medium">Question</span></label>
                <input
                  type="text"
                  name="question_text"
                  value={@form["question_text"]}
                  placeholder="What is the capital of France?"
                  class="input input-bordered w-full focus:input-primary"
                  maxlength="200"
                />
              </div>

              <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-medium">Option A</span>
                    <input
                      type="radio"
                      name="correct_answer"
                      value="a"
                      checked={@form["correct_answer"] == "a"}
                      class="radio radio-error radio-sm"
                      title="Mark as correct"
                    />
                  </label>
                  <input
                    type="text"
                    name="option_a"
                    value={@form["option_a"]}
                    placeholder="Paris"
                    class="input input-bordered input-sm w-full"
                    maxlength="100"
                  />
                </div>
                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-medium">Option B</span>
                    <input
                      type="radio"
                      name="correct_answer"
                      value="b"
                      checked={@form["correct_answer"] == "b"}
                      class="radio radio-info radio-sm"
                      title="Mark as correct"
                    />
                  </label>
                  <input
                    type="text"
                    name="option_b"
                    value={@form["option_b"]}
                    placeholder="London"
                    class="input input-bordered input-sm w-full"
                    maxlength="100"
                  />
                </div>
                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-medium">Option C</span>
                    <input
                      type="radio"
                      name="correct_answer"
                      value="c"
                      checked={@form["correct_answer"] == "c"}
                      class="radio radio-warning radio-sm"
                      title="Mark as correct"
                    />
                  </label>
                  <input
                    type="text"
                    name="option_c"
                    value={@form["option_c"]}
                    placeholder="Berlin"
                    class="input input-bordered input-sm w-full"
                    maxlength="100"
                  />
                </div>
                <div class="form-control">
                  <label class="label">
                    <span class="label-text font-medium">Option D</span>
                    <input
                      type="radio"
                      name="correct_answer"
                      value="d"
                      checked={@form["correct_answer"] == "d"}
                      class="radio radio-success radio-sm"
                      title="Mark as correct"
                    />
                  </label>
                  <input
                    type="text"
                    name="option_d"
                    value={@form["option_d"]}
                    placeholder="Madrid"
                    class="input input-bordered input-sm w-full"
                    maxlength="100"
                  />
                </div>
              </div>

              <p class="text-xs text-base-content/40">
                Select the radio button next to the correct answer
              </p>

              <div :if={@error} role="alert" class="alert alert-error alert-sm">
                <.icon name="hero-exclamation-circle-mini" class="size-5" />
                <span>{@error}</span>
              </div>

              <button type="submit" class="btn btn-outline btn-primary w-full gap-2">
                <.icon name="hero-plus-mini" class="size-5" /> Add Question
              </button>
            </form>
          </div>
        </div>

        <%!-- Question list --%>
        <div
          :if={@questions != []}
          class="card bg-base-200 shadow-xl border border-base-300 animate-slide-up"
        >
          <div class="card-body">
            <div class="flex items-center gap-2 mb-2">
              <.icon name="hero-list-bullet" class="size-5 text-primary" />
              <h2 class="card-title text-xl">Your Questions ({length(@questions)})</h2>
            </div>

            <div class="space-y-2">
              <div
                :for={{q, idx} <- Enum.with_index(@questions)}
                class="flex items-start gap-3 p-3 rounded-lg bg-base-300/50 border border-base-300"
              >
                <span class="badge badge-primary badge-sm mt-1 shrink-0">{idx + 1}</span>
                <div class="flex-1 min-w-0">
                  <p class="font-medium text-sm truncate">{q.question_text}</p>
                  <div class="flex flex-wrap gap-1 mt-1">
                    <span class={[
                      "badge badge-xs",
                      q.correct_answer == "a" && "badge-success",
                      q.correct_answer != "a" && "badge-ghost"
                    ]}>
                      A: {q.option_a}
                    </span>
                    <span class={[
                      "badge badge-xs",
                      q.correct_answer == "b" && "badge-success",
                      q.correct_answer != "b" && "badge-ghost"
                    ]}>
                      B: {q.option_b}
                    </span>
                    <span class={[
                      "badge badge-xs",
                      q.correct_answer == "c" && "badge-success",
                      q.correct_answer != "c" && "badge-ghost"
                    ]}>
                      C: {q.option_c}
                    </span>
                    <span class={[
                      "badge badge-xs",
                      q.correct_answer == "d" && "badge-success",
                      q.correct_answer != "d" && "badge-ghost"
                    ]}>
                      D: {q.option_d}
                    </span>
                  </div>
                </div>
                <button
                  phx-click="remove_question"
                  phx-value-index={idx}
                  class="btn btn-ghost btn-xs text-error shrink-0"
                  title="Remove"
                >
                  <.icon name="hero-trash-mini" class="size-4" />
                </button>
              </div>
            </div>
          </div>
        </div>

        <%!-- Create game button --%>
        <div class="text-center space-y-3">
          <div :if={@create_error} role="alert" class="alert alert-error alert-sm">
            <.icon name="hero-exclamation-circle-mini" class="size-5" />
            <span>{@create_error}</span>
          </div>

          <div :if={length(@questions) < 3} class="text-base-content/40 text-sm">
            Add at least 3 questions to create a game
          </div>

          <button
            phx-click="create_game"
            class={[
              "btn btn-lg gap-2 px-10",
              length(@questions) >= 3 && "btn-primary animate-pulse-glow",
              length(@questions) < 3 && "btn-disabled"
            ]}
            disabled={length(@questions) < 3}
          >
            <.icon name="hero-rocket-launch-mini" class="size-5" />
            Create Game ({length(@questions)} questions)
          </button>
        </div>
      </div>
    </div>
    """
  end
end
