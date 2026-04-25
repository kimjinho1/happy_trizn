defmodule HappyTriznWeb.Plugs.FetchCurrentUser do
  @moduledoc """
  Cookie 의 session token 을 보고 `conn.assigns.current_user` /
  `conn.assigns.current_session` / `conn.assigns.current_nickname` 세팅.

  로그인 안 됐고 게스트 세션도 없으면 셋 다 nil. router :browser 파이프라인에 위치.
  """

  import Plug.Conn

  alias HappyTrizn.Accounts
  alias HappyTrizn.Accounts.Session

  @cookie_name "_happy_trizn_session"
  @cookie_max_age 60 * 60 * 24 * 30
  # 30 days
  @cookie_options [
    max_age: @cookie_max_age,
    sign: false,
    encrypt: false,
    same_site: "Lax",
    http_only: true
  ]

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_cookies(conn, signed: [], encrypted: [])

    case Map.get(conn.req_cookies, @cookie_name) do
      nil ->
        assign_anonymous(conn)

      encoded ->
        with {:ok, raw} <- Session.decode_token(encoded),
             {user_or_nil, session} <- Accounts.get_session_by_token(raw) || :no_session do
          conn
          |> assign(:current_user, user_or_nil)
          |> assign(:current_session, session)
          |> assign(:current_nickname, session.nickname)
        else
          _ -> assign_anonymous(conn) |> delete_resp_cookie(@cookie_name)
        end
    end
  end

  @doc "외부에서 호출: 세션 cookie 심기."
  def put_session_cookie(conn, raw_token) do
    put_resp_cookie(conn, @cookie_name, Session.encode_token(raw_token), @cookie_options)
  end

  @doc "로그아웃 cookie 제거."
  def delete_session_cookie(conn), do: delete_resp_cookie(conn, @cookie_name)

  def cookie_name, do: @cookie_name

  defp assign_anonymous(conn) do
    conn
    |> assign(:current_user, nil)
    |> assign(:current_session, nil)
    |> assign(:current_nickname, nil)
  end
end
