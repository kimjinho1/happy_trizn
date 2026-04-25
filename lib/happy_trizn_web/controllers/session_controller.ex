defmodule HappyTriznWeb.SessionController do
  use HappyTriznWeb, :controller

  alias HappyTrizn.Accounts
  alias HappyTriznWeb.Plugs.FetchCurrentUser

  # ---- 등록자 로그인 ----

  def new(conn, _params), do: render(conn, :new, error: nil)

  def create(conn, %{"session" => %{"email" => email, "password" => password}}) do
    case Accounts.authenticate(email, password) do
      {:ok, user} ->
        {:ok, raw, _session} = Accounts.create_user_session(user)

        conn
        |> FetchCurrentUser.put_session_cookie(raw)
        |> put_flash(:info, "환영합니다, #{user.nickname}!")
        |> redirect(to: ~p"/")

      {:error, :banned} ->
        render(conn, :new, error: "이 계정은 차단되었습니다.")

      {:error, :invalid_credentials} ->
        render(conn, :new, error: "이메일 또는 비밀번호가 올바르지 않습니다.")
    end
  end

  # ---- 게스트 입장 (닉네임만) ----

  def guest(conn, %{"guest" => %{"nickname" => nickname}}) do
    case Accounts.create_guest_session(nickname || "") do
      {:ok, raw, _session} ->
        conn
        |> FetchCurrentUser.put_session_cookie(raw)
        |> put_flash(:info, "안녕하세요, #{String.trim(nickname)}!")
        |> redirect(to: ~p"/")

      {:error, :nickname_too_short} ->
        conn
        |> put_flash(:error, "닉네임은 2자 이상이어야 합니다.")
        |> redirect(to: ~p"/")

      {:error, :nickname_too_long} ->
        conn
        |> put_flash(:error, "닉네임은 32자 이하로 입력하세요.")
        |> redirect(to: ~p"/")

      {:error, _} ->
        conn
        |> put_flash(:error, "닉네임 입력이 잘못되었습니다.")
        |> redirect(to: ~p"/")
    end
  end

  # ---- 로그아웃 ----

  def delete(conn, _params) do
    if session = conn.assigns[:current_session] do
      Accounts.delete_session(session)
    end

    conn
    |> FetchCurrentUser.delete_session_cookie()
    |> put_flash(:info, "로그아웃되었습니다.")
    |> redirect(to: ~p"/")
  end
end
