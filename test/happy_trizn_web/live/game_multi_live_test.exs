defmodule HappyTriznWeb.GameMultiLiveTest do
  use HappyTriznWeb.ConnCase, async: false
  # async: false — GameSession Registry 와 ETS 격리.

  import Phoenix.LiveViewTest

  alias HappyTrizn.Rooms

  setup do
    Rooms.clear_kick_bans()
    :ok
  end

  defp create_tetris_room(host) do
    {:ok, room} =
      Rooms.create(host, %{game_type: "tetris", name: "ml_#{System.unique_integer([:positive])}"})

    room
  end

  describe "/game/:type/:id — guard" do
    test "비입장 사용자는 / 리다이렉트", %{conn: conn} do
      conn = Plug.Test.init_test_session(conn, %{})
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/game/tetris/abc-123")
    end

    test "게스트는 /lobby 리다이렉트", %{conn: conn} do
      conn = log_in_user(conn, nil, "guest_#{System.unique_integer([:positive])}")
      assert {:error, {:redirect, %{to: "/lobby"}}} = live(conn, ~p"/game/tetris/abc-123")
    end

    test "없는 game slug → /lobby", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      room = create_tetris_room(user)
      assert {:error, {:redirect, %{to: "/lobby"}}} = live(conn, ~p"/game/nonexistent/#{room.id}")
    end

    test "싱글 게임 slug → /play/<slug> 리다이렉트", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      assert {:error, {:redirect, %{to: redirect_path}}} = live(conn, ~p"/game/2048/some-room-id")
      assert redirect_path =~ "/play/2048"
    end

    test "없는 방 → /lobby", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      assert {:error, {:redirect, %{to: "/lobby"}}} =
               live(conn, ~p"/game/tetris/00000000-0000-0000-0000-000000000000")
    end

    test "방 game_type 불일치 → /lobby", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      {:ok, bomb_room} = Rooms.create(user, %{game_type: "bomberman", name: "b1"})
      # /game/tetris/<bomberman 방 id> 진입 → 매치 실패
      assert {:error, {:redirect, %{to: "/lobby"}}} = live(conn, ~p"/game/tetris/#{bomb_room.id}")
    end
  end

  describe "/game/tetris/:id — Tetris 풀 통합" do
    setup %{conn: conn} do
      host = user_fixture(nickname: "host_#{System.unique_integer([:positive])}")
      room = create_tetris_room(host)
      {:ok, conn: log_in_user(conn, host), host: host, room: room}
    end

    test "mount + game_state 전달", %{conn: conn, room: room} do
      {:ok, _view, html} = live(conn, ~p"/game/tetris/#{room.id}")
      assert html =~ "Tetris"
      assert html =~ room.id
      assert html =~ "방:"
    end

    test "키보드 이벤트 — input forward", %{conn: conn, room: room} do
      {:ok, view, _} = live(conn, ~p"/game/tetris/#{room.id}")

      # ArrowLeft / ArrowRight / ArrowUp / ArrowDown / Space
      render_keyup(view, "key", %{"key" => "ArrowLeft"})
      render_keyup(view, "key", %{"key" => "ArrowDown"})
      # 화면 깨짐 X (server에서 GameSession.handle_input 내부 처리)
      assert render(view) =~ "Tetris"
    end

    test "phx-click input action — 직접 trigger", %{conn: conn, room: room} do
      {:ok, view, _} = live(conn, ~p"/game/tetris/#{room.id}")
      render_hook(view, "input", %{"action" => "left"})
      assert render(view) =~ "Tetris"
    end

    test "GameSession 에 player 자동 join", %{conn: conn, room: room} do
      {:ok, _view, _} = live(conn, ~p"/game/tetris/#{room.id}")

      pid = HappyTrizn.Games.GameSession.whereis_room(room.id)
      assert pid
      state = HappyTrizn.Games.GameSession.get_state(pid)
      assert map_size(state.players) >= 1
    end
  end
end
