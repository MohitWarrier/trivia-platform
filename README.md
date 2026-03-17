# Trivia Platform

Real-time multiplayer trivia game built with Elixir, Phoenix LiveView, and OTP.

No sign-up required. One player creates a room, shares a 6-character code, others join and play in real-time through their browser.

## How it works

1. **Host** creates a game room, picks a category and question count
2. **Players** join using the room code (no account needed)
3. **Host** starts the game, everyone sees questions simultaneously
4. **Players** answer within 15 seconds, faster correct answers = more points
5. **Leaderboard** updates after each question, final results saved to database

## Tech stack

| Layer | Technology | Why |
|-------|-----------|-----|
| Language | Elixir 1.19 / OTP 28 | Per-room GenServer processes, fault-tolerant supervision, built for concurrency |
| Web | Phoenix 1.8 + LiveView 1.1 | Real-time server-rendered UI over WebSocket, zero client-side JS framework needed |
| Database | PostgreSQL | Persistent storage for questions and game history |
| Styling | Tailwind CSS 4 + DaisyUI | Utility-first CSS with pre-built components |
| HTTP Server | Bandit | Pure-Elixir HTTP server, first-class WebSocket support |

## Quick start

**Prerequisites:** Elixir 1.19+, PostgreSQL running locally

```bash
# Clone and setup
git clone <repo-url>
cd trivia_platform
mix deps.get

# Create database, run migrations, seed 55 trivia questions
mix ecto.setup

# Start the server
mix phx.server
```

Visit [localhost:4000](http://localhost:4000).

**Note:** PostgreSQL password is configured as `"elixir"` in `config/dev.exs`. Change it if yours differs.

## Testing

```bash
mix test          # 76 tests, 0 failures
mix test --trace  # verbose output with test names
```

Tests include a full multiplayer game simulation (host + 2 players, all questions, scoring, DB persistence) without needing multiple browsers. See `test/trivia_platform_web/live/game_loop_test.exs`.

## Manual testing (single person)

Open 3 browser tabs:
1. **Tab 1** (Host): `localhost:4000` -> Create game -> note the room code
2. **Tab 2** (Player 1): `localhost:4000` -> Join with the room code
3. **Tab 3** (Player 2): Same as above, different name

Each tab is an independent WebSocket connection, identical to 3 different computers.




