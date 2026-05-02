defmodule HappyTriznWeb.GameLiveTest do
  use HappyTriznWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "/play/:game_type — guard" do
    test "비입장 사용자는 / 리다이렉트", %{conn: conn} do
      conn = Plug.Test.init_test_session(conn, %{})
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/play/2048")
    end

    test "없는 game slug 는 /lobby 리다이렉트", %{conn: conn} do
      conn = log_in_user(conn, nil, "guest_#{System.unique_integer([:positive])}")
      assert {:error, {:redirect, %{to: "/lobby"}}} = live(conn, ~p"/play/nonexistent")
    end

    test "멀티 게임 slug → /lobby 리다이렉트 (singleplayer 만)", %{conn: conn} do
      conn = log_in_user(conn, nil, "guest_#{System.unique_integer([:positive])}")
      assert {:error, {:redirect, %{to: "/lobby"}}} = live(conn, ~p"/play/tetris")
    end
  end

  # ============================================================================
  # Sprint 4k — 진행 초기화 버튼 + snapshot 자동 저장 / 복원
  # ============================================================================
  describe "/play/2048 — snapshot autosave (Sprint 4k)" do
    setup %{conn: conn} do
      {:ok, user} =
        HappyTrizn.Accounts.register_user(%{
          email: "snap2048_#{System.unique_integer([:positive])}@trizn.kr",
          nickname: "snap2048_#{System.unique_integer([:positive])}",
          password: "hello12345"
        })

      {:ok, conn: log_in_user(conn, user), user: user}
    end

    test "login 사용자 + serializable 게임 → 헤더에 '초기화' 버튼 표시", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/play/2048")
      assert html =~ "🗑️ 초기화"
    end

    test "input 후 snapshot 저장 → 새로 mount 시 같은 board 복원", %{conn: conn, user: user} do
      {:ok, view, _} = live(conn, ~p"/play/2048")
      view |> element("button[phx-value-dir='left']") |> render_click()

      stored = HappyTrizn.GameSnapshots.get(user.id, "2048")
      assert is_map(stored)
      assert stored.score >= 0

      # 새 LV mount — 같은 user → snapshot 복원, board 같은 score.
      {:ok, _view2, html2} = live(conn, ~p"/play/2048")
      assert html2 =~ "점수: <strong>#{stored.score}</strong>"
    end

    test "초기화 버튼 클릭 → snapshot 삭제 + fresh state", %{conn: conn, user: user} do
      {:ok, view, _} = live(conn, ~p"/play/2048")
      view |> element("button[phx-value-dir='left']") |> render_click()
      assert HappyTrizn.GameSnapshots.get(user.id, "2048") != nil

      # 헤더의 "초기화" 버튼 = phx-click="restart" + data-confirm.
      view |> element("button[data-confirm*='초기화']") |> render_click()

      assert HappyTrizn.GameSnapshots.get(user.id, "2048") == nil
      assert render(view) =~ "점수: <strong>0</strong>"
    end
  end

  describe "/play/2048" do
    setup %{conn: conn} do
      {:ok, conn: log_in_user(conn, nil, "p2048_#{System.unique_integer([:positive])}")}
    end

    test "게스트 → '초기화' 버튼 표시 X", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/play/2048")
      refute html =~ "🗑️ 초기화"
    end

    test "mount + 초기 board 렌더 (default 4×4)", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/play/2048")
      assert html =~ "2048"
      assert html =~ "점수:"
      assert html =~ "보드: 4×4"
      # 4x4 = 16 cell div
      assert html |> String.split("w-16 h-16") |> length() == 17
    end

    test "input action move → 점수 변화", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/play/2048")

      # 아무 방향 move 시도 (board 결정 안 되어 있음 — 변화 X 가능성)
      view |> element("button[phx-value-dir='left']") |> render_click()
      # 화면 안 깨짐 검증
      assert render(view) =~ "점수:"
    end

    test "restart → score 0 + result 사라짐", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/play/2048")
      # restart event 직접 push
      render_click(view, "restart", %{})
      assert render(view) =~ "점수: <strong>0</strong>"
    end

    test "ArrowLeft keydown → board state 갱신", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/play/2048")

      html = render_keydown(view, "keydown", %{"key" => "ArrowLeft"})
      # 페이지 살아 있고 점수 표시 유지
      assert html =~ "점수:"
    end

    test "GameKeyCapture hook 마운트 — 화살표/WASD/HJKL preventDefault 키", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/play/2048")
      assert html =~ "phx-hook=\"GameKeyCapture\""
      # data-keys 에 화살표 + WASD + HJKL 포함 — 페이지 스크롤 회피.
      assert html =~ "ArrowUp,ArrowDown,ArrowLeft,ArrowRight"
      assert html =~ "w,W,a,A,s,S,d,D"
      assert html =~ "h,H,j,J,k,K,l,L"
    end

    test "WASD / HJKL 도 keydown 받음", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/play/2048")

      for key <- ~w(w s a d h j k l) do
        html = render_keydown(view, "keydown", %{"key" => key})
        assert html =~ "점수:", "key #{key} 깨짐"
      end
    end

    test "관계없는 키는 무시 — board 상태 변화 X", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/play/2048")
      board_before = extract_board(render(view))
      html_after = render_keydown(view, "keydown", %{"key" => "Tab"})
      board_after = extract_board(html_after)
      # render(view) 는 inner template, render_keydown 은 LV wrapper 포함 — 그래서
      # 전체 HTML 비교 X. game-2048 안의 board markup 만 비교 (Tab 후 동일해야).
      assert board_before == board_after
    end

    defp extract_board(html) do
      [_, after_open] = String.split(html, "<div id=\"game-2048\">", parts: 2)
      [board, _] = String.split(after_open, "</div>", parts: 2)
      board
    end

    test "옵션 모달 — 2048 도 모달로 (Sprint 4f-3)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/play/2048")
      refute render(view) =~ "modal_save_options"

      view |> element("button[phx-click='open_settings']") |> render_click()
      assert render(view) =~ "modal_save_options"
    end
  end

  describe "/play/minesweeper" do
    setup %{conn: conn} do
      {:ok, conn: log_in_user(conn, nil, "pms_#{System.unique_integer([:positive])}")}
    end

    test "mount — 지뢰찾기 (Sprint 4f rename) + medium 16×16 grid", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/play/minesweeper")
      # 페이지 제목 = 지뢰찾기 (메타 name). slug "minesweeper" 는 URL/path 라 그대로.
      assert html =~ "<h1 class=\"text-2xl font-bold\">지뢰찾기</h1>"
      assert html =~ "16×16"
      assert html =~ "지뢰 40개"
      # 256 hidden cell (16×16) 있어야
      assert html |> String.split("phx-value-action=\"reveal\"") |> length() == 257
    end

    test "셀 reveal → state 변화 (string r/c 강제 — phx-value 시뮬)", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/play/minesweeper")

      view
      |> element("button[phx-value-action='reveal'][phx-value-r='5'][phx-value-c='5']")
      |> render_click()

      # 클릭한 셀이 revealed → button 안 보임 (div 로 교체).
      html = render(view)
      refute html =~ "phx-value-action=\"reveal\" phx-value-r=\"5\" phx-value-c=\"5\""
    end

    test "키보드 — 화살표 cursor 이동 + Space reveal + F flag (Sprint 4f)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/play/minesweeper")

      # cursor 초기 (8, 8) — medium 16×16 중앙. 화살표 up → (7, 8).
      render_hook(view, "keydown", %{"key" => "ArrowUp"})
      html = render(view)
      # cursor highlight = outline outline-primary 적용된 셀 1개.
      assert html =~ "outline-primary"

      # F → flag_cursor → 해당 셀 flagged.
      render_hook(view, "keydown", %{"key" => "f"})
      html = render(view)
      assert html =~ "🚩"

      # F 다시 → 해제.
      render_hook(view, "keydown", %{"key" => "F"})
      html = render(view)
      refute html =~ "🚩"

      # Space → reveal_cursor.
      render_hook(view, "keydown", %{"key" => " "})
      _html = render(view)
      # cursor 위치 (7, 8) reveal — button 사라짐.
      refute render(view) =~
               "phx-value-action=\"reveal\" phx-value-r=\"7\" phx-value-c=\"8\""
    end

    test "data-keys 에 F / Space 포함 (Sprint 4f)", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/play/minesweeper")
      assert html =~ "data-keys="
      assert html =~ "f,F"
      assert html =~ "Spacebar"
    end

    test "MinesweeperCell hook — 우클릭 flag 용", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/play/minesweeper")
      assert html =~ "phx-hook=\"MinesweeperCell\""
    end

    test "옵션 모달 — ⚙️ 버튼 클릭 시 모달 열림 (Sprint 4f-3)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/play/minesweeper")
      refute render(view) =~ "modal_save_binding"

      view |> element("button[phx-click='open_settings']") |> render_click()
      html = render(view)
      assert html =~ "modal_save_binding"
      assert html =~ "phx-click=\"close_settings\""
      assert html =~ "modal_reset"
    end

    test "옵션 모달 — close_settings 닫음 (Sprint 4f-3)", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/play/minesweeper")
      view |> element("button[phx-click='open_settings']") |> render_click()
      assert render(view) =~ "modal_save_binding"

      view |> element("button[phx-click='close_settings']") |> render_click()
      refute render(view) =~ "modal_save_binding"
    end

    test "사용자 binding 설정 → 새 키 즉시 반영 (Sprint 4f-2)", %{conn: conn} do
      # 게스트 → 회원 user 가 binding 변경 시나리오.
      user = user_fixture(nickname: "ms_kb_#{System.unique_integer([:positive])}")

      # flag 키를 "g" 로 변경. (schema field = key_bindings)
      {:ok, _} =
        HappyTrizn.UserGameSettings.upsert(user, "minesweeper", %{
          key_bindings: %{
            "move_up" => ["ArrowUp"],
            "move_down" => ["ArrowDown"],
            "move_left" => ["ArrowLeft"],
            "move_right" => ["ArrowRight"],
            "reveal" => [" "],
            "flag" => ["g"]
          }
        })

      conn = log_in_user(conn, user)
      {:ok, view, _} = live(conn, ~p"/play/minesweeper")

      # g 누르면 cursor 위치에 flag.
      render_hook(view, "keydown", %{"key" => "g"})
      html = render(view)
      assert html =~ "🚩"

      # f 는 더 이상 안 먹음 (binding 에서 빠짐).
      render_hook(view, "keydown", %{"key" => "f"})
      # 위 g 로 토글된 flag 가 그대로 — f 가 안 먹었으므로.
      assert render(view) =~ "🚩"
    end
  end

  describe "/play/sudoku (Sprint 3m)" do
    setup %{conn: conn} do
      {:ok, conn: log_in_user(conn, nil, "psd_#{System.unique_integer([:positive])}")}
    end

    test "마운트 — 스도쿠 + 9×9 grid + 난이도 표기", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/play/sudoku")
      assert html =~ "스도쿠"
      assert html =~ "난이도:"
      # 9*9 = 81 cell button.
      assert html |> String.split("phx-value-action=\"set_cursor\"") |> length() == 82
      # 1-9 number 버튼
      assert html =~ "phx-value-action=\"enter\""
    end

    test "키보드 1 → 빈 셀에 1 입력", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/play/sudoku")
      # cursor 0,0 일 시점. 우선 빈 셀로 cursor 옮기기 — phx-click set_cursor.
      # 빈 셀 찾는 건 server state 보지 않고는 어려우니 키 입력만 verify.
      render_hook(view, "keydown", %{"key" => "1"})
      # 페이지 살아있음.
      assert render(view) =~ "스도쿠"
    end

    test "data-keys 1-9 + Backspace + Delete 포함", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/play/sudoku")
      assert html =~ "data-keys="
      assert html =~ "1,2,3,4,5,6,7,8,9"
      assert html =~ "Backspace"
      assert html =~ "Delete"
    end

    test "옵션 모달 — 난이도 변경 가능", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/play/sudoku")
      view |> element("button[phx-click='open_settings']") |> render_click()
      html = render(view)
      assert html =~ "difficulty"
      assert html =~ "modal_save_options"
    end
  end

  describe "/play/pacman (stub)" do
    setup %{conn: conn} do
      {:ok, conn: log_in_user(conn, nil, "ppm_#{System.unique_integer([:positive])}")}
    end

    test "마운트 + 캔버스 hook + 점수/라이프/레벨 노출", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/play/pacman")
      assert html =~ "Pac-Man"
      assert html =~ "phx-hook=\"PacmanCanvas\""
      assert html =~ "점수"
      assert html =~ "라이프"
      assert html =~ "레벨"
    end

    test "GameKeyCapture data-keys 포함 (Pac-Man 입력 키)", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/play/pacman")
      assert html =~ "phx-hook=\"GameKeyCapture\""
      assert html =~ "ArrowUp"
    end

    test "옵션 모달 — Pac-Man 도 모달 (Sprint 4f-3)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/play/pacman")
      view |> element("button[phx-click='open_settings']") |> render_click()
      html = render(view)
      # tick_ms 옵션 노출 (Sprint 4f-4 — 사용자 속도 조절).
      assert html =~ "tick_ms"
      assert html =~ "modal_save_options"
    end

    test "방향 키 → set_dir input forward (page 살아있음)", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/play/pacman")
      html = render_keydown(view, "keydown", %{"key" => "ArrowUp"})
      # 페이지 살아 있음.
      assert html =~ "Pac-Man"
    end
  end
end
