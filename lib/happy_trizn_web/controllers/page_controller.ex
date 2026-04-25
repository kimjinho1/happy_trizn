defmodule HappyTriznWeb.PageController do
  use HappyTriznWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  @doc """
  로비 placeholder. Sprint 2 에서 LiveView (방 리스트, 친구 사이드바, 채팅) 로 교체.
  현재는 입장 확인만.
  """
  def lobby(conn, _params) do
    if conn.assigns.current_user || conn.assigns.current_nickname do
      render(conn, :lobby)
    else
      conn
      |> put_flash(:error, "먼저 입장하세요.")
      |> redirect(to: ~p"/")
    end
  end
end
