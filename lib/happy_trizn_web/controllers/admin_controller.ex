defmodule HappyTriznWeb.AdminController do
  use HappyTriznWeb, :controller

  alias HappyTrizn.Accounts
  alias HappyTrizn.Admin

  def index(conn, _params), do: redirect(conn, to: ~p"/admin/users")

  def users(conn, params) do
    status = Map.get(params, "status")
    page = String.to_integer(Map.get(params, "page", "1"))
    per = 50

    users = Accounts.list_users(status: status, limit: per, offset: (page - 1) * per)

    render(conn, :users,
      users: users,
      current_status: status,
      page: page,
      per_page: per
    )
  end

  def ban(conn, %{"id" => id}) do
    with %{} = user <- Accounts.get_user(id),
         {:ok, _} <- Accounts.ban_user(user),
         {:ok, _} <-
           Admin.log_action(conn.assigns.current_admin, "ban", target_user_id: user.id) do
      conn
      |> put_flash(:info, "#{user.nickname} 차단됨.")
      |> redirect(to: ~p"/admin/users")
    else
      _ ->
        conn
        |> put_flash(:error, "차단 실패.")
        |> redirect(to: ~p"/admin/users")
    end
  end

  def unban(conn, %{"id" => id}) do
    with %{} = user <- Accounts.get_user(id),
         {:ok, _} <- Accounts.unban_user(user),
         {:ok, _} <-
           Admin.log_action(conn.assigns.current_admin, "unban", target_user_id: user.id) do
      conn
      |> put_flash(:info, "#{user.nickname} 차단 해제됨.")
      |> redirect(to: ~p"/admin/users")
    else
      _ ->
        conn
        |> put_flash(:error, "차단 해제 실패.")
        |> redirect(to: ~p"/admin/users")
    end
  end
end
