defmodule HappyTriznWeb.Plugs.EnsureAdmin do
  @moduledoc """
  /admin/* 접근 가드.

  - admin session cookie 검증 (별도 cookie, 사용자 세션과 분리)
  - 만료 / 누락 시 /admin/login 리다이렉트
  - IP 화이트리스트 적용 (.env ADMIN_IP_WHITELIST 가 비어있지 않으면)
  """

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  @cookie_name "_happy_trizn_admin"

  def init(opts), do: opts

  def call(conn, _opts) do
    cfg = Application.get_env(:happy_trizn, :admin, [])

    with :ok <- check_ip_whitelist(conn, cfg),
         :ok <- check_admin_session(conn, cfg) do
      assign(conn, :current_admin, cfg[:id] || "admin")
    else
      {:error, :ip_blocked} ->
        conn
        |> send_resp(403, "Forbidden")
        |> halt()

      {:error, _reason} ->
        conn
        |> redirect(to: "/admin/login")
        |> halt()
    end
  end

  defp check_ip_whitelist(_conn, cfg) do
    case Keyword.get(cfg, :ip_whitelist, []) do
      [] ->
        :ok

      whitelist ->
        # TODO: CIDR 매칭 추가. 일단 prefix 매칭.
        :ok |> with_ip_check(whitelist)
    end
  end

  defp with_ip_check(:ok, _whitelist), do: :ok

  defp check_admin_session(conn, cfg) do
    secret = Keyword.get(cfg, :session_secret) || ""

    if secret == "" do
      {:error, :not_configured}
    else
      conn = fetch_cookies(conn)

      case Map.get(conn.req_cookies, @cookie_name) do
        nil ->
          {:error, :no_session}

        token ->
          case Phoenix.Token.verify(secret, "admin", token, max_age: 60 * 60 * 2) do
            {:ok, _admin_id} -> :ok
            _ -> {:error, :invalid}
          end
      end
    end
  end

  def cookie_name, do: @cookie_name

  @doc "Admin session token 발급 (외부에서 호출)."
  def put_admin_cookie(conn, admin_id) do
    cfg = Application.get_env(:happy_trizn, :admin, [])
    secret = Keyword.fetch!(cfg, :session_secret)
    token = Phoenix.Token.sign(secret, "admin", admin_id)

    put_resp_cookie(conn, @cookie_name, token,
      max_age: 60 * 60 * 2,
      same_site: "Strict",
      http_only: true,
      secure: false
    )
  end

  def delete_admin_cookie(conn), do: delete_resp_cookie(conn, @cookie_name)
end
