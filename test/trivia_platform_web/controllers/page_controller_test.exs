defmodule TriviaPlatformWeb.PageControllerTest do
  use TriviaPlatformWeb.ConnCase

  test "GET / renders home page", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Trivia Platform"
  end
end
