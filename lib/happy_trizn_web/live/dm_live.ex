defmodule HappyTriznWeb.DmLive do
  @moduledoc """
  DM (Direct Message) LiveView.

  - `/dm` — 대화 상대 리스트 (친구 + 마지막 메시지 + 미읽 카운트).
  - `/dm/:peer_id` — 특정 친구와 thread (메시지 + 입력창 + read receipt).

  실시간:
  - subscribe `user:<me_id>:dm` PubSub.
  - 받은 메시지 → 리스트 / 열려있는 thread 자동 갱신.
  """

  use HappyTriznWeb, :live_view

  alias HappyTrizn.Accounts
  alias HappyTrizn.Friends
  alias HappyTrizn.Messages

  @impl true
  def mount(params, _session, socket) do
    user = socket.assigns[:current_user]

    cond do
      is_nil(user) ->
        {:ok, socket |> put_flash(:error, "로그인 사용자만") |> redirect(to: ~p"/lobby")}

      true ->
        if connected?(socket), do: Messages.subscribe(user)
        action = if params["peer_id"], do: :thread, else: :index
        socket = assign(socket, :live_action, action)

        {:ok,
         socket
         |> assign(:user, user)
         |> assign(:page_title, "💬 DM")
         |> load_action(action, params)}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    action = if params["peer_id"], do: :thread, else: :index
    {:noreply, socket |> assign(:live_action, action) |> load_action(action, params)}
  end

  defp load_action(socket, :index, _params) do
    threads = Messages.recent_threads(socket.assigns.user)
    assign(socket, threads: threads, peer: nil, messages: [])
  end

  defp load_action(socket, :thread, %{"peer_id" => peer_id}) do
    me = socket.assigns.user

    case Accounts.get_user(peer_id) do
      nil ->
        socket |> put_flash(:error, "사용자 없음") |> redirect(to: ~p"/dm")

      peer ->
        if Friends.are_friends?(me, peer) do
          # 들어가는 즉시 mark_read.
          Messages.mark_thread_read(me, peer)
          messages = Messages.list_thread(me, peer)

          socket
          |> assign(:peer, peer)
          |> assign(:messages, messages)
          |> assign(:threads, Messages.recent_threads(me))
        else
          socket
          |> put_flash(:error, "친구 사이만 DM 가능")
          |> redirect(to: ~p"/dm")
        end
    end
  end

  # ============================================================================
  # Events
  # ============================================================================

  @impl true
  def handle_event("send", %{"body" => body}, socket) do
    me = socket.assigns.user
    peer = socket.assigns.peer

    cond do
      is_nil(peer) ->
        {:noreply, socket}

      true ->
        case Messages.send(me, peer, body) do
          {:ok, _msg} ->
            {:noreply, push_event(socket, "chat:reset_input", %{})}

          {:error, :not_friends} ->
            {:noreply, put_flash(socket, :error, "친구 사이가 아님")}

          {:error, :invalid} ->
            {:noreply, push_event(socket, "chat:reset_input", %{})}

          {:error, _cs} ->
            {:noreply, put_flash(socket, :error, "메시지 전송 실패")}
        end
    end
  end

  # ============================================================================
  # Realtime PubSub
  # ============================================================================

  @impl true
  def handle_info({:dm_received, msg}, socket) do
    me = socket.assigns.user
    peer = socket.assigns[:peer]

    socket =
      cond do
        # 현재 열려있는 thread 와 일치하면 메시지 추가 + mark_read.
        peer && msg.from_user_id == peer.id ->
          Messages.mark_thread_read(me, peer)

          socket
          |> update(:messages, fn ms -> ms ++ [msg] end)
          |> push_event("chat_message_added", %{})

        true ->
          socket
      end

    # 어느 케이스든 좌측 conversation list 갱신 — 마지막 메시지 / unread 빨간 숫자.
    {:noreply, assign(socket, :threads, Messages.recent_threads(me))}
  end

  def handle_info({:dm_sent, msg}, socket) do
    me = socket.assigns.user
    peer = socket.assigns[:peer]

    socket =
      if peer && msg.to_user_id == peer.id do
        # 본인이 보낸 메시지도 thread 에 추가 (다른 디바이스 sync 와 통일).
        socket
        |> update(:messages, fn ms ->
          if Enum.any?(ms, &(&1.id == msg.id)), do: ms, else: ms ++ [msg]
        end)
        |> push_event("chat_message_added", %{})
      else
        socket
      end

    {:noreply, assign(socket, :threads, Messages.recent_threads(me))}
  end

  def handle_info({:dm_read, _}, socket) do
    # peer 가 읽음. read receipt UI 향후.
    {:noreply, socket}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  # ============================================================================
  # Render
  # ============================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto p-4">
      <h1 class="text-2xl font-bold mb-4">💬 DM</h1>

      <div class="grid grid-cols-1 md:grid-cols-[260px_1fr] gap-4">
        <aside class="bg-base-200 rounded p-2 overflow-y-auto h-[70vh]">
          <h2 class="text-sm font-semibold px-2 py-1 text-base-content/60">대화 상대</h2>
          <%= if @threads == [] do %>
            <div class="text-xs text-base-content/40 px-2 py-3">
              친구 추가 후 메시지 가능. <.link navigate={~p"/lobby"} class="link">로비</.link>에서 친구 검색.
            </div>
          <% else %>
            <ul class="space-y-1">
              <%= for t <- @threads do %>
                <li>
                  <.link
                    navigate={~p"/dm/#{t.peer.id}"}
                    class={[
                      "flex items-center gap-2 p-2 rounded transition",
                      @peer && @peer.id == t.peer.id && "bg-base-300",
                      t.unread > 0 && "bg-error/10 hover:bg-error/20 border-l-4 border-error",
                      !(t.unread > 0) && "hover:bg-base-300"
                    ]}
                  >
                    <.dm_avatar user={t.peer} size={36} />
                    <div class="flex-1 min-w-0">
                      <div class="flex items-center gap-2">
                        <span class={[
                          "truncate",
                          t.unread > 0 && "font-bold text-error",
                          !(t.unread > 0) && "font-semibold"
                        ]}>
                          {t.peer.nickname}
                        </span>
                        <%= if t.unread > 0 do %>
                          <span class="badge badge-error badge-sm font-bold">
                            {if t.unread > 300, do: "300+", else: t.unread}
                          </span>
                        <% end %>
                      </div>
                      <div class={[
                        "text-xs truncate",
                        t.unread > 0 && "text-base-content/80 font-medium",
                        !(t.unread > 0) && "text-base-content/50"
                      ]}>
                        {dm_preview(t.last)}
                      </div>
                    </div>
                  </.link>
                </li>
              <% end %>
            </ul>
          <% end %>
        </aside>

        <main class="bg-base-100 rounded border border-base-300 flex flex-col">
          <%= if @peer do %>
            <header class="border-b border-base-300 p-3 flex items-center gap-2">
              <.dm_avatar user={@peer} size={40} />
              <div>
                <div class="font-bold">{@peer.nickname}</div>
                <div class="text-xs text-base-content/50">{@peer.email}</div>
              </div>
            </header>

            <div
              id="dm-thread-scroll"
              phx-hook="ChatScroll"
              class="overflow-y-auto p-3 flex flex-col-reverse gap-2 h-[60vh]"
            >
              <%= if @messages == [] do %>
                <div class="text-xs text-base-content/40 text-center my-auto">메시지 없음 — 첫 인사를</div>
              <% else %>
                <%= for m <- Enum.reverse(@messages) do %>
                  <.dm_bubble msg={m} me={@user} />
                <% end %>
              <% end %>
            </div>

            <form
              id="dm-form"
              phx-submit="send"
              phx-hook="ChatReset"
              class="border-t border-base-300 p-2 flex gap-1"
            >
              <input
                type="text"
                name="body"
                autocomplete="off"
                maxlength="1000"
                placeholder="메시지..."
                class="input input-sm input-bordered flex-1"
              />
              <button type="submit" class="btn btn-sm btn-primary">전송</button>
            </form>
          <% else %>
            <div class="flex-1 flex items-center justify-center text-base-content/50">
              왼쪽에서 대화 선택
            </div>
          <% end %>
        </main>
      </div>
    </div>
    """
  end

  attr :user, :map, required: true
  attr :size, :integer, default: 36

  defp dm_avatar(assigns) do
    ~H"""
    <%= if @user.avatar_url do %>
      <img
        src={@user.avatar_url}
        alt={@user.nickname}
        class="rounded-full object-cover ring-1 ring-base-300 shrink-0"
        style={"width: #{@size}px; height: #{@size}px"}
      />
    <% else %>
      <div
        class="rounded-full bg-primary/20 text-primary font-bold flex items-center justify-center ring-1 ring-base-300 shrink-0"
        style={"width: #{@size}px; height: #{@size}px"}
      >
        {String.first(@user.nickname) |> String.upcase()}
      </div>
    <% end %>
    """
  end

  attr :msg, :map, required: true
  attr :me, :map, required: true

  defp dm_bubble(assigns) do
    is_me = assigns.msg.from_user_id == assigns.me.id
    parts = body_with_links(assigns.msg.body || "")
    assigns = assigns |> assign(:is_me, is_me) |> assign(:parts, parts)

    ~H"""
    <div class={["flex", @is_me && "justify-end"]}>
      <div class={[
        "max-w-[70%] px-3 py-2 rounded-2xl text-sm break-words",
        @is_me && "bg-primary text-primary-content rounded-br-sm",
        !@is_me && "bg-base-200 rounded-bl-sm"
      ]}>
        <div>
          <%= for part <- @parts do %>
            <%= case part do %>
              <% {:text, t} -> %>
                {t}
              <% {:link, url} -> %>
                <.link
                  navigate={url}
                  class="underline font-semibold hover:opacity-80"
                  title="게임 방 입장"
                >
                  🎮 {url}
                </.link>
            <% end %>
          <% end %>
        </div>
        <div class="text-[10px] opacity-50 mt-1 text-right">
          {format_ts(@msg.inserted_at)}
        </div>
      </div>
    </div>
    """
  end

  # 본문 안 `/game/<slug>/<room_id>` 패턴을 link 로 분해.
  # 결과: list of `{:text, str}` | `{:link, url}`.
  @link_regex ~r{(/game/[a-zA-Z0-9_]+/[a-zA-Z0-9_-]+)}

  defp body_with_links(body) when is_binary(body) do
    case Regex.run(@link_regex, body, return: :index) do
      nil ->
        [{:text, body}]

      [{start, len} | _] ->
        before = String.slice(body, 0, start)
        url = String.slice(body, start, len)
        rest_start = start + len
        rest = String.slice(body, rest_start, byte_size(body))

        [{:text, before}, {:link, url}] ++ body_with_links(rest)
    end
  end

  defp body_with_links(_), do: [{:text, ""}]

  defp dm_preview(nil), do: "(메시지 없음)"
  defp dm_preview(%{body: body}), do: String.slice(body || "", 0, 30)

  defp format_ts(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M")
  end

  defp format_ts(_), do: ""
end
