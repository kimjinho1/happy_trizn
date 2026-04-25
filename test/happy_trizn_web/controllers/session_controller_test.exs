defmodule HappyTriznWeb.SessionControllerTest do
  use HappyTriznWeb.ConnCase, async: true

  describe "GET /login" do
    test "로그인 폼 렌더", %{conn: conn} do
      conn = get(conn, ~p"/login")
      assert html_response(conn, 200) =~ "로그인"
      assert html_response(conn, 200) =~ "@trizn.kr"
    end
  end

  describe "POST /login" do
    setup do
      {:ok, user: user_fixture()}
    end

    test "정확한 자격증명 → / 리다이렉트 + 세션 cookie", %{conn: conn, user: user} do
      conn = post(conn, ~p"/login", session: %{email: user.email, password: "hello12345"})
      assert redirected_to(conn) == ~p"/"

      cookie_name = HappyTriznWeb.Plugs.FetchCurrentUser.cookie_name()
      assert Map.has_key?(conn.resp_cookies, cookie_name)
    end

    test "잘못된 비번 → 폼 + 에러", %{conn: conn, user: user} do
      conn = post(conn, ~p"/login", session: %{email: user.email, password: "wrong_password"})
      assert html_response(conn, 200) =~ "올바르지 않"
    end

    test "banned 계정 → 차단 메시지", %{conn: conn, user: user} do
      {:ok, _} = HappyTrizn.Accounts.ban_user(user)
      conn = post(conn, ~p"/login", session: %{email: user.email, password: "hello12345"})
      assert html_response(conn, 200) =~ "차단"
    end

    test "없는 이메일 → 보통 invalid", %{conn: conn} do
      conn = post(conn, ~p"/login", session: %{email: "ghost@trizn.kr", password: "anything"})
      assert html_response(conn, 200) =~ "올바르지 않"
    end
  end

  describe "POST /guest" do
    test "닉네임으로 게스트 입장 → / 리다이렉트", %{conn: conn} do
      conn = post(conn, ~p"/guest", guest: %{nickname: "casual_user"})
      assert redirected_to(conn) == ~p"/"

      cookie_name = HappyTriznWeb.Plugs.FetchCurrentUser.cookie_name()
      assert Map.has_key?(conn.resp_cookies, cookie_name)
    end

    test "1자 닉네임 거부 + flash + / 리다이렉트", %{conn: conn} do
      conn = post(conn, ~p"/guest", guest: %{nickname: "a"})
      assert redirected_to(conn) == ~p"/"
    end

    test "33자 닉네임 거부", %{conn: conn} do
      long = String.duplicate("x", 33)
      conn = post(conn, ~p"/guest", guest: %{nickname: long})
      assert redirected_to(conn) == ~p"/"
    end

    test "공백 trim 후 입장", %{conn: conn} do
      conn = post(conn, ~p"/guest", guest: %{nickname: "   trim_me   "})
      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "DELETE /logout" do
    test "로그아웃 → cookie 삭제 + / 리다이렉트", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      conn = delete(conn, ~p"/logout")
      assert redirected_to(conn) == ~p"/"

      cookie_name = HappyTriznWeb.Plugs.FetchCurrentUser.cookie_name()
      assert conn.resp_cookies[cookie_name][:max_age] == 0
    end

    test "비로그인 상태 logout 도 / 리다이렉트", %{conn: conn} do
      conn = delete(conn, ~p"/logout")
      assert redirected_to(conn) == ~p"/"
    end
  end
end
