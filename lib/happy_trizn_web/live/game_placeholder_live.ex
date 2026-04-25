defmodule HappyTriznWeb.GamePlaceholderLive do
  @moduledoc """
  Sprint 3 GameLive 가 만들어지기 전까지 임시 placeholder.

  /game/:game_type/:room_id 또는 /play/:game_type 으로 들어오면 "준비 중"
  메시지 + 로비 복귀 링크.
  """

  use HappyTriznWeb, :live_view

  @impl true
  def mount(params, _session, socket) do
    nickname = socket.assigns[:current_nickname]

    if is_nil(nickname) do
      {:ok, socket |> put_flash(:error, "먼저 입장하세요.") |> redirect(to: ~p"/")}
    else
      {:ok,
       assign(socket,
         game_type: Map.get(params, "game_type"),
         room_id: Map.get(params, "room_id"),
         nickname: nickname
       )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center px-4">
      <div class="card bg-base-200 max-w-md w-full">
        <div class="card-body text-center space-y-4">
          <h1 class="text-2xl font-bold">{@game_type}</h1>
          <%= if @room_id do %>
            <p class="text-sm text-base-content/70">방 ID: <code>{@room_id}</code></p>
          <% end %>
          <div class="alert alert-info">
            <span>이 게임은 Sprint 3 에서 구현됩니다. 지금은 placeholder.</span>
          </div>
          <p class="text-xs text-base-content/60">{@nickname} 님 환영합니다.</p>
          <div class="card-actions justify-center">
            <.link navigate={~p"/lobby"} class="btn btn-primary btn-sm">로비로</.link>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
