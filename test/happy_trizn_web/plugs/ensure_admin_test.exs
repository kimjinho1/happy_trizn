defmodule HappyTriznWeb.Plugs.EnsureAdminTest do
  use HappyTriznWeb.ConnCase, async: false
  # async: false — session_secret 변경 test 가 다른 test 와 충돌 회피

  alias HappyTriznWeb.Plugs.EnsureAdmin

  describe "call/2" do
    test "admin cookie 없으면 /admin/login 리다이렉트", %{conn: conn} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> EnsureAdmin.call(EnsureAdmin.init([]))

      assert conn.halted
      assert redirected_to(conn) == ~p"/admin/login"
    end

    test "유효 admin 토큰 → current_admin assign", %{conn: conn} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> log_in_admin()
        |> EnsureAdmin.call(EnsureAdmin.init([]))

      refute conn.halted
      assert conn.assigns.current_admin == "admin"
    end

    test "만료된 토큰 → 리다이렉트", %{conn: conn} do
      cfg = Application.get_env(:happy_trizn, :admin)
      secret = Keyword.fetch!(cfg, :session_secret)

      # 음수 max_age 로 즉시 만료
      old_token =
        Phoenix.Token.sign(secret, "admin", "admin", signed_at: 0)

      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> Plug.Test.put_req_cookie(EnsureAdmin.cookie_name(), old_token)
        |> EnsureAdmin.call(EnsureAdmin.init([]))

      assert conn.halted
      assert redirected_to(conn) == ~p"/admin/login"
    end

    test "다른 secret 으로 sign 한 토큰 거부", %{conn: conn} do
      bad_token =
        Phoenix.Token.sign(String.duplicate("different_secret_", 4), "admin", "admin")

      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> Plug.Test.put_req_cookie(EnsureAdmin.cookie_name(), bad_token)
        |> EnsureAdmin.call(EnsureAdmin.init([]))

      assert conn.halted
      assert redirected_to(conn) == ~p"/admin/login"
    end

    test "session_secret 비어있으면 거부 (cookie 없어도 마찬가지)", %{conn: conn} do
      original = Application.get_env(:happy_trizn, :admin)
      Application.put_env(:happy_trizn, :admin, Keyword.put(original, :session_secret, ""))

      on_exit(fn -> Application.put_env(:happy_trizn, :admin, original) end)

      # cookie 없는 상태에서 직접 EnsureAdmin 호출 — secret="" 분기 + no_session 둘 다 거부
      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> EnsureAdmin.call(EnsureAdmin.init([]))

      assert conn.halted
      assert redirected_to(conn) == ~p"/admin/login"
    end
  end

  describe "put_admin_cookie/2 + delete_admin_cookie/1" do
    test "토큰 발급 + 검증 round-trip", %{conn: conn} do
      conn = EnsureAdmin.put_admin_cookie(conn, "admin")
      cookie_attrs = conn.resp_cookies[EnsureAdmin.cookie_name()]
      assert cookie_attrs.value
      assert cookie_attrs.max_age == 7200
      assert cookie_attrs.http_only
      assert cookie_attrs.same_site == "Strict"
    end

    test "delete_admin_cookie 시 max_age=0", %{conn: conn} do
      conn = EnsureAdmin.delete_admin_cookie(conn)
      assert conn.resp_cookies[EnsureAdmin.cookie_name()][:max_age] == 0
    end
  end
end
