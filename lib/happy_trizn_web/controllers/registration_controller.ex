defmodule HappyTriznWeb.RegistrationController do
  use HappyTriznWeb, :controller

  alias HappyTrizn.Accounts
  alias HappyTrizn.Accounts.User
  alias HappyTriznWeb.Plugs.FetchCurrentUser

  def new(conn, _params) do
    changeset = Ecto.Changeset.change(%User{})
    render(conn, :new, changeset: changeset)
  end

  def create(conn, %{"user" => user_params}) do
    ip = ip_string(conn)

    case HappyTrizn.RateLimit.hit("register:" <> ip, 60_000, 3) do
      {:deny, _} ->
        conn
        |> put_flash(:error, "Too many sign-up attempts. Try again in a minute.")
        |> redirect(to: ~p"/register")

      _ ->
        case Accounts.register_user(user_params) do
          {:ok, user} ->
            {:ok, raw, _session} = Accounts.create_user_session(user)

            conn
            |> FetchCurrentUser.put_session_cookie(raw)
            |> put_flash(:info, "환영합니다, #{user.nickname}!")
            |> redirect(to: ~p"/")

          {:error, %Ecto.Changeset{} = changeset} ->
            render(conn, :new, changeset: changeset)
        end
    end
  end

  defp ip_string(conn) do
    conn.remote_ip |> :inet.ntoa() |> to_string()
  end
end
