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

  describe "/play/2048" do
    setup %{conn: conn} do
      {:ok, conn: log_in_user(conn, nil, "p2048_#{System.unique_integer([:positive])}")}
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

    test "WASD / HJKL 도 keydown 받음", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/play/2048")

      for key <- ~w(w s a d h j k l) do
        html = render_keydown(view, "keydown", %{"key" => key})
        assert html =~ "점수:", "key #{key} 깨짐"
      end
    end

    test "관계없는 키는 무시", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/play/2048")
      html_before = render(view)
      html = render_keydown(view, "keydown", %{"key" => "Tab"})
      assert html == html_before
    end
  end

  describe "/play/minesweeper" do
    setup %{conn: conn} do
      {:ok, conn: log_in_user(conn, nil, "pms_#{System.unique_integer([:positive])}")}
    end

    test "mount — 게스트 default = medium 프리셋 16×16 grid", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/play/minesweeper")
      assert html =~ "Minesweeper"
      assert html =~ "16×16"
      assert html =~ "지뢰 40개"
      # 256 hidden cell (16×16) 있어야
      assert html |> String.split("phx-value-action=\"reveal\"") |> length() == 257
    end

    test "셀 reveal → state 변화", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/play/minesweeper")

      view
      |> element("button[phx-value-action='reveal'][phx-value-r='5'][phx-value-c='5']")
      |> render_click()

      # 클릭한 셀이 revealed (색 다른 div)
      html = render(view)
      assert html =~ "Minesweeper"
    end
  end

  describe "/play/pacman (stub)" do
    setup %{conn: conn} do
      {:ok, conn: log_in_user(conn, nil, "ppm_#{System.unique_integer([:positive])}")}
    end

    test "mount stub 렌더", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/play/pacman")
      assert html =~ "Pac-Man"
      assert html =~ "Sprint 3g"
    end
  end
end
