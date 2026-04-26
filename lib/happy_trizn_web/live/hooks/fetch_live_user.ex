defmodule HappyTriznWeb.Live.Hooks.FetchLiveUser do
  @moduledoc """
  LiveView `on_mount` hook — 일반 controller 의 FetchCurrentUser plug 와 대응.

  Phoenix session cookie 안의 session_token (FetchCurrentUser plug 가 심음) 으로
  사용자/세션을 다시 조회해 socket.assigns 에 current_user / current_session /
  current_nickname 세팅. 토큰 없거나 만료 / banned 면 anonymous.
  """

  import Phoenix.Component, only: [assign: 2]

  alias HappyTrizn.Accounts
  alias HappyTrizn.Accounts.Session
  alias HappyTriznWeb.Plugs.FetchCurrentUser
  alias HappyTriznWeb.Presence

  def on_mount(:default, _params, session, socket) do
    encoded = session["session_token"] || session[:session_token]

    {user, sess, nickname} =
      case encoded && Session.decode_token(encoded) do
        {:ok, raw} ->
          case Accounts.get_session_by_token(raw) do
            {u, s} -> {u, s, s.nickname}
            _ -> {nil, nil, nil}
          end

        _ ->
          {nil, nil, nil}
      end

    # Sprint 4g — 로그인 사용자의 LV 접속 시 presence track. 연결 종료 시 자동 해제.
    if user && Phoenix.LiveView.connected?(socket) do
      Presence.track_user(self(), user.id)
    end

    {:cont, assign(socket, current_user: user, current_session: sess, current_nickname: nickname)}
  end

  # FetchCurrentUser plug의 cookie_name 노출은 더 이상 필요없음. session_token key 사용.
  _ = FetchCurrentUser
end
