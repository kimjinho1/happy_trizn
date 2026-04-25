defmodule HappyTriznWeb.Plugs.FetchCurrentUserTest do
  use HappyTriznWeb.ConnCase, async: true

  alias HappyTriznWeb.Plugs.FetchCurrentUser
  alias HappyTrizn.Accounts
  alias HappyTrizn.Accounts.{Session, User}

  defp run_plug(conn) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> FetchCurrentUser.call(FetchCurrentUser.init([]))
  end

  describe "call/2" do
    test "쿠키 없으면 anonymous", %{conn: conn} do
      conn = run_plug(conn)
      assert conn.assigns.current_user == nil
      assert conn.assigns.current_session == nil
      assert conn.assigns.current_nickname == nil
    end

    test "유효 토큰 → user / session / nickname assign", %{conn: conn} do
      user = user_fixture()
      {:ok, raw, _session} = Accounts.create_user_session(user)
      encoded = Session.encode_token(raw)

      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> Plug.Test.put_req_cookie(FetchCurrentUser.cookie_name(), encoded)
        |> FetchCurrentUser.call(FetchCurrentUser.init([]))

      assert %User{id: id} = conn.assigns.current_user
      assert id == user.id
      assert conn.assigns.current_session
      assert conn.assigns.current_nickname == user.nickname
    end

    test "잘못된 토큰 → anonymous + cookie 삭제 응답 헤더", %{conn: conn} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> Plug.Test.put_req_cookie(FetchCurrentUser.cookie_name(), "garbage-not-base64")
        |> FetchCurrentUser.call(FetchCurrentUser.init([]))

      assert conn.assigns.current_user == nil
      assert conn.assigns.current_nickname == nil
      # cookie 무효화 — resp_cookies 에 max_age=0 있어야
      assert Map.has_key?(conn.resp_cookies, FetchCurrentUser.cookie_name())
    end

    test "게스트 세션 토큰 → user nil + nickname only", %{conn: conn} do
      {:ok, raw, _session} = Accounts.create_guest_session("guesty")
      encoded = Session.encode_token(raw)

      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> Plug.Test.put_req_cookie(FetchCurrentUser.cookie_name(), encoded)
        |> FetchCurrentUser.call(FetchCurrentUser.init([]))

      assert conn.assigns.current_user == nil
      assert conn.assigns.current_nickname == "guesty"
      assert conn.assigns.current_session
    end
  end

  describe "put_session_cookie/2 + delete_session_cookie/1" do
    test "cookie + plug session 둘 다 세팅", %{conn: conn} do
      raw = :crypto.strong_rand_bytes(32)

      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> FetchCurrentUser.put_session_cookie(raw)

      assert Map.has_key?(conn.resp_cookies, FetchCurrentUser.cookie_name())
      assert Plug.Conn.get_session(conn, :session_token) == Session.encode_token(raw)
    end

    test "delete 시 cookie + session 모두 정리", %{conn: conn} do
      raw = :crypto.strong_rand_bytes(32)

      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> FetchCurrentUser.put_session_cookie(raw)
        |> FetchCurrentUser.delete_session_cookie()

      # delete_resp_cookie → max_age=0 마킹
      cookie_attrs = conn.resp_cookies[FetchCurrentUser.cookie_name()]
      assert cookie_attrs[:max_age] == 0
      assert Plug.Conn.get_session(conn, :session_token) == nil
    end
  end
end
