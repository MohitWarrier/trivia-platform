defmodule TriviaPlatformWeb.HomeLive do
  use TriviaPlatformWeb, :live_view

  alias TriviaPlatform.Questions
  alias TriviaPlatform.Token
  alias TriviaPlatform.Rooms.{RoomServer, RoomRegistry, RateLimiter}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Trivia Platform",
       categories: Questions.list_categories(),
       create_form:
         to_form(%{"host_name" => "", "category" => "science", "question_count" => "10"}),
       join_form: to_form(%{"player_name" => "", "room_code" => ""}),
       create_error: nil,
       join_error: nil
     )}
  end

  @impl true
  def handle_event(
        "create_game",
        %{"host_name" => host_name, "category" => category, "question_count" => count_str},
        socket
      ) do
    host_name = String.trim(host_name)
    count = String.to_integer(count_str)

    # Use socket id as rate limit key (unique per WebSocket connection)
    rate_key = socket.id || "anonymous"

    cond do
      host_name == "" ->
        {:noreply, assign(socket, create_error: "Please enter your name")}

      count < 3 or count > 20 ->
        {:noreply, assign(socket, create_error: "Question count must be between 3 and 20")}

      category not in Questions.list_categories() ->
        {:noreply, assign(socket, create_error: "Invalid category")}

      RateLimiter.check(rate_key) == {:error, :rate_limited} ->
        {:noreply, assign(socket, create_error: "Too many rooms created. Please wait a minute.")}

      true ->
        case RoomServer.start_room(host_name, category, count) do
          {:ok, code, host_id} ->
            host_token = Token.sign(host_id)

            {:noreply,
             socket
             |> put_session(:host_id, host_id)
             |> push_navigate(to: ~p"/host/#{code}?token=#{host_token}")}

          {:error, _reason} ->
            {:noreply, assign(socket, create_error: "Failed to create room. Try again.")}
        end
    end
  end

  def handle_event("join_game", %{"player_name" => player_name, "room_code" => room_code}, socket) do
    player_name = String.trim(player_name)
    room_code = room_code |> String.trim() |> String.upcase()

    cond do
      player_name == "" ->
        {:noreply, assign(socket, join_error: "Please enter your name")}

      room_code == "" ->
        {:noreply, assign(socket, join_error: "Please enter a room code")}

      true ->
        case RoomRegistry.lookup(room_code) do
          {:ok, _pid} ->
            {:noreply, push_navigate(socket, to: ~p"/play/#{room_code}?name=#{player_name}")}

          {:error, :not_found} ->
            {:noreply,
             assign(socket, join_error: "Room not found. Check the code and try again.")}
        end
    end
  end

  def handle_event("validate_create", params, socket) do
    {:noreply, assign(socket, create_form: to_form(params), create_error: nil)}
  end

  def handle_event("validate_join", params, socket) do
    {:noreply, assign(socket, join_form: to_form(params), join_error: nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center px-4 py-16 sm:py-24">
      <%!-- Hero --%>
      <div class="text-center mb-12 animate-slide-up">
        <div class="inline-flex items-center justify-center w-20 h-20 rounded-full bg-primary/10 mb-6">
          <.icon name="hero-puzzle-piece-solid" class="size-10 text-primary" />
        </div>
        <h1 class="text-5xl sm:text-6xl font-extrabold text-base-content tracking-tight">
          Trivia <span class="text-primary">Platform</span>
        </h1>
        <p class="text-lg text-base-content/60 mt-3 max-w-md mx-auto">
          Real-time multiplayer trivia. No sign-up needed. Just create or join!
        </p>
      </div>

      <div class="flex flex-col md:flex-row gap-6 w-full max-w-3xl">
        <%!-- Create Game Card --%>
        <div class="card bg-base-200 shadow-xl flex-1 border border-base-300 animate-slide-up">
          <div class="card-body">
            <div class="flex items-center gap-3 mb-2">
              <div class="w-10 h-10 rounded-lg bg-primary/10 flex items-center justify-center">
                <.icon name="hero-plus-circle" class="size-6 text-primary" />
              </div>
              <h2 class="card-title text-2xl">Host a Game</h2>
            </div>

            <.form
              for={@create_form}
              phx-submit="create_game"
              phx-change="validate_create"
              class="space-y-4 mt-2"
            >
              <div class="form-control">
                <label class="label"><span class="label-text font-medium">Your Name</span></label>
                <input
                  type="text"
                  name="host_name"
                  value={@create_form["host_name"].value}
                  placeholder="Enter your name"
                  class="input input-bordered w-full focus:input-primary"
                  maxlength="20"
                  required
                />
              </div>

              <div class="form-control">
                <label class="label"><span class="label-text font-medium">Category</span></label>
                <select name="category" class="select select-bordered w-full focus:select-primary">
                  <%= for cat <- @categories do %>
                    <option value={cat} selected={@create_form["category"].value == cat}>
                      {category_display(cat)}
                    </option>
                  <% end %>
                </select>
              </div>

              <div class="form-control">
                <label class="label">
                  <span class="label-text font-medium">Questions</span>
                  <span class="label-text-alt text-base-content/50">3 - 20</span>
                </label>
                <input
                  type="range"
                  name="question_count"
                  value={@create_form["question_count"].value}
                  min="3"
                  max="20"
                  class="range range-primary range-sm"
                />
                <div class="text-center text-sm font-semibold text-primary mt-1">
                  {@create_form["question_count"].value} questions
                </div>
              </div>

              <div :if={@create_error} role="alert" class="alert alert-error alert-sm">
                <.icon name="hero-exclamation-circle-mini" class="size-5" />
                <span>{@create_error}</span>
              </div>

              <button type="submit" class="btn btn-primary w-full mt-2 gap-2">
                <.icon name="hero-rocket-launch-mini" class="size-5" /> Create Game
              </button>
            </.form>
          </div>
        </div>

        <%!-- Divider --%>
        <div class="divider md:divider-horizontal text-base-content/30 font-semibold">OR</div>

        <%!-- Join Game Card --%>
        <div class="card bg-base-200 shadow-xl flex-1 border border-base-300 animate-slide-up">
          <div class="card-body">
            <div class="flex items-center gap-3 mb-2">
              <div class="w-10 h-10 rounded-lg bg-secondary/10 flex items-center justify-center">
                <.icon name="hero-user-group" class="size-6 text-secondary" />
              </div>
              <h2 class="card-title text-2xl">Join a Game</h2>
            </div>

            <.form
              for={@join_form}
              phx-submit="join_game"
              phx-change="validate_join"
              class="space-y-4 mt-2"
            >
              <div class="form-control">
                <label class="label"><span class="label-text font-medium">Your Name</span></label>
                <input
                  type="text"
                  name="player_name"
                  value={@join_form["player_name"].value}
                  placeholder="Enter your name"
                  class="input input-bordered w-full focus:input-secondary"
                  maxlength="20"
                  required
                />
              </div>

              <div class="form-control">
                <label class="label"><span class="label-text font-medium">Room Code</span></label>
                <input
                  type="text"
                  name="room_code"
                  value={@join_form["room_code"].value}
                  placeholder="e.g. XK47BM"
                  class="input input-bordered w-full text-center text-3xl tracking-[0.3em] uppercase font-mono focus:input-secondary"
                  maxlength="6"
                  required
                />
              </div>

              <div :if={@join_error} role="alert" class="alert alert-error alert-sm">
                <.icon name="hero-exclamation-circle-mini" class="size-5" />
                <span>{@join_error}</span>
              </div>

              <button type="submit" class="btn btn-secondary w-full mt-2 gap-2">
                <.icon name="hero-arrow-right-circle-mini" class="size-5" /> Join Game
              </button>
            </.form>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp category_display("science"), do: "Science"
  defp category_display("history"), do: "History"
  defp category_display("geography"), do: "Geography"
  defp category_display("entertainment"), do: "Entertainment"
  defp category_display("sports"), do: "Sports"
  defp category_display(cat), do: String.capitalize(cat)

  defp put_session(socket, key, value) do
    assign(socket, key, value)
  end
end
