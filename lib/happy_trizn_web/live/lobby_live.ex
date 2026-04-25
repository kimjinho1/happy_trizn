defmodule HappyTriznWeb.LobbyLive do
  @moduledoc """
  로비 LiveView. 글로벌 채팅 + 게임 카테고리 placeholder.

  Sprint 1: 글로벌 채팅 (Phoenix.PubSub).
  Sprint 2: 친구 사이드바, DM, 방 리스트, 게임 모듈 통합.
  """

  use HappyTriznWeb, :live_view

  alias Phoenix.PubSub
  alias HappyTrizn.RateLimit

  @chat_topic "chat:global"
  @max_message_length 500
  @max_messages_in_view 100

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns[:current_user]
    nickname = socket.assigns[:current_nickname]

    cond do
      is_nil(nickname) ->
        {:ok,
         socket
         |> put_flash(:error, "먼저 입장하세요.")
         |> redirect(to: ~p"/")}

      true ->
        if connected?(socket), do: PubSub.subscribe(HappyTrizn.PubSub, @chat_topic)

        {:ok,
         assign(socket,
           messages: [],
           input: "",
           user: user,
           nickname: nickname,
           rate_limited: false,
           max_message_length: @max_message_length
         )}
    end
  end

  @impl true
  def handle_event("send", %{"message" => body}, socket) do
    body = String.trim(body)
    nickname = socket.assigns.nickname

    cond do
      body == "" ->
        {:noreply, socket}

      String.length(body) > @max_message_length ->
        {:noreply, put_flash(socket, :error, "메시지는 #{@max_message_length}자 이하.")}

      true ->
        rate_key = "chat:" <> nickname

        case RateLimit.hit(rate_key, 10_000, 5) do
          {:deny, _} ->
            {:noreply,
             socket
             |> put_flash(:error, "메시지를 너무 빨리 보냅니다. 잠시 기다려주세요.")
             |> assign(:rate_limited, true)}

          _ ->
            msg = %{
              id: Ecto.UUID.generate(),
              nickname: nickname,
              body: body,
              ts: DateTime.utc_now(),
              registered: not is_nil(socket.assigns.user)
            }

            PubSub.broadcast(HappyTrizn.PubSub, @chat_topic, {:chat_message, msg})

            {:noreply, assign(socket, input: "", rate_limited: false)}
        end
    end
  end

  @impl true
  def handle_info({:chat_message, msg}, socket) do
    messages = Enum.take([msg | socket.assigns.messages], @max_messages_in_view)
    {:noreply, assign(socket, messages: messages)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen p-6 max-w-7xl mx-auto">
      <header class="flex items-center justify-between mb-6">
        <h1 class="text-2xl font-bold">Happy Trizn — 로비</h1>
        <div class="flex items-center gap-2">
          <span class="text-sm text-base-content/70">
            <%= if @user do %>
              <strong>{@nickname}</strong>
            <% else %>
              (게스트) <strong>{@nickname}</strong>
            <% end %>
          </span>
          <.link href={~p"/logout"} method="delete" class="btn btn-ghost btn-sm">로그아웃</.link>
        </div>
      </header>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
        <section class="card bg-base-200">
          <div class="card-body">
            <h2 class="card-title">멀티 게임</h2>
            <ul class="list-disc list-inside text-sm text-base-content/70">
              <li>Tetris (Sprint 3 예정)</li>
              <li>Bomberman</li>
              <li>Skribbl</li>
              <li>Snake.io</li>
            </ul>
          </div>
        </section>

        <section class="card bg-base-200">
          <div class="card-body">
            <h2 class="card-title">싱글 게임</h2>
            <ul class="list-disc list-inside text-sm text-base-content/70">
              <li>2048</li>
              <li>Minesweeper</li>
              <li>Pac-Man</li>
            </ul>
          </div>
        </section>

        <section class="card bg-base-200 lg:row-span-2">
          <div class="card-body">
            <h2 class="card-title">친구</h2>
            <p class="text-sm text-base-content/70">
              Sprint 2 에서 추가. 추천 친구, 요청/수락, DM.
            </p>
          </div>
        </section>

        <section class="card bg-base-200 lg:col-span-2">
          <div class="card-body">
            <h2 class="card-title">글로벌 채팅</h2>

            <div
              id="chat-messages"
              class="h-72 overflow-y-auto flex flex-col-reverse gap-1 bg-base-100 rounded p-3 text-sm"
              phx-hook="ChatScroll"
            >
              <%= if @messages == [] do %>
                <div class="text-base-content/40 text-center py-8">
                  첫 메시지를 보내보세요.
                </div>
              <% else %>
                <%= for msg <- @messages do %>
                  <div class="flex gap-2 items-baseline">
                    <span class="text-xs text-base-content/40">
                      {Calendar.strftime(msg.ts, "%H:%M")}
                    </span>
                    <span class={["font-semibold", if(msg.registered, do: "text-primary")]}>
                      {msg.nickname}
                    </span>
                    <span class="break-all">{msg.body}</span>
                  </div>
                <% end %>
              <% end %>
            </div>

            <form phx-submit="send" class="flex gap-2 mt-3">
              <input
                type="text"
                name="message"
                value={@input}
                placeholder="메시지..."
                class="input input-bordered flex-1"
                maxlength={@max_message_length}
                autocomplete="off"
              />
              <button type="submit" class="btn btn-primary" disabled={@rate_limited}>
                보내기
              </button>
            </form>
          </div>
        </section>
      </div>
    </div>
    """
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}
end
