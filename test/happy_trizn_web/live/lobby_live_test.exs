defmodule HappyTriznWeb.LobbyLiveTest do
  use HappyTriznWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "/lobby — 인증 가드" do
    test "비입장 사용자는 / 로 리다이렉트", %{conn: conn} do
      conn = Plug.Test.init_test_session(conn, %{})
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/lobby")
    end
  end

  describe "/lobby — 게스트 입장" do
    setup %{conn: conn} do
      {:ok, conn: log_in_user(conn, nil, "guest_one")}
    end

    test "마운트 성공 + 닉네임 표시", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/lobby")
      assert html =~ "guest_one"
      assert html =~ "글로벌 채팅"
    end

    test "메시지 보내기 → 화면에 표시", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/lobby")

      view |> form("form[phx-submit='send']", %{"message" => "안녕하세요"}) |> render_submit()
      assert render(view) =~ "안녕하세요"
      assert render(view) =~ "guest_one"
    end

    test "빈 메시지 무시", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/lobby")
      view |> form("form[phx-submit='send']", %{"message" => "   "}) |> render_submit()
      refute render(view) =~ "<span class=\"break-all\">"
    end

    test "501자 메시지 안 표시 (rendered HTML 안에 본문 없음)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/lobby")
      long = String.duplicate("a", 501)
      view |> form("form[phx-submit='send']", %{"message" => long}) |> render_submit()
      # 메시지가 broadcast 안 됨 → 화면에 안 보임
      refute render(view) =~ String.duplicate("a", 501)
    end
  end

  describe "/lobby — 등록자 입장" do
    setup %{conn: conn} do
      user = user_fixture(nickname: "alice_reg")
      {:ok, conn: log_in_user(conn, user), user: user}
    end

    test "닉네임 + 이메일 노출 안 함", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/lobby")
      assert html =~ "alice_reg"
      refute html =~ "alice_reg@trizn.kr"
    end

    test "메시지 broadcast 가 다른 LiveView 에 도달", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/lobby")

      # 두번째 사용자 LiveView
      conn2 =
        Phoenix.ConnTest.build_conn()
        |> log_in_user(user_fixture(nickname: "bob_reg"))

      {:ok, view2, _} = live(conn2, ~p"/lobby")

      view |> form("form[phx-submit='send']", %{"message" => "from alice"}) |> render_submit()

      # PubSub broadcast → view2 도 메시지 받음
      assert render(view2) =~ "from alice"
      _ = user
    end
  end

  describe "/lobby — 도배 방지" do
    setup %{conn: conn} do
      nick = "spammer_#{System.unique_integer([:positive])}"
      {:ok, conn: log_in_user(conn, nil, nick), nick: nick}
    end

    test "10초에 5메시지 초과 시 6번째 메시지는 broadcast 안 됨 + button disabled", %{conn: conn, nick: _nick} do
      {:ok, view, _} = live(conn, ~p"/lobby")

      for i <- 1..5 do
        view |> form("form[phx-submit='send']", %{"message" => "msg#{i}"}) |> render_submit()
      end

      view |> form("form[phx-submit='send']", %{"message" => "over_quota"}) |> render_submit()
      html = render(view)
      # 6번째 메시지 본문은 broadcast 안 됨 (자기 자신 화면에도 안 추가)
      refute html =~ "over_quota"
      # button 도 disabled (rate_limited true)
      assert html =~ ~s(disabled)
    end
  end
end
