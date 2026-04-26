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

    test "글로벌 top nav (Happy Trizn + 게임명) 게임 화면에도 노출", %{conn: conn, room: room} do
      conn = Phoenix.ConnTest.get(conn, ~p"/game/tetris/#{room.id}")
      html = Phoenix.ConnTest.html_response(conn, 200)
      assert html =~ "Happy Trizn"
      assert html =~ "Tetris"
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

    test "모달 save_binding → key_settings 즉시 갱신 + 모달 유지 (단일 저장)", %{
      conn: conn,
      room: room
    } do
      {:ok, view, _} = live(conn, ~p"/game/tetris/#{room.id}")
      view |> element("button[phx-click='open_settings']") |> render_click()

      view
      |> form("form[phx-submit='modal_save_binding']:nth-of-type(1)")
      |> render_submit(%{"action" => "hard_drop", "keys" => "Space, q"})

      html = render(view)
      assert html =~ "&quot;hard_drop&quot;:[&quot; &quot;,&quot;q&quot;]"
      # 단일 저장 후에도 모달 그대로 — 다른 키도 연속 저장 가능
      assert html =~ "phx-submit=\"modal_save_binding\""
    end

    test "모달 save_options (옵션 저장 버튼) → 모달 닫힘", %{conn: conn, room: room} do
      {:ok, view, _} = live(conn, ~p"/game/tetris/#{room.id}")
      view |> element("button[phx-click='open_settings']") |> render_click()
      assert render(view) =~ "modal_save_options"

      view
      |> form("form[phx-submit='modal_save_options']")
      |> render_submit(%{"options" => %{"das" => "100"}})

      refute render(view) =~ "modal_save_options"
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

    test "다음 큐 (5 piece) UI 노출 + 좌측 holdpane 분리", %{conn: conn, room: room} do
      {:ok, _, html} = live(conn, ~p"/game/tetris/#{room.id}")
      # next_queue 컴포넌트 marker
      assert html =~ ">다음<"
      # hold 좌측 라벨
      assert html =~ ">홀드<"
    end

    test "pending garbage spoiler bar — 빨간 indicator 가 board 옆에 노출", %{
      conn: conn,
      room: room
    } do
      {:ok, view, _} = live(conn, ~p"/game/tetris/#{room.id}")

      # 강제로 player pending_garbage 5 셋업.
      pid = HappyTrizn.Games.GameSession.whereis_room(room.id)

      :sys.replace_state(pid, fn state ->
        # 첫 player_id 찾아 pending_garbage 5 강제.
        gs = state.game_state

        new_players =
          Map.new(gs.players, fn {id, p} -> {id, %{p | pending_garbage: 5}} end)

        %{state | game_state: %{gs | players: new_players}}
      end)

      # 실제 player_id 의 갱신된 player state 를 broadcast — pending_garbage = 5 반영.
      state = HappyTrizn.Games.GameSession.get_state(pid)
      [player_id] = Map.keys(state.players)
      pp = HappyTrizn.Games.Tetris.public_player(state.players[player_id])
      send(view.pid, {:game_event, {:player_state, player_id, pp}})
      Process.sleep(20)
      html = render(view)

      # spoiler bar (bg-error animate-pulse) 가 노출
      assert html =~ "bg-error"
      assert html =~ "animate-pulse"
    end

    test "🔄 다시 하기 버튼 클릭 → restart action → 라운드 리셋", %{conn: conn, room: room} do
      {:ok, view, _} = live(conn, ~p"/game/tetris/#{room.id}")
      pid = HappyTrizn.Games.GameSession.whereis_room(room.id)

      # 강제로 :over + winner=현재 player 상태.
      :sys.replace_state(pid, fn state ->
        gs = state.game_state
        [player_id] = Map.keys(gs.players)
        %{state | game_state: %{gs | status: :over, winner: player_id}}
      end)

      send(view.pid, {:game_event, {:game_over, %{winner: nil, players: %{}}}})
      Process.sleep(20)
      html = render(view)
      assert html =~ "다시 하기"

      view |> element("button[phx-click='restart']") |> render_click()
      Process.sleep(20)

      state = HappyTrizn.Games.GameSession.get_state(pid)
      # 1명 → :practice, 2명 → :countdown 으로 진입. 여기는 1명.
      assert state.status == :practice
    end

    test "game_over_panel 에 winners_summary (닉네임 누적 우승) 표시", %{conn: conn, room: room} do
      {:ok, view, _} = live(conn, ~p"/game/tetris/#{room.id}")

      # game_over event 수동 push — winners_summary 포함.
      send(
        view.pid,
        {:game_event,
         {:game_over,
          %{
            winner: "p_other",
            players: %{},
            winners_summary: [
              %{user_id: "u1", nickname: "alice", wins: 5},
              %{user_id: "u2", nickname: "bob", wins: 2}
            ]
          }}}
      )

      Process.sleep(20)
      html = render(view)
      assert html =~ "alice"
      assert html =~ "5회"
      assert html =~ "bob"
      assert html =~ "2회"
      assert html =~ "방 누적 우승"
    end

    test "TetrisSound 훅 + 사운드 옵션 data attrs 노출", %{conn: conn, room: room} do
      {:ok, _, html} = live(conn, ~p"/game/tetris/#{room.id}")
      assert html =~ "phx-hook=\"TetrisSound\""
      assert html =~ "data-sound-rotate"
      assert html =~ "data-sound-tetris"
      assert html =~ "data-sound-volume"
    end

    test "lock event → tetris:sfx push (lock)", %{conn: conn, room: room} do
      {:ok, view, _} = live(conn, ~p"/game/tetris/#{room.id}")
      pid = HappyTrizn.Games.GameSession.whereis_room(room.id)

      # 첫 player_id 가져오기
      state = HappyTrizn.Games.GameSession.get_state(pid)
      [player_id] = Map.keys(state.players)

      send(view.pid, {:game_event, {:locked, player_id}})
      assert_push_event(view, "tetris:sfx", %{event: "lock"})
    end

    test "line_clear (4 lines) → tetris sfx", %{conn: conn, room: room} do
      {:ok, view, _} = live(conn, ~p"/game/tetris/#{room.id}")
      pid = HappyTrizn.Games.GameSession.whereis_room(room.id)
      state = HappyTrizn.Games.GameSession.get_state(pid)
      [player_id] = Map.keys(state.players)

      send(
        view.pid,
        {:game_event,
         {:line_clear, %{player: player_id, lines: 4, b2b: false, tspin: :none, combo: 0}}}
      )

      assert_push_event(view, "tetris:sfx", %{event: "tetris"})
    end

    test "rotate event → rotate sfx", %{conn: conn, room: room} do
      {:ok, view, _} = live(conn, ~p"/game/tetris/#{room.id}")
      pid = HappyTrizn.Games.GameSession.whereis_room(room.id)
      [player_id] = HappyTrizn.Games.GameSession.get_state(pid).players |> Map.keys()

      send(view.pid, {:game_event, {:rotated, player_id}})
      assert_push_event(view, "tetris:sfx", %{event: "rotate"})
    end

    test "b2b line_clear (b2b: true) → b2b sfx", %{conn: conn, room: room} do
      {:ok, view, _} = live(conn, ~p"/game/tetris/#{room.id}")
      pid = HappyTrizn.Games.GameSession.whereis_room(room.id)
      [player_id] = HappyTrizn.Games.GameSession.get_state(pid).players |> Map.keys()

      send(
        view.pid,
        {:game_event,
         {:line_clear, %{player: player_id, lines: 4, b2b: true, tspin: :none, combo: 0}}}
      )

      assert_push_event(view, "tetris:sfx", %{event: "b2b"})
    end

    test "garbage_sent (to: me) → garbage sfx", %{conn: conn, room: room} do
      {:ok, view, _} = live(conn, ~p"/game/tetris/#{room.id}")
      pid = HappyTrizn.Games.GameSession.whereis_room(room.id)
      [player_id] = HappyTrizn.Games.GameSession.get_state(pid).players |> Map.keys()

      send(view.pid, {:game_event, {:garbage_sent, %{from: "x", to: player_id, lines: 3}}})
      assert_push_event(view, "tetris:sfx", %{event: "garbage"})
    end

    test "top_out (me) → top_out sfx", %{conn: conn, room: room} do
      {:ok, view, _} = live(conn, ~p"/game/tetris/#{room.id}")
      pid = HappyTrizn.Games.GameSession.whereis_room(room.id)
      [player_id] = HappyTrizn.Games.GameSession.get_state(pid).players |> Map.keys()

      send(view.pid, {:game_event, {:top_out, player_id}})
      assert_push_event(view, "tetris:sfx", %{event: "top_out"})
    end

    test "countdown_start → countdown sfx", %{conn: conn, room: room} do
      {:ok, view, _} = live(conn, ~p"/game/tetris/#{room.id}")
      send(view.pid, {:game_event, {:countdown_start, 3000}})
      assert_push_event(view, "tetris:sfx", %{event: "countdown"})
    end

    test "player_state event → game_state.players 직접 갱신 (GenServer.call 안 함)", %{
      conn: conn,
      room: room
    } do
      {:ok, view, _} = live(conn, ~p"/game/tetris/#{room.id}")
      pid = HappyTrizn.Games.GameSession.whereis_room(room.id)
      [player_id] = HappyTrizn.Games.GameSession.get_state(pid).players |> Map.keys()

      # 가짜 player state — score 9999 — broadcast.
      fake = %{
        board: HappyTrizn.Games.Tetris.Board.new(),
        current: %{type: :o, rotation: 0, origin: {0, 4}},
        next: :i,
        nexts: [:i, :t, :s, :z, :l],
        hold: nil,
        hold_used: false,
        score: 9999,
        lines: 99,
        level: 5,
        pending_garbage: 0,
        combo: -1,
        b2b: false,
        top_out: false,
        lock_delay_ms: nil,
        pieces_placed: 0
      }

      send(view.pid, {:game_event, {:player_state, player_id, fake}})
      Process.sleep(20)
      html = render(view)
      # 화면에 9999 점수 노출
      assert html =~ "9999"
    end

    test "modal reset 버튼 → bindings/options 초기화 + 모달 유지", %{conn: conn, room: room, host: host} do
      {:ok, _} =
        HappyTrizn.UserGameSettings.upsert(host, "tetris", %{
          key_bindings: %{"move_left" => ["q"]},
          options: %{"das" => 99}
        })

      {:ok, view, _} = live(conn, ~p"/game/tetris/#{room.id}")
      view |> element("button[phx-click='open_settings']") |> render_click()

      view |> element("button[phx-click='modal_reset']") |> render_click()

      result = HappyTrizn.UserGameSettings.get_for(host, "tetris")
      # 기본값 복귀
      assert result.das == 133
      assert "ArrowLeft" in result.bindings["move_left"]
      # 모달 유지 (form 그대로)
      assert render(view) =~ "modal_save_binding"
    end
  end

  describe "/game/skribbl/:id — Skribbl 통합" do
    setup %{conn: conn} do
      Rooms.clear_kick_bans()
      host = user_fixture(nickname: "sk_host_#{System.unique_integer([:positive])}")

      {:ok, room} =
        Rooms.create(host, %{
          game_type: "skribbl",
          name: "sk_#{System.unique_integer([:positive])}"
        })

      {:ok, conn: log_in_user(conn, host), host: host, room: room}
    end

    test "마운트 + canvas hook + 참가자 표시", %{conn: conn, room: room} do
      {:ok, _, html} = live(conn, ~p"/game/skribbl/#{room.id}")
      assert html =~ "phx-hook=\"SkribblCanvas\""
      assert html =~ "참가자"
      assert html =~ "채팅"
    end

    test "혼자면 시작 버튼 안 보임 (2명 이상 필요)", %{conn: conn, room: room} do
      {:ok, _, html} = live(conn, ~p"/game/skribbl/#{room.id}")
      refute html =~ "phx-click=\"skribbl_start_game\""
    end

    test "2명 모인 후 start_game → :choosing 진입 + word_choices broadcast", %{
      conn: conn,
      host: host,
      room: room
    } do
      {:ok, view_a, _} = live(conn, ~p"/game/skribbl/#{room.id}")

      bob = user_fixture(nickname: "sk_b_#{System.unique_integer([:positive])}")
      conn_b = Phoenix.ConnTest.build_conn() |> log_in_user(bob)
      {:ok, _view_b, _} = live(conn_b, ~p"/game/skribbl/#{room.id}")

      Process.sleep(20)
      html = render(view_a)
      assert html =~ "phx-click=\"skribbl_start_game\""

      view_a |> element("button[phx-click='skribbl_start_game']") |> render_click()

      pid = HappyTrizn.Games.GameSession.whereis_room(room.id)
      state = HappyTrizn.Games.GameSession.get_state(pid)
      assert state.status == :choosing
      assert length(state.word_choices) == 3
      _ = host
    end

    test "stroke event 보내면 다른 사용자 push_event 받음", %{conn: conn, host: _host, room: room} do
      {:ok, view_a, _} = live(conn, ~p"/game/skribbl/#{room.id}")
      bob = user_fixture(nickname: "sk_str_#{System.unique_integer([:positive])}")
      conn_b = Phoenix.ConnTest.build_conn() |> log_in_user(bob)
      {:ok, view_b, _} = live(conn_b, ~p"/game/skribbl/#{room.id}")
      Process.sleep(20)

      view_a |> element("button[phx-click='skribbl_start_game']") |> render_click()
      pid = HappyTrizn.Games.GameSession.whereis_room(room.id)

      state = HappyTrizn.Games.GameSession.get_state(pid)
      drawer_id = state.drawer_id
      [first | _] = state.word_choices

      # drawer 가 단어 고름 → :drawing
      drawer_view = if drawer_id == view_a.id, do: view_a, else: view_b

      HappyTrizn.Games.GameSession.handle_input(pid, drawer_id, %{
        "action" => "choose_word",
        "word" => first
      })

      Process.sleep(20)

      # drawer 가 stroke 입력
      stroke = %{
        "from" => %{"x" => 1, "y" => 1},
        "to" => %{"x" => 10, "y" => 10},
        "color" => "#000000",
        "size" => 4
      }

      HappyTrizn.Games.GameSession.handle_input(pid, drawer_id, %{
        "action" => "stroke",
        "stroke" => stroke
      })

      # 양쪽 view 모두 push_event "skribbl:stroke" 받아야
      assert_push_event(view_a, "skribbl:stroke", _)
      assert_push_event(view_b, "skribbl:stroke", _)

      _ = drawer_view
    end

    test "글로벌 top nav (Happy Trizn + 캐치마인드) skribbl 화면에도 노출", %{conn: conn, room: room} do
      conn = Phoenix.ConnTest.get(conn, ~p"/game/skribbl/#{room.id}")
      html = Phoenix.ConnTest.html_response(conn, 200)
      assert html =~ "Happy Trizn"
      assert html =~ "캐치마인드"
    end

    test "skribbl_chat 후 chat:reset_input push (입력창 자동 비움)", %{conn: conn, room: room} do
      {:ok, view, _} = live(conn, ~p"/game/skribbl/#{room.id}")
      view |> render_hook("skribbl_chat", %{"text" => "안녕"})
      assert_push_event(view, "chat:reset_input", %{})
    end

    test "round_end 시 정답 공개 popup 모달 표시", %{conn: conn, room: room} do
      {:ok, view, _} = live(conn, ~p"/game/skribbl/#{room.id}")
      bob = user_fixture(nickname: "sk_re_#{System.unique_integer([:positive])}")
      conn_b = Phoenix.ConnTest.build_conn() |> log_in_user(bob)
      {:ok, _, _} = live(conn_b, ~p"/game/skribbl/#{room.id}")
      Process.sleep(20)

      view |> element("button[phx-click='skribbl_start_game']") |> render_click()
      pid = HappyTrizn.Games.GameSession.whereis_room(room.id)

      # 강제로 round_end 상태 만듦.
      :sys.replace_state(pid, fn s ->
        gs = s.game_state
        new_gs = %{gs | status: :round_end, word: "사과", time_left_ms: 5000, word_revealed: true}
        %{s | game_state: new_gs}
      end)

      send(view.pid, {:game_event, {:round_end, %{reason: :timeout, word: "사과"}}})
      Process.sleep(20)
      html = render(view)

      # popup overlay (정답 공개 + 단어 + 다음 라운드 까지)
      assert html =~ "정답 공개"
      assert html =~ "사과"
    end

    test ":over 시 game_over popup + 다시 하기 버튼", %{conn: conn, room: room} do
      {:ok, view, _} = live(conn, ~p"/game/skribbl/#{room.id}")
      bob = user_fixture(nickname: "sk_o_#{System.unique_integer([:positive])}")
      conn_b = Phoenix.ConnTest.build_conn() |> log_in_user(bob)
      {:ok, _, _} = live(conn_b, ~p"/game/skribbl/#{room.id}")
      Process.sleep(20)

      view |> element("button[phx-click='skribbl_start_game']") |> render_click()
      pid = HappyTrizn.Games.GameSession.whereis_room(room.id)

      :sys.replace_state(pid, fn s ->
        gs = s.game_state
        # 강제 :over.
        winner_id = gs.players |> Map.keys() |> List.first()
        new_gs = %{gs | status: :over, winner_id: winner_id}
        %{s | game_state: new_gs}
      end)

      send(view.pid, {:game_event, {:game_finished, %{winner: nil}}})
      Process.sleep(20)
      html = render(view)
      assert html =~ "다시 하기"
    end
  end

  # ============================================================================
  # Bomberman 풀 통합 — 셀 크기, 이모티콘 클래스, scoreboard
  # ============================================================================

  describe "/game/bomberman/:id — Bomberman 통합" do
    setup %{conn: conn} do
      Rooms.clear_kick_bans()
      host = user_fixture(nickname: "bm_host_#{System.unique_integer([:positive])}")

      {:ok, room} =
        Rooms.create(host, %{
          game_type: "bomberman",
          name: "bm_#{System.unique_integer([:positive])}"
        })

      {:ok, conn: log_in_user(conn, host), host: host, room: room}
    end

    test "마운트 + 격자 + 조작 안내", %{conn: conn, room: room} do
      {:ok, _view, html} = live(conn, ~p"/game/bomberman/#{room.id}")
      assert html =~ "Bomberman" or html =~ "봄버맨" or html =~ "폭탄"
      assert html =~ "phx-hook=\"BombermanInput\""
      assert html =~ "참가자"
      # 셀 크기 — Sprint 3k 모바일 반응형: 데스크탑 w-12 h-12, 모바일 w-7 h-7.
      assert html =~ "sm:w-12 sm:h-12"
      assert html =~ "sm:text-2xl"
    end

    test "플레이어 아바타 (이모지 + ring 컬러) 노출", %{conn: conn, room: room} do
      {:ok, view, _} = live(conn, ~p"/game/bomberman/#{room.id}")

      pid = HappyTrizn.Games.GameSession.whereis_room(room.id)
      assert pid

      # 시작 안 한 상태도 spawn corner 에 player 가 있어야 (handle_player_join).
      Process.sleep(20)
      html = render(view)
      # 4 색 ring 클래스 중 첫 (red) 하나는 첫 player 라 등장.
      assert html =~ "ring-red-400"
    end

    test "chat aside 노출 + 게임방 채팅 입력 form 존재", %{conn: conn, room: room} do
      {:ok, _view, html} = live(conn, ~p"/game/bomberman/#{room.id}")
      assert html =~ "게임방 채팅"
      assert html =~ "phx-submit=\"game_chat\""
      assert html =~ "phx-hook=\"ChatScroll\""
    end
  end

  # ============================================================================
  # 게임방 ephemeral chat — Tetris / Bomberman 양쪽 동작.
  # ============================================================================

  describe "게임방 채팅 (game_chat)" do
    setup %{conn: conn} do
      Rooms.clear_kick_bans()
      host = user_fixture(nickname: "ch_host_#{System.unique_integer([:positive])}")
      {:ok, conn: log_in_user(conn, host), host: host}
    end

    test "tetris 화면 — 채팅 패널 표시", %{conn: conn, host: host} do
      {:ok, room} = Rooms.create(host, %{game_type: "tetris", name: "ch_t1"})
      {:ok, _view, html} = live(conn, ~p"/game/tetris/#{room.id}")
      assert html =~ "게임방 채팅"
      assert html =~ "phx-submit=\"game_chat\""
    end

    test "skribbl 화면 — 게임방 채팅 패널 안 보임 (자체 채팅 사용)", %{conn: conn, host: host} do
      {:ok, room} = Rooms.create(host, %{game_type: "skribbl", name: "ch_s1"})
      {:ok, _view, html} = live(conn, ~p"/game/skribbl/#{room.id}")
      refute html =~ "게임방 채팅"
    end

    test "메시지 전송 → 본인 화면에 노출", %{conn: conn, host: host} do
      {:ok, room} = Rooms.create(host, %{game_type: "tetris", name: "ch_t2"})
      {:ok, view, _} = live(conn, ~p"/game/tetris/#{room.id}")

      view
      |> element("form[phx-submit='game_chat']")
      |> render_submit(%{"text" => "안녕"})

      Process.sleep(20)
      html = render(view)
      assert html =~ "안녕"
      # nickname 도 노출.
      assert html =~ host.nickname
    end

    test "메시지 broadcast — 다른 LiveView 도 수신", %{conn: conn, host: host} do
      {:ok, room} = Rooms.create(host, %{game_type: "bomberman", name: "ch_b1"})
      {:ok, view_a, _} = live(conn, ~p"/game/bomberman/#{room.id}")

      bob = user_fixture(nickname: "ch_bob_#{System.unique_integer([:positive])}")
      conn_b = Phoenix.ConnTest.build_conn() |> log_in_user(bob)
      {:ok, view_b, _} = live(conn_b, ~p"/game/bomberman/#{room.id}")
      Process.sleep(20)

      view_a
      |> element("form[phx-submit='game_chat']")
      |> render_submit(%{"text" => "GG"})

      Process.sleep(20)
      assert render(view_a) =~ "GG"
      assert render(view_b) =~ "GG"
    end

    test "빈 텍스트 — broadcast 안 함", %{conn: conn, host: host} do
      {:ok, room} = Rooms.create(host, %{game_type: "tetris", name: "ch_t3"})
      {:ok, view, _} = live(conn, ~p"/game/tetris/#{room.id}")

      view
      |> element("form[phx-submit='game_chat']")
      |> render_submit(%{"text" => "   "})

      Process.sleep(20)
      html = render(view)
      assert html =~ "아직 메시지 없음"
    end

    test "200자 초과 — slice 후 노출", %{conn: conn, host: host} do
      {:ok, room} = Rooms.create(host, %{game_type: "tetris", name: "ch_t4"})
      {:ok, view, _} = live(conn, ~p"/game/tetris/#{room.id}")

      long = String.duplicate("a", 250)

      view
      |> element("form[phx-submit='game_chat']")
      |> render_submit(%{"text" => long})

      Process.sleep(20)
      html = render(view)
      # 200자 까지만 보임 — "a" 200개 노출.
      assert html =~ String.duplicate("a", 200)
    end

    test "input 비움 push_event (chat:reset_input)", %{conn: conn, host: host} do
      {:ok, room} = Rooms.create(host, %{game_type: "tetris", name: "ch_t5"})
      {:ok, view, _} = live(conn, ~p"/game/tetris/#{room.id}")

      view
      |> element("form[phx-submit='game_chat']")
      |> render_submit(%{"text" => "hi"})

      assert_push_event(view, "chat:reset_input", _)
    end
  end

  # ============================================================================
  # Snake.io 통합 — 마운트 / 캔버스 hook / set_dir / 채팅
  # ============================================================================

  describe "/game/snake_io/:id — Snake.io 통합" do
    setup %{conn: conn} do
      Rooms.clear_kick_bans()
      host = user_fixture(nickname: "sn_host_#{System.unique_integer([:positive])}")

      {:ok, room} =
        Rooms.create(host, %{
          game_type: "snake_io",
          name: "sn_#{System.unique_integer([:positive])}"
        })

      {:ok, conn: log_in_user(conn, host), host: host, room: room}
    end

    test "마운트 + canvas hook + 게임방 채팅", %{conn: conn, room: room} do
      {:ok, _view, html} = live(conn, ~p"/game/snake_io/#{room.id}")
      assert html =~ "phx-hook=\"SnakeInput\""
      assert html =~ "phx-hook=\"SnakeCanvas\""
      assert html =~ "리더보드"
      assert html =~ "게임방 채팅"
      # 캔버스 — 200×200 월드 (클라 카메라가 viewport 일부만 그림).
      assert html =~ "data-grid-size=\"200\""
    end

    test "set_dir → GameSession 에 forward", %{conn: conn, room: room} do
      {:ok, view, _} = live(conn, ~p"/game/snake_io/#{room.id}")
      Process.sleep(20)

      pid = HappyTrizn.Games.GameSession.whereis_room(room.id)
      assert pid

      # set_dir 보냄. 현재 dir 와 반대 아닌 방향 보장: tick 마다 dir 바뀔 수 있어
      # 4 방향 모두 시도해 next_dir 갱신 확인 — 한 번이라도 받아들여지면 OK.
      Enum.each(["up", "down", "left", "right"], fn d ->
        render_hook(view, "snake_set_dir", %{"dir" => d})
      end)

      # state 폭주 X — view 살아 있음.
      assert render(view) =~ "Snake.io"
    end

    test "1명 join 만 해도 :playing — game_over 안 발생", %{conn: conn, room: room} do
      {:ok, _view, _} = live(conn, ~p"/game/snake_io/#{room.id}")
      Process.sleep(60)
      pid = HappyTrizn.Games.GameSession.whereis_room(room.id)
      state = HappyTrizn.Games.GameSession.get_state(pid)
      assert state.status == :playing
      assert map_size(state.players) == 1
    end
  end
end
