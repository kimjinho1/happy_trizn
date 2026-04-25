defmodule HappyTriznWeb.AdminSessionControllerTest do
  use HappyTriznWeb.ConnCase, async: false
  # async: false — Hammer ETS 카운터 격리 위해

  describe "GET /admin/login" do
    test "admin 로그인 폼 렌더", %{conn: conn} do
      conn = get(conn, ~p"/admin/login")
      assert html_response(conn, 200) =~ "Admin"
      assert html_response(conn, 200) =~ "관리자"
    end
  end

  describe "POST /admin/login" do
    test "정확한 자격증명 → /admin/users 리다이렉트 + admin cookie", %{conn: conn} do
      conn = post(conn, ~p"/admin/login", admin: %{id: "admin", password: "admin1234"})
      assert redirected_to(conn) == ~p"/admin/users"

      cookie_name = HappyTriznWeb.Plugs.EnsureAdmin.cookie_name()
      assert Map.has_key?(conn.resp_cookies, cookie_name)
    end

    test "잘못된 비번 → 폼 + 에러", %{conn: conn} do
      conn = post(conn, ~p"/admin/login", admin: %{id: "admin", password: "wrong"})
      assert html_response(conn, 200) =~ "올바르지 않"
    end

    test "잘못된 ID → 폼 + 에러", %{conn: conn} do
      conn = post(conn, ~p"/admin/login", admin: %{id: "wrong_id", password: "admin1234"})
      assert html_response(conn, 200) =~ "올바르지 않"
    end

    test "5회 실패 → rate limit", %{conn: conn} do
      # 같은 IP (test 의 default 127.0.0.1) 로 5회 실패 후 6회째
      for _ <- 1..5 do
        post(conn, ~p"/admin/login", admin: %{id: "admin", password: "wrong"})
      end

      conn = post(conn, ~p"/admin/login", admin: %{id: "admin", password: "admin1234"})
      assert html_response(conn, 200) =~ "너무 많"
    end

    test "ADMIN_PASSWORD_HASH 누락 시 명확한 에러", %{conn: conn} do
      original = Application.get_env(:happy_trizn, :admin)
      Application.put_env(:happy_trizn, :admin, Keyword.put(original, :password_hash, nil))
      on_exit(fn -> Application.put_env(:happy_trizn, :admin, original) end)

      conn = post(conn, ~p"/admin/login", admin: %{id: "admin", password: "admin1234"})
      assert html_response(conn, 200) =~ "ADMIN_PASSWORD_HASH"
    end
  end

  describe "DELETE /admin/logout" do
    test "logout → / 리다이렉트 + admin cookie 삭제", %{conn: conn} do
      conn = delete(conn, ~p"/admin/logout")
      assert redirected_to(conn) == ~p"/"
      cookie_name = HappyTriznWeb.Plugs.EnsureAdmin.cookie_name()
      assert conn.resp_cookies[cookie_name][:max_age] == 0
    end
  end
end
