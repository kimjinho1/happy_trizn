defmodule HappyTriznWeb.AdminControllerTest do
  use HappyTriznWeb.ConnCase, async: true

  alias HappyTrizn.Accounts
  alias HappyTrizn.Admin

  describe "GET /admin (without admin auth)" do
    test "비-admin 은 /admin/login 리다이렉트", %{conn: conn} do
      conn = get(conn, ~p"/admin/users")
      assert redirected_to(conn) == ~p"/admin/login"
    end

    test "ban POST 도 차단", %{conn: conn} do
      user = user_fixture()
      conn = post(conn, ~p"/admin/users/#{user.id}/ban")
      assert redirected_to(conn) == ~p"/admin/login"
    end
  end

  describe "GET /admin/users (with admin)" do
    setup %{conn: conn} do
      _ = user_fixture(nickname: "alice", email: "alice@trizn.kr")
      _ = user_fixture(nickname: "bob", email: "bob@trizn.kr")
      {:ok, conn: log_in_admin(conn)}
    end

    test "사용자 목록 페이지 + 닉네임 표시", %{conn: conn} do
      conn = get(conn, ~p"/admin/users")
      body = html_response(conn, 200)
      assert body =~ "alice"
      assert body =~ "bob"
      assert body =~ "사용자 관리"
    end

    test "active 필터", %{conn: conn} do
      conn = get(conn, ~p"/admin/users?status=active")
      assert html_response(conn, 200) =~ "alice"
    end

    test "/admin → /admin/users 리다이렉트", %{conn: conn} do
      conn = get(conn, ~p"/admin")
      assert redirected_to(conn) == ~p"/admin/users"
    end
  end

  describe "POST /admin/users/:id/ban" do
    setup %{conn: conn} do
      user = user_fixture()
      {:ok, conn: log_in_admin(conn), user: user}
    end

    test "ban → status banned + 감사 로그 + 리다이렉트", %{conn: conn, user: user} do
      conn = post(conn, ~p"/admin/users/#{user.id}/ban")
      assert redirected_to(conn) == ~p"/admin/users"

      reloaded = Accounts.get_user(user.id)
      assert reloaded.status == "banned"

      logs = Admin.list_actions(action: "ban")
      assert Enum.any?(logs, &(&1.target_user_id == user.id))
    end

    test "ban 시 active 세션 무효화", %{conn: conn, user: user} do
      {:ok, raw, _s} = Accounts.create_user_session(user)
      assert Accounts.get_session_by_token(raw) != nil

      _ = post(conn, ~p"/admin/users/#{user.id}/ban")
      assert Accounts.get_session_by_token(raw) == nil
    end

    test "없는 user id 는 admin 페이지 + error flash", %{conn: conn} do
      conn = post(conn, ~p"/admin/users/00000000-0000-0000-0000-000000000000/ban")
      assert redirected_to(conn) == ~p"/admin/users"
    end
  end

  describe "POST /admin/users/:id/unban" do
    setup %{conn: conn} do
      user = user_fixture()
      {:ok, _} = Accounts.ban_user(user)
      {:ok, conn: log_in_admin(conn), user: user}
    end

    test "unban → status active + 감사 로그", %{conn: conn, user: user} do
      conn = post(conn, ~p"/admin/users/#{user.id}/unban")
      assert redirected_to(conn) == ~p"/admin/users"

      reloaded = Accounts.get_user(user.id)
      assert reloaded.status == "active"

      logs = Admin.list_actions(action: "unban")
      assert Enum.any?(logs, &(&1.target_user_id == user.id))
    end
  end
end
