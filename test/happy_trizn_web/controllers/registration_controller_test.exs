defmodule HappyTriznWeb.RegistrationControllerTest do
  use HappyTriznWeb.ConnCase, async: false

  describe "GET /register" do
    test "가입 폼 렌더", %{conn: conn} do
      conn = get(conn, ~p"/register")
      assert html_response(conn, 200) =~ "@trizn.kr"
      assert html_response(conn, 200) =~ "회원가입"
    end
  end

  describe "POST /register" do
    test "@trizn.kr 가입 성공 + 자동 로그인 + / 리다이렉트", %{conn: conn} do
      suffix = System.unique_integer([:positive])

      conn =
        post(conn, ~p"/register",
          user: %{
            email: "alice#{suffix}@trizn.kr",
            nickname: "alice#{suffix}",
            password: "supersecret"
          }
        )

      assert redirected_to(conn) == ~p"/"

      # 세션 cookie 심김
      cookie_name = HappyTriznWeb.Plugs.FetchCurrentUser.cookie_name()
      assert Map.has_key?(conn.resp_cookies, cookie_name)
    end

    test "외부 도메인 거부 + 폼 다시", %{conn: conn} do
      conn =
        post(conn, ~p"/register",
          user: %{
            email: "evil@gmail.com",
            nickname: "evil",
            password: "supersecret"
          }
        )

      assert html_response(conn, 200) =~ "must be a @trizn.kr address"
    end

    test "닉네임 중복 거부", %{conn: conn} do
      _ = user_fixture(nickname: "dup_nick", email: "first@trizn.kr")

      conn =
        post(conn, ~p"/register",
          user: %{email: "second@trizn.kr", nickname: "dup_nick", password: "hello12345"}
        )

      assert html_response(conn, 200) =~ "has already been taken"
    end

    test "비번 8자 미만 거부", %{conn: conn} do
      conn =
        post(conn, ~p"/register",
          user: %{email: "short@trizn.kr", nickname: "shorty", password: "abc"}
        )

      assert html_response(conn, 200) =~ "should be at least 8 character"
    end
  end

end
