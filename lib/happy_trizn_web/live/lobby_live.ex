defmodule HappyTriznWeb.LobbyLive do
  @moduledoc """
  로비 LiveView. 글로벌 채팅 + 친구 사이드바 + 방 리스트 + 게임 카테고리.

  Sprint 1: 글로벌 채팅.
  Sprint 2: 친구 추천/요청/수락, 방 생성/입장/강퇴, 친구 알림 PubSub.
  """

  use HappyTriznWeb, :live_view

  require Logger
  alias Phoenix.PubSub
  alias HappyTrizn.{RateLimit, Friends, Rooms}
  alias HappyTrizn.Games.Registry, as: GameRegistry

  @chat_topic "chat:global"
  @max_message_length 500
  @max_messages_in_view 100

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns[:current_user]
    nickname = socket.assigns[:current_nickname]

    cond do
      is_nil(nickname) ->
        {:ok, socket |> put_flash(:error, "먼저 입장하세요.") |> redirect(to: ~p"/")}

      true ->
        if connected?(socket) do
          PubSub.subscribe(HappyTrizn.PubSub, @chat_topic)
          Rooms.subscribe_lobby()
          if user, do: Friends.subscribe(user)
        end

        {:ok,
         socket
         |> assign(:messages, [])
         |> assign(:input, "")
         |> assign(:user, user)
         |> assign(:nickname, nickname)
         |> assign(:rate_limited, false)
         |> assign(:max_message_length, @max_message_length)
         |> assign(:show_all_users, false)
         |> assign(:games_multi, GameRegistry.list_multi())
         |> assign(:games_single, GameRegistry.list_single())
         |> load_friends_data()
         |> load_rooms()}
    end
  end

  # ============================================================================
  # Chat
  # ============================================================================

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
        case RateLimit.hit("chat:" <> nickname, 10_000, 5) do
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

            HappyTrizn.Chat.log_message(msg, "lobby")
            PubSub.broadcast(HappyTrizn.PubSub, @chat_topic, {:chat_message, msg})

            # 클라이언트 input value clear — morphdom 이 typed value 안 건드리므로
            # 명시적 push_event 로 JS hook 이 reset.
            {:noreply,
             socket
             |> assign(input: "", rate_limited: false)
             |> push_event("chat:reset_input", %{})}
        end
    end
  end

  # ============================================================================
  # Friends
  # ============================================================================

  def handle_event("toggle_show_all", _, socket) do
    {:noreply,
     assign(socket, show_all_users: not socket.assigns.show_all_users) |> load_friends_data()}
  end

  def handle_event("send_friend_request", %{"user-id" => target_id}, socket) do
    with %{} = me <- socket.assigns.user,
         target when not is_nil(target) <- HappyTrizn.Accounts.get_user(target_id) do
      case Friends.send_request(me, target) do
        {:ok, :already_pending} ->
          {:noreply, put_flash(socket, :info, "이미 요청 보냄")}

        {:ok, :already_accepted} ->
          {:noreply, put_flash(socket, :info, "이미 친구")}

        {:ok, _friendship} ->
          {:noreply,
           socket |> put_flash(:info, "친구 요청 보냄: #{target.nickname}") |> load_friends_data()}

        {:error, :self} ->
          {:noreply, put_flash(socket, :error, "자기 자신은 추가 불가")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "요청 실패")}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "게스트는 친구 추가 불가")}
    end
  end

  def handle_event("accept_friend", %{"friendship-id" => fid}, socket) do
    with %{} = me <- socket.assigns.user,
         %{} = f <- Friends.get_friendship(fid),
         {:ok, _} <- Friends.accept(me, f) do
      {:noreply, socket |> put_flash(:info, "친구 수락") |> load_friends_data()}
    else
      _ -> {:noreply, put_flash(socket, :error, "수락 실패")}
    end
  end

  def handle_event("reject_friend", %{"friendship-id" => fid}, socket) do
    with %{} = me <- socket.assigns.user,
         %{} = f <- Friends.get_friendship(fid),
         {:ok, _} <- Friends.reject(me, f) do
      {:noreply, socket |> put_flash(:info, "친구 요청 거절") |> load_friends_data()}
    else
      _ -> {:noreply, put_flash(socket, :error, "거절 실패")}
    end
  end

  # ============================================================================
  # Rooms
  # ============================================================================

  def handle_event("create_room", params, socket) do
    case socket.assigns.user do
      nil ->
        {:noreply, put_flash(socket, :error, "게스트는 방 생성 불가. @trizn.kr 가입 필요.")}

      host ->
        game_type = Map.fetch!(params, "game_type")
        name = Map.fetch!(params, "name")
        password = Map.get(params, "password", "") |> String.trim()
        max_players = Map.get(params, "max_players", "4") |> String.to_integer()

        cond do
          not GameRegistry.valid_slug?(game_type) ->
            {:noreply, put_flash(socket, :error, "잘못된 게임 타입")}

          true ->
            attrs = %{
              game_type: game_type,
              name: name,
              password: password,
              max_players: max_players
            }

            case Rooms.create(host, attrs) do
              {:ok, room} ->
                {:noreply, redirect(socket, to: ~p"/game/#{room.game_type}/#{room.id}")}

              {:error, _cs} ->
                {:noreply, put_flash(socket, :error, "방 생성 실패")}
            end
        end
    end
  end

  def handle_event("join_room", %{"room-id" => room_id} = params, socket) do
    Logger.info(
      "[lobby] join_room user=#{inspect(socket.assigns.user && socket.assigns.user.id)} room=#{room_id}"
    )

    case socket.assigns.user do
      nil ->
        {:noreply, put_flash(socket, :error, "게스트는 방 입장 불가. @trizn.kr 가입 필요.")}

      user ->
        password = Map.get(params, "password")

        case Rooms.join(user, room_id, password) do
          {:ok, room} -> {:noreply, redirect(socket, to: ~p"/game/#{room.game_type}/#{room.id}")}
          {:error, :wrong_password} -> {:noreply, put_flash(socket, :error, "비밀번호 오류")}
          {:error, :kicked} -> {:noreply, put_flash(socket, :error, "강퇴된 방 (5분 ban)")}
          {:error, :closed} -> {:noreply, put_flash(socket, :error, "방 종료됨")}
          {:error, :not_found} -> {:noreply, put_flash(socket, :error, "방 없음")}
        end
    end
  end

  # ============================================================================
  # PubSub handle_info
  # ============================================================================

  @impl true
  def handle_info({:chat_message, msg}, socket) do
    messages = Enum.take([msg | socket.assigns.messages], @max_messages_in_view)
    {:noreply, assign(socket, messages: messages)}
  end

  def handle_info({:friend_request_received, %{from: from}}, socket) do
    {:noreply, socket |> put_flash(:info, "#{from} 님이 친구 요청") |> load_friends_data()}
  end

  def handle_info({:friend_request_accepted, %{by: by}}, socket) do
    {:noreply, socket |> put_flash(:info, "#{by} 님이 친구 수락") |> load_friends_data()}
  end

  def handle_info({:room_created, _room}, socket), do: {:noreply, load_rooms(socket)}
  def handle_info({:room_closed, _room}, socket), do: {:noreply, load_rooms(socket)}

  def handle_info(_, socket), do: {:noreply, socket}

  # ============================================================================
  # Helpers
  # ============================================================================

  defp load_friends_data(socket) do
    user = socket.assigns.user

    if user do
      assign(socket,
        friends: Friends.list_friends(user),
        pending_received: Friends.list_pending_received(user),
        recommend: Friends.recommend(user, 10),
        all_users:
          if(socket.assigns.show_all_users,
            do: HappyTrizn.Accounts.list_users(limit: 100),
            else: []
          )
      )
    else
      assign(socket,
        friends: [],
        pending_received: [],
        recommend: [],
        all_users: []
      )
    end
  end

  defp load_rooms(socket) do
    assign(socket, rooms: Rooms.list_open(limit: 50))
  end

  # ============================================================================
  # Render
  # ============================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
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
          <.link navigate={~p"/history"} class="btn btn-ghost btn-sm" title="내 기록">
            🏆 기록
          </.link>
          <.link navigate={~p"/settings/games"} class="btn btn-ghost btn-sm" title="게임 옵션">
            ⚙️ 옵션
          </.link>
          <.link href={~p"/logout"} method="delete" class="btn btn-ghost btn-sm">로그아웃</.link>
        </div>
      </header>

      <div class="grid grid-cols-1 lg:grid-cols-4 gap-4">
        <!-- 왼쪽: 게임 카테고리 + 방 생성 -->
        <section class="card bg-base-200 lg:col-span-1">
          <div class="card-body">
            <h2 class="card-title text-base">방 만들기</h2>
            <%= if @user do %>
              <form phx-submit="create_room" class="space-y-2">
                <select name="game_type" class="select select-bordered select-sm w-full" required>
                  <option value="">게임 선택</option>
                  <%= for g <- @games_multi do %>
                    <option value={g.slug}>{g.name} ({g.mode})</option>
                  <% end %>
                </select>
                <input
                  type="text"
                  name="name"
                  placeholder="방 이름"
                  class="input input-bordered input-sm w-full"
                  required
                  maxlength="64"
                />
                <input
                  type="password"
                  name="password"
                  placeholder="비번 (선택)"
                  class="input input-bordered input-sm w-full"
                />
                <input
                  type="number"
                  name="max_players"
                  value="4"
                  min="2"
                  max="16"
                  class="input input-bordered input-sm w-full"
                />
                <button type="submit" class="btn btn-primary btn-sm w-full">생성</button>
              </form>
            <% else %>
              <p class="text-xs text-base-content/50">
                게스트는 방 생성 불가. <.link href={~p"/register"} class="link">@trizn.kr 가입</.link>
              </p>
            <% end %>

            <div class="divider text-xs my-2">싱글</div>
            <ul class="text-sm space-y-1">
              <%= for g <- @games_single do %>
                <li>
                  <.link navigate={~p"/play/#{g.slug}"} class="link">{g.name}</.link>
                </li>
              <% end %>
              <%= if @games_single == [] do %>
                <li class="text-base-content/40 text-xs">Sprint 3 예정</li>
              <% end %>
            </ul>
          </div>
        </section>
        
    <!-- 가운데: 방 리스트 + 채팅 -->
        <section class="lg:col-span-2 space-y-4">
          <div class="card bg-base-200">
            <div class="card-body">
              <h2 class="card-title text-base">활성 방 ({length(@rooms)})</h2>
              <%= if @rooms == [] do %>
                <p class="text-base-content/50 text-sm py-4 text-center">열린 방 없음. 직접 만들어보세요.</p>
              <% else %>
                <div class="space-y-1 max-h-48 overflow-y-auto">
                  <%= for room <- @rooms do %>
                    <div class="flex items-center justify-between p-2 bg-base-100 rounded text-sm">
                      <div class="flex items-center gap-2">
                        <span class="badge badge-sm">{room.game_type}</span>
                        <span class="font-semibold">{room.name}</span>
                        <%= if room.password_hash do %>
                          <span class="text-xs" title="비밀번호 방">🔒</span>
                        <% end %>
                      </div>
                      <%= if room.password_hash do %>
                        <form phx-submit="join_room" class="flex items-center gap-1">
                          <input type="hidden" name="room-id" value={room.id} />
                          <input
                            type="password"
                            name="password"
                            placeholder="비번"
                            class="input input-bordered input-xs w-24"
                            required
                          />
                          <button type="submit" class="btn btn-xs btn-primary">입장</button>
                        </form>
                      <% else %>
                        <button
                          phx-click="join_room"
                          phx-value-room-id={room.id}
                          class="btn btn-xs btn-primary"
                        >
                          입장
                        </button>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>

          <div class="card bg-base-200">
            <div class="card-body">
              <h2 class="card-title text-base">글로벌 채팅</h2>
              <div
                id="chat-messages"
                class="h-64 overflow-y-auto flex flex-col-reverse gap-1 bg-base-100 rounded p-3 text-sm"
                phx-hook="ChatScroll"
              >
                <%= if @messages == [] do %>
                  <div class="text-base-content/40 text-center py-8">첫 메시지를 보내보세요.</div>
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
              <form id="chat-form" phx-submit="send" phx-hook="ChatReset" class="flex gap-2 mt-3">
                <input
                  type="text"
                  name="message"
                  value={@input}
                  placeholder="메시지..."
                  class="input input-bordered input-sm flex-1"
                  maxlength={@max_message_length}
                  autocomplete="off"
                />
                <button type="submit" class="btn btn-primary btn-sm" disabled={@rate_limited}>
                  보내기
                </button>
              </form>
            </div>
          </div>
        </section>
        
    <!-- 오른쪽: 친구 사이드바 -->
        <section class="card bg-base-200 lg:col-span-1">
          <div class="card-body">
            <h2 class="card-title text-base">친구</h2>

            <%= cond do %>
              <% is_nil(@user) -> %>
                <p class="text-xs text-base-content/50">
                  게스트는 친구 기능 사용 불가. <.link href={~p"/register"} class="link">@trizn.kr 가입</.link>
                </p>
              <% true -> %>
                <%= if @pending_received != [] do %>
                  <div class="text-xs font-semibold mt-2">받은 요청 ({length(@pending_received)})</div>
                  <%= for f <- @pending_received do %>
                    <div class="flex items-center justify-between text-sm py-1 border-b">
                      <span>{f.requester.nickname}</span>
                      <div class="flex gap-1">
                        <button
                          phx-click="accept_friend"
                          phx-value-friendship-id={f.id}
                          class="btn btn-xs btn-success"
                        >
                          ✓
                        </button>
                        <button
                          phx-click="reject_friend"
                          phx-value-friendship-id={f.id}
                          class="btn btn-xs btn-error"
                        >
                          ✗
                        </button>
                      </div>
                    </div>
                  <% end %>
                <% end %>

                <div class="text-xs font-semibold mt-2">친구 ({length(@friends)})</div>
                <%= if @friends == [] do %>
                  <p class="text-xs text-base-content/40">아직 없음</p>
                <% else %>
                  <%= for u <- @friends do %>
                    <div class="text-sm py-1">{u.nickname}</div>
                  <% end %>
                <% end %>

                <div class="text-xs font-semibold mt-2">
                  {if @show_all_users, do: "모든 사용자", else: "추천 친구 (최대 10)"}
                </div>
                <%= for u <- (if @show_all_users, do: @all_users, else: @recommend) do %>
                  <div class="flex items-center justify-between text-sm py-1">
                    <span>{u.nickname}</span>
                    <%= if u.id != @user.id do %>
                      <button
                        phx-click="send_friend_request"
                        phx-value-user-id={u.id}
                        class="btn btn-xs btn-outline"
                      >
                        +
                      </button>
                    <% end %>
                  </div>
                <% end %>

                <button phx-click="toggle_show_all" class="btn btn-ghost btn-xs mt-1">
                  {if @show_all_users, do: "추천만 보기", else: "더보기 →"}
                </button>
            <% end %>
          </div>
        </section>
      </div>
    </div>
    """
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}
end
