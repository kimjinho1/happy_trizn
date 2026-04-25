defmodule HappyTriznWeb.AdminSessionController do
  use HappyTriznWeb, :controller

  alias HappyTriznWeb.Plugs.EnsureAdmin

  def new(conn, _params), do: render(conn, :new, error: nil)

  def create(conn, %{"admin" => %{"id" => id, "password" => password}}) do
    cfg = Application.get_env(:happy_trizn, :admin, [])
    expected_id = Keyword.get(cfg, :id, "admin")
    expected_hash = Keyword.get(cfg, :password_hash)
    ip = ip_string(conn)

    case HappyTrizn.RateLimit.hit("admin_login:" <> ip, 60_000, 5) do
      {:deny, _} ->
        render(conn, :new, error: "로그인 시도가 너무 많습니다. 1분 뒤 다시 시도하세요.")

      _ ->
        cond do
          is_nil(expected_hash) or expected_hash == "" ->
            render(conn, :new, error: "Admin 계정이 설정되지 않았습니다 (.env ADMIN_PASSWORD_HASH).")

          id == expected_id and Bcrypt.verify_pass(password, expected_hash) ->
            conn
            |> EnsureAdmin.put_admin_cookie(expected_id)
            |> redirect(to: ~p"/admin/users")

          true ->
            # timing-safe — 사용자 없을 때도 bcrypt 시간 일관
            Bcrypt.no_user_verify()
            render(conn, :new, error: "ID 또는 비밀번호가 올바르지 않습니다.")
        end
    end
  end

  def delete(conn, _params) do
    conn
    |> EnsureAdmin.delete_admin_cookie()
    |> redirect(to: ~p"/")
  end

  defp ip_string(conn) do
    conn.remote_ip |> :inet.ntoa() |> to_string()
  end
end
