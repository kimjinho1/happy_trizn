defmodule HappyTriznWeb.Live.Hooks.DmNotifications do
  @moduledoc """
  on_mount hook — 모든 LiveView 에 DM 실시간 알림 attach.

  - mount 시 `current_user` 있으면 `Messages.subscribe(user)`.
  - assign `:dm_unread_count` (top nav badge 갱신용).
  - `:dm_received` 도착 → unread_count assign + push_event "dm:notify"
    JS 가 받아 sound + toast + 페이지 타이틀 깜빡 처리.
  - `:dm_read` → unread_count 갱신.

  attach_hook 은 모든 LV process 에서 작동, on_mount 에서 한 번 attach.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, push_event: 3]

  alias HappyTrizn.Accounts.User
  alias HappyTrizn.Messages

  def on_mount(:default, _params, _session, socket) do
    user = socket.assigns[:current_user]

    socket =
      cond do
        is_nil(user) ->
          assign(socket, :dm_unread_count, 0)

        true ->
          if Phoenix.LiveView.connected?(socket), do: Messages.subscribe(user)

          socket
          |> assign(:dm_unread_count, Messages.unread_count(user))
          |> attach_hook(:dm_realtime, :handle_info, &handle_dm/2)
      end

    {:cont, socket}
  end

  # hook 은 :cont 반환 — LV 의 자체 handle_info 도 함께 호출되도록 (e.g. DmLive 가
  # 본인 thread 갱신). hook 은 글로벌 알림 (sound / toast / badge / title) 만 담당.
  defp handle_dm({:dm_received, msg}, socket) do
    user = socket.assigns[:current_user]

    if user && msg.to_user_id == user.id do
      count = Messages.unread_count(user)

      socket =
        socket
        |> assign(:dm_unread_count, count)
        |> push_event("dm:notify", %{
          from_user_id: msg.from_user_id,
          body: String.slice(msg.body || "", 0, 80),
          unread_count: count
        })

      {:cont, socket}
    else
      {:cont, socket}
    end
  end

  defp handle_dm({:dm_read, _payload}, socket) do
    user = socket.assigns[:current_user]
    count = if user, do: Messages.unread_count(user), else: 0
    {:cont, assign(socket, :dm_unread_count, count)}
  end

  defp handle_dm(_, socket), do: {:cont, socket}

  # Used 으로 마킹.
  _ = User
end
