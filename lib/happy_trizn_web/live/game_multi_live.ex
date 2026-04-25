defmodule HappyTriznWeb.GameMultiLive do
  @moduledoc """
  멀티 게임 진입점 — `/game/:game_type/:room_id`.

  - `Rooms.get!/1` 로 방 검증.
  - `GameSession.get_or_start_room/2` 로 GenServer 확보 후 player_join.
  - PubSub `game:<room_id>` subscribe → game_event 받아 socket assign 갱신.
  - keyboard input (Tetris): JS hook 이 phx-keyup → handle_event "input".
  - 화면 leave 시 `GameSession.player_leave/3` (LiveView terminate).
  """

  use HappyTriznWeb, :live_view

  alias HappyTrizn.Rooms
  alias HappyTrizn.Games.GameSession
  alias HappyTrizn.Games.Registry, as: GameRegistry

  @impl true
  def mount(%{"game_type" => slug, "room_id" => room_id}, _session, socket) do
    nickname = socket.assigns[:current_nickname]
    user = socket.assigns[:current_user]

    cond do
      is_nil(nickname) ->
        {:ok, socket |> put_flash(:error, "먼저 입장하세요.") |> redirect(to: ~p"/")}

      is_nil(user) ->
        {:ok, socket |> put_flash(:error, "게스트는 멀티 게임 입장 불가") |> redirect(to: ~p"/lobby")}

      not GameRegistry.valid_slug?(slug) ->
        {:ok, socket |> put_flash(:error, "없는 게임") |> redirect(to: ~p"/lobby")}

      true ->
        meta = GameRegistry.get_meta(slug)

        if meta.mode != :multi do
          {:ok, socket |> put_flash(:error, "이 게임은 싱글 — /play/#{slug}") |> redirect(to: ~p"/play/#{slug}")}
        else
          case Rooms.get(room_id) do
            nil ->
              {:ok, socket |> put_flash(:error, "방 없음") |> redirect(to: ~p"/lobby")}

            %{game_type: ^slug, status: status} = _room when status != "closed" ->
              case GameSession.get_or_start_room(room_id, slug) do
                {:ok, pid} ->
                  case GameSession.player_join(pid, user.id, %{nickname: nickname}) do
                    :ok ->
                      if connected?(socket), do: GameSession.subscribe_room(room_id)

                      {:ok,
                       socket
                       |> assign(:slug, slug)
                       |> assign(:meta, meta)
                       |> assign(:room_id, room_id)
                       |> assign(:session_pid, pid)
                       |> assign(:player_id, user.id)
                       |> assign(:nickname, nickname)
                       |> assign(:game_state, GameSession.get_state(pid))
                       |> assign(:result, nil)}

                    {:reject, reason} ->
                      {:ok, socket |> put_flash(:error, "입장 거부: #{reason}") |> redirect(to: ~p"/lobby")}
                  end

                {:error, _} ->
                  {:ok, socket |> put_flash(:error, "게임 세션 시작 실패") |> redirect(to: ~p"/lobby")}
              end

            _ ->
              {:ok, socket |> put_flash(:error, "방 종료됨") |> redirect(to: ~p"/lobby")}
          end
        end
    end
  end

  # ============================================================================
  # Input
  # ============================================================================

  @impl true
  def handle_event("input", payload, socket) do
    GameSession.handle_input(socket.assigns.session_pid, socket.assigns.player_id, payload)
    {:noreply, socket}
  end

  def handle_event("key", %{"key" => key}, socket) do
    if action = key_to_action(socket.assigns.slug, key) do
      GameSession.handle_input(socket.assigns.session_pid, socket.assigns.player_id, %{"action" => action})
    end

    {:noreply, socket}
  end

  defp key_to_action("tetris", "ArrowLeft"), do: "left"
  defp key_to_action("tetris", "ArrowRight"), do: "right"
  defp key_to_action("tetris", "ArrowUp"), do: "rotate"
  defp key_to_action("tetris", "ArrowDown"), do: "soft_drop"
  defp key_to_action("tetris", " "), do: "hard_drop"
  defp key_to_action("tetris", "Spacebar"), do: "hard_drop"
  defp key_to_action(_, _), do: nil

  # ============================================================================
  # PubSub from GameSession
  # ============================================================================

  @impl true
  def handle_info({:game_event, {:player_state, _pid, _state}}, socket) do
    # 모든 player_state event 시 server에서 다시 fetch (간단)
    {:noreply, refresh_state(socket)}
  end

  def handle_info({:game_event, {:winner, w}}, socket) do
    new_socket = refresh_state(socket)
    {:noreply, assign(new_socket, result: %{winner: w})}
  end

  def handle_info({:game_event, {:top_out, _pid}}, socket) do
    {:noreply, refresh_state(socket)}
  end

  def handle_info({:game_event, _other}, socket), do: {:noreply, refresh_state(socket)}

  def handle_info(_, socket), do: {:noreply, socket}

  defp refresh_state(socket) do
    if Process.alive?(socket.assigns.session_pid) do
      assign(socket, game_state: GameSession.get_state(socket.assigns.session_pid))
    else
      socket
    end
  end

  # ============================================================================
  # Terminate (LiveView 떠날 때 player_leave)
  # ============================================================================

  @impl true
  def terminate(_reason, socket) do
    if pid = socket.assigns[:session_pid] do
      if Process.alive?(pid) do
        GameSession.player_leave(pid, socket.assigns.player_id, :disconnect)
      end
    end

    :ok
  end

  # ============================================================================
  # Render
  # ============================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={"game-multi-#{@slug}-#{@room_id}"}
      phx-window-keyup="key"
      class="min-h-screen p-6 max-w-6xl mx-auto"
    >
      <header class="flex items-center justify-between mb-4">
        <div>
          <h1 class="text-2xl font-bold">{@meta.name}</h1>
          <p class="text-xs text-base-content/60">방: <code>{@room_id}</code> · {@nickname}</p>
        </div>
        <.link navigate={~p"/lobby"} class="btn btn-ghost btn-sm">로비로</.link>
      </header>

      <%= if @result && @result != %{} do %>
        <div class="alert alert-success mb-4">
          <span>{format_result(@result)}</span>
        </div>
      <% end %>

      <.game_view slug={@slug} state={@game_state} player_id={@player_id} />

      <div class="mt-4 text-xs text-base-content/50">
        키보드: ← → 이동, ↑ 회전, ↓ 소프트드롭, Space 하드드롭.
      </div>
    </div>
    """
  end

  defp game_view(%{slug: "tetris"} = assigns) do
    me_id = assigns.player_id
    state = assigns.state

    me = Map.get(state.players, me_id)
    other = state.players |> Enum.find(fn {id, _} -> id != me_id end)
    other_player = if other, do: elem(other, 1), else: nil

    assigns = assign(assigns, me: me, other: other_player)

    ~H"""
    <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
      <div>
        <h3 class="font-semibold mb-2">나 ({@player_id |> String.slice(0..7)})</h3>
        <%= if @me do %>
          <.tetris_board board={with_current(@me)} />
          <div class="text-sm mt-2 space-y-1">
            <div>점수: <strong>{@me.score}</strong></div>
            <div>라인: {@me.lines} · 레벨: {@me.level}</div>
            <div>다음: {@me.next}</div>
            <div>받을 가비지: {@me.pending_garbage}</div>
            <%= if @me.top_out do %>
              <div class="text-error font-bold">탑아웃</div>
            <% end %>
          </div>
        <% else %>
          <div class="text-base-content/40">로딩...</div>
        <% end %>
      </div>

      <div>
        <h3 class="font-semibold mb-2">상대</h3>
        <%= if @other do %>
          <.tetris_board board={with_current(@other)} />
          <div class="text-sm mt-2 space-y-1">
            <div>점수: {@other.score} · 라인: {@other.lines} · 레벨: {@other.level}</div>
            <%= if @other.top_out do %>
              <div class="text-error font-bold">탑아웃</div>
            <% end %>
          </div>
        <% else %>
          <div class="text-base-content/40">상대방 대기 중...</div>
        <% end %>
      </div>
    </div>
    """
  end

  defp game_view(assigns) do
    ~H"""
    <div class="card bg-base-200">
      <div class="card-body">
        <h3 class="card-title">{@slug}</h3>
        <p class="text-sm">이 게임은 Sprint 3b 진행 중. 풀 클라이언트 구현 예정.</p>
        <pre class="text-xs bg-base-100 p-2 rounded overflow-auto max-h-64">{inspect(@state, pretty: true, limit: 50)}</pre>
      </div>
    </div>
    """
  end

  # board (player) 에 current piece overlay → 단일 grid 렌더용.
  defp with_current(%{board: board, current: cur, top_out: false}) do
    cells = HappyTrizn.Games.Tetris.Piece.absolute_cells(cur.type, cur.rotation, cur.origin)

    Enum.reduce(cells, board, fn {r, c}, acc ->
      if r >= 0 and r < length(acc) do
        row = Enum.at(acc, r) |> List.replace_at(c, cur.type)
        List.replace_at(acc, r, row)
      else
        acc
      end
    end)
  end

  defp with_current(%{board: board}), do: board

  # 22x10 board → 20x10 (visible) 만 표시.
  attr :board, :list, required: true

  defp tetris_board(assigns) do
    visible = Enum.drop(assigns.board, 2)
    assigns = assign(assigns, visible: visible)

    ~H"""
    <div class="inline-block bg-base-300 p-1">
      <%= for row <- @visible do %>
        <div class="flex">
          <%= for cell <- row do %>
            <div class={["w-5 h-5 border border-base-100", cell_color(cell)]}></div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp cell_color(nil), do: "bg-base-100"
  defp cell_color(:i), do: "bg-cyan-400"
  defp cell_color(:o), do: "bg-yellow-400"
  defp cell_color(:t), do: "bg-purple-500"
  defp cell_color(:s), do: "bg-green-500"
  defp cell_color(:z), do: "bg-red-500"
  defp cell_color(:l), do: "bg-orange-500"
  defp cell_color(:j), do: "bg-blue-500"
  defp cell_color(:garbage), do: "bg-gray-500"
  defp cell_color(_), do: "bg-base-100"

  defp format_result(%{winner: w}), do: "승자: #{String.slice(w, 0..7)}!"
  defp format_result(other), do: inspect(other)
end
