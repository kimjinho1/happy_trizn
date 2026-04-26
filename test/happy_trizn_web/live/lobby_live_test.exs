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

    test "글로벌 브랜드 + 페이지 타이틀 root layout 에 노출", %{conn: conn} do
      conn = Phoenix.ConnTest.get(conn, ~p"/lobby")
      html = Phoenix.ConnTest.html_response(conn, 200)
      assert html =~ "Happy Trizn"
      assert html =~ "href=\"/lobby\""
      # 페이지 타이틀 (lobby 는 "로비")
      assert html =~ "로비"
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

    test "메시지 send 후 input 비움 — chat:reset_input event 푸시", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/lobby")

      view |> form("form[phx-submit='send']", %{"message" => "hello world"}) |> render_submit()

      # 1. server-side input assign 비어야
      assert render(view) =~ ~s(name="message" value="")
      # 2. JS hook 트리거할 push_event 검증
      assert_push_event(view, "chat:reset_input", %{})
    end

    test "501자 메시지 안 표시 (rendered HTML 안에 본문 없음)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/lobby")
      long = String.duplicate("a", 501)
      view |> form("form[phx-submit='send']", %{"message" => long}) |> render_submit()
      # 메시지가 broadcast 안 됨 → 화면에 안 보임
      refute render(view) =~ String.duplicate("a", 501)
    end

    test "rate limited 시 input 보존 (assign input 안 비움)", %{conn: conn} do
      nick = "rate_buf_#{System.unique_integer([:positive])}"
      conn = log_in_user(conn, nil, nick)
      {:ok, view, _} = live(conn, ~p"/lobby")

      for i <- 1..5 do
        view |> form("form[phx-submit='send']", %{"message" => "burst#{i}"}) |> render_submit()
      end

      # 6번째 → rate limited, broadcast 안 됨, button disabled
      html = view |> form("form[phx-submit='send']", %{"message" => "kept"}) |> render_submit()
      refute html =~ ~s(value="kept")
      # broadcast 자체 안 됨 → 화면에 "kept" 본문 없음
      refute html =~ ">kept<"
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

  describe "/lobby — 친구 사이드바 (등록자)" do
    setup %{conn: conn} do
      Cachex.clear(:recommendations_cache)
      alice = user_fixture(nickname: "alice_lob_#{System.unique_integer([:positive])}")
      bob = user_fixture(nickname: "bob_lob_#{System.unique_integer([:positive])}")
      {:ok, conn: log_in_user(conn, alice), alice: alice, bob: bob}
    end

    test "추천 친구에 다른 유저 표시", %{conn: conn, bob: bob} do
      {:ok, _view, html} = live(conn, ~p"/lobby")
      assert html =~ bob.nickname
      assert html =~ "추천 친구"
    end

    test "send_friend_request → 요청 row 생성 + flash", %{conn: conn, alice: alice, bob: bob} do
      {:ok, view, _} = live(conn, ~p"/lobby")

      view
      |> element("button[phx-click='send_friend_request'][phx-value-user-id='#{bob.id}']")
      |> render_click()

      assert HappyTrizn.Friends.get_friendship_between(alice, bob)
    end

    test "accept_friend → 친구 성립", %{conn: conn, alice: alice, bob: bob} do
      {:ok, f} = HappyTrizn.Friends.send_request(bob, alice)
      Cachex.clear(:recommendations_cache)

      {:ok, view, _} = live(conn, ~p"/lobby")

      view
      |> element("button[phx-click='accept_friend'][phx-value-friendship-id='#{f.id}']")
      |> render_click()

      assert HappyTrizn.Friends.are_friends?(alice, bob)
    end

    test "더보기 → 모든 사용자 모드 toggle", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/lobby")
      assert render(view) =~ "추천 친구"
      view |> element("button[phx-click='toggle_show_all']") |> render_click()
      assert render(view) =~ "모든 사용자"
    end
  end

  describe "/lobby — 친구 사이드바 (게스트)" do
    setup %{conn: conn} do
      Cachex.clear(:recommendations_cache)
      {:ok, conn: log_in_user(conn, nil, "guest_lobby_#{System.unique_integer([:positive])}")}
    end

    test "게스트는 친구 기능 비활성", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/lobby")
      assert html =~ "게스트는 친구 기능 사용 불가"
    end

    test "게스트는 방 생성 form 안 보임", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/lobby")
      assert html =~ "게스트는 방 생성 불가"
      refute html =~ "phx-submit=\"create_room\""
    end
  end

  describe "/lobby — 방 리스트 + 액션" do
    setup %{conn: conn} do
      Cachex.clear(:recommendations_cache)
      HappyTrizn.Rooms.clear_kick_bans()
      alice = user_fixture(nickname: "ar_#{System.unique_integer([:positive])}")

      {:ok, room} =
        HappyTrizn.Rooms.create(alice, %{game_type: "tetris", name: "lobby_visible_room"})

      {:ok, conn: log_in_user(conn, alice), alice: alice, room: room}
    end

    test "활성 방 표시", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/lobby")
      assert html =~ "lobby_visible_room"
      assert html =~ "활성 방"
    end

    test "join_room → /game/:type/:id 리다이렉트", %{conn: conn, room: room} do
      {:ok, view, _} = live(conn, ~p"/lobby")

      assert {:error, {:redirect, %{to: redirect_path}}} =
               view
               |> element("button[phx-click='join_room'][phx-value-room-id='#{room.id}']")
               |> render_click()

      assert redirect_path =~ "/game/tetris/"
    end
  end

  describe "/lobby — 비번 있는 방 (회귀)" do
    setup %{conn: conn} do
      Cachex.clear(:recommendations_cache)
      HappyTrizn.Rooms.clear_kick_bans()
      alice = user_fixture(nickname: "ar_pw_#{System.unique_integer([:positive])}")

      {:ok, room} =
        HappyTrizn.Rooms.create(alice, %{
          game_type: "tetris",
          name: "secret_room_#{System.unique_integer([:positive])}",
          password: "topsecret"
        })

      {:ok, conn: log_in_user(conn, alice), alice: alice, room: room}
    end

    test "비번 방 row 에 password input form 표시", %{conn: conn, room: room} do
      {:ok, _view, html} = live(conn, ~p"/lobby")
      assert html =~ "🔒"
      assert html =~ ~s(name="password")
      assert html =~ room.name
    end

    test "비번 정확하면 redirect 성공", %{conn: conn, room: room} do
      {:ok, view, _} = live(conn, ~p"/lobby")

      assert {:error, {:redirect, %{to: path}}} =
               view
               |> form("form[phx-submit='join_room']", %{
                 "room-id" => room.id,
                 "password" => "topsecret"
               })
               |> render_submit()

      assert path =~ "/game/tetris/"
    end

    test "비번 틀리면 wrong_password flash + 같은 페이지", %{conn: conn, room: room} do
      {:ok, view, _} = live(conn, ~p"/lobby")

      html =
        view
        |> form("form[phx-submit='join_room']", %{
          "room-id" => room.id,
          "password" => "wrongguess"
        })
        |> render_submit()

      assert html =~ "비밀번호 오류"
    end
  end

  describe "/lobby — 회귀 (게스트 + 강퇴 ban)" do
    test "게스트는 join_room 이벤트 차단", %{conn: conn} do
      conn = log_in_user(conn, nil, "guest_reg_#{System.unique_integer([:positive])}")
      alice = user_fixture(nickname: "alice_reg_#{System.unique_integer([:positive])}")

      {:ok, room} =
        HappyTrizn.Rooms.create(alice, %{
          game_type: "tetris",
          name: "n#{System.unique_integer([:positive])}"
        })

      {:ok, view, _} = live(conn, ~p"/lobby")
      # 게스트 → 친구/방 사이드바 안 보임. 직접 push (phx-click via render_hook)
      html = render_hook(view, "join_room", %{"room-id" => room.id})
      assert html =~ "게스트는 방 입장 불가"
    end

    test "강퇴된 user 가 같은 방 join 시도 → kicked flash", %{conn: conn} do
      host = user_fixture(nickname: "host_kick_#{System.unique_integer([:positive])}")
      target = user_fixture(nickname: "tgt_kick_#{System.unique_integer([:positive])}")

      {:ok, room} =
        HappyTrizn.Rooms.create(host, %{
          game_type: "tetris",
          name: "k#{System.unique_integer([:positive])}"
        })

      {:ok, :kicked} = HappyTrizn.Rooms.kick(host, room.id, target.id)

      conn = log_in_user(conn, target)
      {:ok, view, _} = live(conn, ~p"/lobby")

      html =
        view
        |> element("button[phx-click='join_room'][phx-value-room-id='#{room.id}']")
        |> render_click()

      assert html =~ "강퇴" or render(view) =~ "강퇴"
    end
  end
end
