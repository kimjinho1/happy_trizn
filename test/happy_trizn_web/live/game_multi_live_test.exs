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

    test "두 사용자 동시 입장 → 같은 GameSession 에 둘 다 join (방 만든 사람이 사라지지 않음)",
         %{conn: conn, host: host, room: room} do
      # host A 가 게임 방 입장
      {:ok, view_a, _} = live(conn, ~p"/game/tetris/#{room.id}")
      pid_a = HappyTrizn.Games.GameSession.whereis_room(room.id)
      assert pid_a
      state_a = HappyTrizn.Games.GameSession.get_state(pid_a)
      assert map_size(state_a.players) == 1

      # B 가 같은 방으로 입장
      bob = user_fixture(nickname: "bob_#{System.unique_integer([:positive])}")
      conn_b = Phoenix.ConnTest.build_conn() |> log_in_user(bob)
      {:ok, _view_b, _} = live(conn_b, ~p"/game/tetris/#{room.id}")

      # 같은 GameSession pid 사용 (host 가 만든 세션 그대로)
      pid_b = HappyTrizn.Games.GameSession.whereis_room(room.id)
      assert pid_b == pid_a

      state = HappyTrizn.Games.GameSession.get_state(pid_b)
      assert map_size(state.players) == 2

      # host (A) 가 여전히 player 안에 있어야 — HTTP mount 의 leave 사이클이 죽이지 않음
      _ = view_a
      _ = host
    end

    test "혼자 입장 → 스프린트 버튼 노출 + 클릭 시 :practice 진입", %{conn: conn, room: room} do
      {:ok, view, html} = live(conn, ~p"/game/tetris/#{room.id}")
      assert html =~ "스프린트"

      view |> element("button[phx-click='start_practice']") |> render_click()

      pid = HappyTrizn.Games.GameSession.whereis_room(room.id)
      state = HappyTrizn.Games.GameSession.get_state(pid)
      assert state.status == :practice
    end

    test "2번째 player 입장 → 카운트다운 배너 (시작까지 N…)", %{conn: conn, room: room} do
      # host A
      {:ok, view_a, _} = live(conn, ~p"/game/tetris/#{room.id}")

      # B 입장
      bob = user_fixture(nickname: "bob_cd_#{System.unique_integer([:positive])}")
      conn_b = Phoenix.ConnTest.build_conn() |> log_in_user(bob)
      {:ok, _view_b, _} = live(conn_b, ~p"/game/tetris/#{room.id}")

      # A 화면에 countdown 표기 도달 (PubSub broadcast 전파 후)
      Process.sleep(50)
      html = render(view_a)
      assert html =~ "시작까지"

      pid = HappyTrizn.Games.GameSession.whereis_room(room.id)
      state = HappyTrizn.Games.GameSession.get_state(pid)
      assert state.status == :countdown
      # 양쪽 모두 fresh state — score 0
      Enum.each(state.players, fn {_, p} -> assert p.score == 0 end)
    end

    test "글로벌 🏠 홈 링크 게임 화면에도 노출", %{conn: conn, room: room} do
      conn = Phoenix.ConnTest.get(conn, ~p"/game/tetris/#{room.id}")
      html = Phoenix.ConnTest.html_response(conn, 200)
      assert html =~ "🏠"
    end

    test "ghost piece + grid class render", %{conn: conn, room: room} do
      {:ok, _view, html} = live(conn, ~p"/game/tetris/#{room.id}")
      # standard grid class (default)
      assert html =~ "border-base-100"
      # 옵션 hold/next preview 컴포넌트
      assert html =~ "홀드"
      assert html =~ "다음"
    end

    test "⚙️ 옵션 → 모달 인라인 (페이지 안 옮김)", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/game/tetris/#{room.id}")
      # 처음엔 모달 안 열림
      refute render(view) =~ "modal_save_binding"

      view |> element("button[phx-click='open_settings']") |> render_click()
      html = render(view)
      assert html =~ "modal_save_binding"
      assert html =~ "modal_save_options"
      assert html =~ "phx-click=\"close_settings\""
    end

    test "모달 save_binding → key_settings 즉시 갱신 + 모달 자동 닫힘", %{conn: conn, room: room} do
      {:ok, view, _} = live(conn, ~p"/game/tetris/#{room.id}")
      view |> element("button[phx-click='open_settings']") |> render_click()
      assert render(view) =~ "modal_save_binding"

      view
      |> form("form[phx-submit='modal_save_binding']:nth-of-type(1)")
      |> render_submit(%{"action" => "hard_drop", "keys" => "Space, q"})

      html = render(view)
      # data-key-bindings 에 새 키 반영
      assert html =~ "&quot;hard_drop&quot;:[&quot; &quot;,&quot;q&quot;]"
      # 모달 자동 닫힘 (form 사라짐)
      refute html =~ "phx-submit=\"modal_save_binding\""
    end

    test "모달 ✕ 버튼 → 닫힘", %{conn: conn, room: room} do
      {:ok, view, _} = live(conn, ~p"/game/tetris/#{room.id}")
      view |> element("button[phx-click='open_settings']") |> render_click()
      assert render(view) =~ "modal_save_binding"

      # 닫기 버튼 (모달 안의 ✕)
      view |> element("#settings-modal-box button[phx-click='close_settings']") |> render_click()
      refute render(view) =~ "modal_save_binding"
    end

    test "tetris 일 때 phx-window-keyup 비활성 (JS hook 만 키 처리)", %{conn: conn, room: room} do
      {:ok, _view, html} = live(conn, ~p"/game/tetris/#{room.id}")
      # 더블파이어 방지 — server keyup handler 없어야
      refute html =~ "phx-window-keyup=\"key\""
      # JS hook 은 살아있어야
      assert html =~ "phx-hook=\"TetrisInput\""
    end

    test "HTTP-only mount (connected? = false) 는 GameSession 안 건드림", %{conn: conn, room: room} do
      # disconnected GET 요청만 — websocket 없음 (Phoenix.ConnTest 가 fully render)
      conn = Phoenix.ConnTest.get(conn, ~p"/game/tetris/#{room.id}")
      assert conn.status == 200
      # GameSession 시작 안 됨 (connected 일 때만 시작)
      assert HappyTrizn.Games.GameSession.whereis_room(room.id) == nil
    end
  end
end
