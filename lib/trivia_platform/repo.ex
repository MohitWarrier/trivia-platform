defmodule TriviaPlatform.Repo do
  use Ecto.Repo,
    otp_app: :trivia_platform,
    adapter: Ecto.Adapters.Postgres
end
