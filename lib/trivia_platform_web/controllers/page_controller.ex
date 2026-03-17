defmodule TriviaPlatformWeb.PageController do
  use TriviaPlatformWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
