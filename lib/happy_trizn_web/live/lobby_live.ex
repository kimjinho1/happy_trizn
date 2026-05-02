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
          HappyTriznWeb.Presence.subscribe()
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
         |> assign(:page_title, "로비")
         |> assign(:invite_modal_room, nil)
         |> assign(:online_user_ids, HappyTriznWeb.Presence.online_user_ids())
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

  def handle_event("rooms_page", %{"page" => p}, socket) do
    page = p |> to_string() |> String.to_integer()
    {:noreply, socket |> assign(:rooms_page, page) |> load_rooms()}
  end

  def handle_event("open_invite", %{"room-id" => room_id}, socket) do
    case Rooms.get(room_id) do
      nil -> {:noreply, put_flash(socket, :error, "방 없음")}
      room -> {:noreply, assign(socket, :invite_modal_room, room)}
    end
  end

  def handle_event("close_invite", _, socket) do
    {:noreply, assign(socket, :invite_modal_room, nil)}
  end

  def handle_event("send_invites", params, socket) do
    user = socket.assigns.user
    room = socket.assigns.invite_modal_room
    friend_ids = Map.get(params, "friend_ids", []) |> List.wrap()

    cond do
      is_nil(user) ->
        {:noreply, put_flash(socket, :error, "로그인 사용자만")}

      is_nil(room) ->
        {:noreply, socket}

      friend_ids == [] ->
        {:noreply, put_flash(socket, :error, "친구를 선택하세요")}

      true ->
        url = "/game/#{room.game_type}/#{room.id}"
        game_name = game_display_name(room.game_type)
        body = "🎮 [#{game_name}] 방 초대: #{room.name} → #{url}"

        sent =
          friend_ids
          |> Enum.reduce(0, fn fid, acc ->
            case HappyTrizn.Accounts.get_user(fid) do
              nil ->
                acc

              friend ->
                case HappyTrizn.Messages.send(user, friend, body) do
                  {:ok, _} -> acc + 1
                  _ -> acc
                end
            end
          end)

        {:noreply,
         socket
         |> assign(:invite_modal_room, nil)
         |> put_flash(:info, "초대 #{sent}명 전송")}
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

  # Sprint 4o — GameSession 의 player join/leave 알림 → 방 카드 N/M badge 갱신.
  def handle_info({:room_player_count_changed, _room_id, _count}, socket),
    do: {:noreply, load_rooms(socket)}

  # Sprint 4g — presence diff. 누가 접속/이탈하면 online list 갱신.
  def handle_info(%{event: "presence_diff"}, socket) do
    {:noreply, assign(socket, :online_user_ids, HappyTriznWeb.Presence.online_user_ids())}
  end

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
    # Sprint 4o — list_open_with_counts: [{room, current_player_count}].
    # render 에서 max_players 와 같이 "N/M" badge 로 표시.
    rooms_with_counts = Rooms.list_open_with_counts(limit: 50)
    page = Map.get(socket.assigns, :rooms_page, 1)
    page_size = 4
    total_pages = max(1, ceil(length(rooms_with_counts) / page_size))
    page = page |> max(1) |> min(total_pages)

    socket
    |> assign(:rooms, rooms_with_counts)
    |> assign(:rooms_page, page)
    |> assign(:rooms_page_size, page_size)
    |> assign(:rooms_total_pages, total_pages)
  end

  # game_type slug → 사용자 친화 이름 (캐치마인드, Tetris 등). 없으면 slug 그대로.
  defp game_display_name(slug) do
    case GameRegistry.get_meta(slug) do
      %{name: name} -> name
      _ -> slug
    end
  end

  # Sprint 4o — player count 색상.
  # 0/M = 빨강 (호스트 mount 안 함, orphan 후보), N/M = 노랑 (1+ 자리 남음),
  # full = 회색.
  defp player_count_badge_class(0, _max), do: "badge-error"
  defp player_count_badge_class(n, max) when n >= max, do: "badge-ghost"
  defp player_count_badge_class(_n, _max), do: "badge-warning"

  # 게임별 emoji — single + multi 공용.
  defp single_game_emoji("2048"), do: "🔢"
  defp single_game_emoji("games_2048"), do: "🔢"
  defp single_game_emoji("minesweeper"), do: "💣"
  defp single_game_emoji("pacman"), do: "👻"
  defp single_game_emoji("sudoku"), do: "🧩"
  defp single_game_emoji("tetris"), do: "🟦"
  defp single_game_emoji("bomberman"), do: "💥"
  defp single_game_emoji("skribbl"), do: "🎨"
  defp single_game_emoji("snake_io"), do: "🐍"
  defp single_game_emoji(_), do: "🎯"

  # ============================================================================
  # Render
  # ============================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <div class="min-h-screen p-2 sm:p-3 max-w-7xl mx-auto">
      <div class="grid grid-cols-1 lg:grid-cols-4 gap-3">
        <!-- 왼쪽: 게임 카테고리 + 방 생성 -->
        <section class="card bg-base-200 lg:col-span-1">
          <div class="card-body p-3">
            <h2 class="card-title text-lg">방 만들기</h2>
            <%= if @user do %>
              <form phx-submit="create_room" class="space-y-2">
                <select name="game_type" class="select select-bordered select-md w-full" required>
                  <option value="">게임 선택</option>
                  <%= for g <- @games_multi do %>
                    <option value={g.slug}>{g.name} ({g.mode})</option>
                  <% end %>
                </select>
                <input
                  type="text"
                  name="name"
                  placeholder="방 이름"
                  class="input input-bordered input-md w-full"
                  required
                  maxlength="64"
                />
                <input
                  type="password"
                  name="password"
                  placeholder="비번 (선택)"
                  class="input input-bordered input-md w-full"
                />
                <input
                  type="number"
                  name="max_players"
                  value="4"
                  min="2"
                  max="16"
                  class="input input-bordered input-md w-full"
                />
                <button type="submit" class="btn btn-primary btn-md w-full">생성</button>
              </form>
            <% else %>
              <p class="text-xs text-base-content/50">
                게스트는 방 생성 불가. <.link href={~p"/register"} class="link">@trizn.kr 가입</.link>
              </p>
            <% end %>

            <div class="divider text-xs my-2">싱글</div>
            <div class="grid grid-cols-2 gap-2">
              <%= for g <- @games_single do %>
                <.link
                  navigate={~p"/play/#{g.slug}"}
                  class="btn btn-sm btn-outline btn-primary justify-start text-sm whitespace-nowrap"
                  title={g.name}
                >
                  {single_game_emoji(g.slug)} {g.name}
                </.link>
              <% end %>
              <%= if @games_single == [] do %>
                <div class="text-base-content/40 text-xs col-span-2">Sprint 3 예정</div>
              <% end %>
            </div>
          </div>
        </section>
        
    <!-- 가운데: 방 리스트 + 채팅 -->
        <section class="lg:col-span-2 space-y-4">
          <div class="card bg-base-200">
            <div class="card-body p-3">
              <h2 class="card-title text-lg">활성 방 ({length(@rooms)})</h2>
              <%= if @rooms == [] do %>
                <p class="text-base-content/50 text-sm py-4 text-center">열린 방 없음. 직접 만들어보세요.</p>
              <% else %>
                <% page_rooms =
                  Enum.slice(@rooms, (@rooms_page - 1) * @rooms_page_size, @rooms_page_size) %>
                <div class="space-y-2">
                  <%= for {room, current_count} <- page_rooms do %>
                    <div class="flex items-center justify-between gap-2 p-3 bg-base-100 rounded">
                      <div class="flex items-center gap-2 min-w-0 flex-1">
                        <span class="badge badge-md shrink-0">
                          {single_game_emoji(room.game_type)} {game_display_name(room.game_type)}
                        </span>
                        <span class="font-semibold text-base truncate">{room.name}</span>
                        <span
                          class={"badge badge-sm shrink-0 " <> player_count_badge_class(current_count, room.max_players)}
                          title="현재 / 최대 인원"
                        >
                          👥 {current_count}/{room.max_players}
                        </span>
                        <%= if room.password_hash do %>
                          <span class="text-base shrink-0" title="비밀번호 방">🔒</span>
                        <% end %>
                      </div>
                      <div class="flex items-center gap-2">
                        <%= if @user && @friends != [] do %>
                          <button
                            phx-click="open_invite"
                            phx-value-room-id={room.id}
                            class="btn btn-sm btn-ghost text-lg"
                            title="친구 초대"
                          >
                            💌
                          </button>
                        <% end %>
                        <%= if room.password_hash do %>
                          <form phx-submit="join_room" class="flex items-center gap-1">
                            <input type="hidden" name="room-id" value={room.id} />
                            <input
                              type="password"
                              name="password"
                              placeholder="비번"
                              class="input input-bordered input-sm w-28"
                              required
                            />
                            <button type="submit" class="btn btn-sm btn-primary">입장</button>
                          </form>
                        <% else %>
                          <button
                            phx-click="join_room"
                            phx-value-room-id={room.id}
                            class="btn btn-sm btn-primary"
                          >
                            입장
                          </button>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                </div>

                <%= if @rooms_total_pages > 1 do %>
                  <div class="flex items-center justify-center gap-1 mt-3">
                    <button
                      phx-click="rooms_page"
                      phx-value-page={@rooms_page - 1}
                      class="btn btn-sm btn-ghost"
                      disabled={@rooms_page <= 1}
                    >
                      ←
                    </button>
                    <%= for p <- 1..@rooms_total_pages do %>
                      <button
                        phx-click="rooms_page"
                        phx-value-page={p}
                        class={[
                          "btn btn-sm",
                          if(p == @rooms_page, do: "btn-primary", else: "btn-ghost")
                        ]}
                      >
                        {p}
                      </button>
                    <% end %>
                    <button
                      phx-click="rooms_page"
                      phx-value-page={@rooms_page + 1}
                      class="btn btn-sm btn-ghost"
                      disabled={@rooms_page >= @rooms_total_pages}
                    >
                      →
                    </button>
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>

          <div class="card bg-base-200">
            <div class="card-body p-3">
              <h2 class="card-title text-lg">글로벌 채팅</h2>
              <div
                id="chat-messages"
                class="h-80 overflow-y-auto flex flex-col-reverse gap-1 bg-base-100 rounded p-3 text-base"
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
                  class="input input-bordered input-md flex-1 text-base"
                  maxlength={@max_message_length}
                  autocomplete="off"
                />
                <button type="submit" class="btn btn-primary btn-md text-base" disabled={@rate_limited}>
                  보내기
                </button>
              </form>
            </div>
          </div>
        </section>
        
    <!-- 오른쪽: 친구 사이드바 -->
        <section class="card bg-base-200 lg:col-span-1">
          <div class="card-body p-3">
            <h2 class="card-title text-lg">친구</h2>

            <%= cond do %>
              <% is_nil(@user) -> %>
                <div class="text-center py-4 space-y-3">
                  <div class="text-4xl">👋</div>
                  <p class="text-sm font-semibold">회원가입 하면 가능</p>
                  <ul class="text-sm text-base-content/70 space-y-1 text-left inline-block">
                    <li>👥 친구 추가 / DM</li>
                    <li>🏆 영구 기록 + 리더보드</li>
                    <li>💌 친구 게임 초대</li>
                    <li>🟢 접속중 표시</li>
                  </ul>
                  <.link href={~p"/register"} class="btn btn-primary btn-md w-full">
                    @trizn.kr 가입
                  </.link>
                </div>
              <% true -> %>
                <%= if @pending_received != [] do %>
                  <div class="mt-3 -mx-3 px-3 py-1 bg-warning/20 border-y border-warning/40 text-sm font-bold flex items-center gap-2">
                    🔔 받은 요청
                    <span class="badge badge-warning badge-sm">{length(@pending_received)}</span>
                  </div>
                  <div class="divide-y divide-base-300">
                    <%= for f <- @pending_received do %>
                      <div class="flex items-center justify-between text-base py-1.5">
                        <span>{f.requester.nickname}</span>
                        <div class="flex gap-1">
                          <button
                            phx-click="accept_friend"
                            phx-value-friendship-id={f.id}
                            class="btn btn-sm btn-success"
                          >
                            ✓
                          </button>
                          <button
                            phx-click="reject_friend"
                            phx-value-friendship-id={f.id}
                            class="btn btn-sm btn-error"
                          >
                            ✗
                          </button>
                        </div>
                      </div>
                    <% end %>
                  </div>
                <% end %>

                <div class="mt-3 -mx-3 px-3 py-1 bg-base-300 text-sm font-bold flex items-center gap-2">
                  👥 친구 <span class="badge badge-sm">{length(@friends)}</span>
                </div>
                <%= if @friends == [] do %>
                  <p class="text-sm text-base-content/40 py-1">아직 없음</p>
                <% else %>
                  <div class="divide-y divide-base-300">
                    <%= for u <- @friends do %>
                      <% online? = MapSet.member?(@online_user_ids, u.id) %>
                      <div class="flex items-center justify-between text-base py-1">
                        <span class="flex items-center gap-1.5 truncate">
                          <span
                            class={[
                              "inline-block w-2 h-2 rounded-full shrink-0",
                              if(online?,
                                do: "bg-success ring-2 ring-success/30",
                                else: "bg-base-content/20"
                              )
                            ]}
                            title={if online?, do: "접속 중", else: "오프라인"}
                          >
                          </span>
                          <span class="truncate">{u.nickname}</span>
                        </span>
                        <.link
                          navigate={~p"/dm/#{u.id}"}
                          class="btn btn-sm btn-neutral text-sm inline-flex items-center gap-1 leading-none"
                          title="DM 보내기"
                        >
                          <span class="text-base leading-none">💬</span>
                          <span class="leading-none">DM</span>
                        </.link>
                      </div>
                    <% end %>
                  </div>
                <% end %>

                <div class="mt-3 -mx-3 px-3 py-1 bg-base-300/50 text-sm font-bold flex items-center gap-2">
                  ✨ {if @show_all_users, do: "모든 사용자", else: "추천 친구"}
                </div>
                <div class="divide-y divide-base-300">
                  <%= for u <- (if @show_all_users, do: @all_users, else: @recommend) do %>
                    <div class="flex items-center justify-between text-base py-1">
                      <span>{u.nickname}</span>
                      <%= if u.id != @user.id do %>
                        <button
                          phx-click="send_friend_request"
                          phx-value-user-id={u.id}
                          class="btn btn-sm btn-outline"
                        >
                          +
                        </button>
                      <% end %>
                    </div>
                  <% end %>
                </div>

                <button phx-click="toggle_show_all" class="btn btn-ghost btn-sm text-base mt-2 w-full">
                  {if @show_all_users, do: "추천만 보기", else: "더보기 →"}
                </button>
            <% end %>
          </div>
        </section>
      </div>

      <%= if @invite_modal_room do %>
        <div class="fixed inset-0 z-40 flex items-center justify-center bg-black/50">
          <div
            id="invite-modal-box"
            class="bg-base-100 rounded-lg shadow-xl max-w-md w-full max-h-[80vh] overflow-y-auto p-6"
            phx-click-away="close_invite"
          >
            <header class="flex items-center justify-between mb-3">
              <h2 class="text-lg font-bold">💌 친구 초대 — {@invite_modal_room.name}</h2>
              <button phx-click="close_invite" class="btn btn-sm btn-ghost" type="button">✕</button>
            </header>

            <p class="text-xs text-base-content/60 mb-3">
              {game_display_name(@invite_modal_room.game_type)} 방에 친구 초대.
              선택된 친구에게 DM 으로 link 발송됩니다.
            </p>

            <%= if @friends == [] do %>
              <p class="text-sm text-base-content/50 py-3">친구 없음 — 친구 추가 후 다시 시도.</p>
            <% else %>
              <form phx-submit="send_invites" class="space-y-2">
                <input type="hidden" name="room-id" value={@invite_modal_room.id} />
                <div class="space-y-1 max-h-64 overflow-y-auto">
                  <%= for f <- @friends do %>
                    <label class="flex items-center gap-2 p-2 bg-base-200 rounded cursor-pointer hover:bg-base-300">
                      <input
                        type="checkbox"
                        name="friend_ids[]"
                        value={f.id}
                        class="checkbox checkbox-sm"
                      />
                      <span class="font-semibold">{f.nickname}</span>
                    </label>
                  <% end %>
                </div>
                <div class="flex justify-end gap-2 pt-2">
                  <button type="button" phx-click="close_invite" class="btn btn-sm btn-ghost">
                    취소
                  </button>
                  <button type="submit" class="btn btn-sm btn-primary">DM 보내기</button>
                </div>
              </form>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}
end
