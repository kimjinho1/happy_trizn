defmodule HappyTriznWeb.GamePlaceholderLiveTest do
  use HappyTriznWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "/game/:game_type/:room_id" do
    test "비입장 사용자 / 로 리다이렉트", %{conn: conn} do
      conn = Plug.Test.init_test_session(conn, %{})

      assert {:error, {:redirect, %{to: "/"}}} =
               live(conn, ~p"/game/tetris/abc-123")
    end

    test "입장 사용자 mount 성공 + game_type / room_id 표시", %{conn: conn} do
      nick = "ppl_#{System.unique_integer([:positive])}"
      conn = log_in_user(conn, nil, nick)

      {:ok, _view, html} = live(conn, ~p"/game/tetris/abc-123")
      assert html =~ "tetris"
      assert html =~ "abc-123"
      assert html =~ "Sprint 3"
      assert html =~ nick
    end
  end
end
