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

  require Logger
  alias HappyTrizn.Rooms
  alias HappyTrizn.Games.GameSession
  alias HappyTrizn.Games.Registry, as: GameRegistry
  alias HappyTrizn.UserGameSettings

  @impl true
  def mount(%{"game_type" => slug, "room_id" => room_id}, _session, socket) do
    nickname = socket.assigns[:current_nickname]
    user = socket.assigns[:current_user]

    Logger.info(
      "[game_multi] mount slug=#{slug} room=#{room_id} nickname=#{inspect(nickname)} user=#{inspect(user && user.id)}"
    )

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
          {:ok,
           socket
           |> put_flash(:error, "이 게임은 싱글 — /play/#{slug}")
           |> redirect(to: ~p"/play/#{slug}")}
        else
          case Rooms.get(room_id) do
            nil ->
              {:ok, socket |> put_flash(:error, "방 없음") |> redirect(to: ~p"/lobby")}

            %{game_type: ^slug, status: status} = _room when status != "closed" ->
              case GameSession.get_or_start_room(room_id, slug) do
                {:ok, pid} ->
                  # player_id = session.id (각 브라우저/탭마다 별도 세션이라 같은 사용자가
                  # 두 디바이스로 같은 방 들어와도 다른 player 로 인식. 사내 dev 테스트 시
                  # 같은 계정 두 incognito 로 1v1 시뮬 가능).
                  player_id = socket.assigns.current_session.id

                  case GameSession.player_join(pid, player_id, %{
                         nickname: nickname,
                         user_id: user.id
                       }) do
                    :ok ->
                      if connected?(socket), do: GameSession.subscribe_room(room_id)

                      key_settings = UserGameSettings.get_for(user, slug)

                      {:ok,
                       socket
                       |> assign(:slug, slug)
                       |> assign(:meta, meta)
                       |> assign(:room_id, room_id)
                       |> assign(:session_pid, pid)
                       |> assign(:player_id, player_id)
                       |> assign(:nickname, nickname)
                       |> assign(:game_state, GameSession.get_state(pid))
                       |> assign(:key_settings, key_settings)
                       |> assign(:result, nil)}

                    {:reject, reason} ->
                      {:ok,
                       socket |> put_flash(:error, "입장 거부: #{reason}") |> redirect(to: ~p"/lobby")}
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
      GameSession.handle_input(socket.assigns.session_pid, socket.assigns.player_id, %{
        "action" => action
      })
    end

    {:noreply, socket}
  end

  # Tetris 기본 키 바인딩 (server-side fallback — JS DAS/ARR 훅이 우선).
  # 사용자별 커스텀 바인딩은 user_game_settings 에 저장 후 JS hook 으로 주입.
  defp key_to_action("tetris", "ArrowLeft"), do: "left"
  defp key_to_action("tetris", "ArrowRight"), do: "right"
  defp key_to_action("tetris", "ArrowUp"), do: "rotate_cw"
  defp key_to_action("tetris", "ArrowDown"), do: "soft_drop"
  defp key_to_action("tetris", " "), do: "hard_drop"
  defp key_to_action("tetris", "Spacebar"), do: "hard_drop"
  defp key_to_action("tetris", "z"), do: "rotate_ccw"
  defp key_to_action("tetris", "Z"), do: "rotate_ccw"
  defp key_to_action("tetris", "x"), do: "rotate_cw"
  defp key_to_action("tetris", "X"), do: "rotate_cw"
  defp key_to_action("tetris", "Control"), do: "rotate_ccw"
  defp key_to_action("tetris", "a"), do: "rotate_180"
  defp key_to_action("tetris", "A"), do: "rotate_180"
  defp key_to_action("tetris", "Shift"), do: "hold"
  defp key_to_action("tetris", "c"), do: "hold"
  defp key_to_action("tetris", "C"), do: "hold"
  defp key_to_action("tetris", "j"), do: "left"
  defp key_to_action("tetris", "l"), do: "right"
  defp key_to_action("tetris", "k"), do: "soft_drop"
  defp key_to_action("tetris", "i"), do: "rotate_cw"
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
      phx-hook={if @slug == "tetris", do: "TetrisInput", else: nil}
      phx-window-keyup="key"
      data-das={@key_settings.das}
      data-arr={@key_settings.arr}
      data-key-bindings={Jason.encode!(@key_settings.bindings)}
      class="min-h-screen p-6 max-w-6xl mx-auto"
    >
      <header class="flex items-center justify-between mb-4">
        <div>
          <h1 class="text-2xl font-bold">{@meta.name}</h1>
          <p class="text-xs text-base-content/60">방: <code>{@room_id}</code> · {@nickname}</p>
        </div>
        <div class="flex gap-2">
          <.link navigate={~p"/settings/games/#{@slug}"} class="btn btn-ghost btn-sm">⚙️ 옵션</.link>
          <.link navigate={~p"/lobby"} class="btn btn-ghost btn-sm">로비로</.link>
        </div>
      </header>

      <%= if @result && @result != %{} do %>
        <div class="alert alert-success mb-4">
          <span>{format_result(@result)}</span>
        </div>
      <% end %>

      <.game_view
        slug={@slug}
        state={@game_state}
        player_id={@player_id}
        options={@key_settings.options}
      />

      <div class="mt-4 text-xs text-base-content/50">
        <%= if @slug == "tetris" do %>
          키: ← → 이동, ↑/X 회전CW, Z/Ctrl 회전CCW, A 180회전, ↓ 소프트드롭, Space 하드드롭, Shift/C 홀드. 옵션에서 변경 가능.
        <% end %>
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

    ghost? = Map.get(assigns.options, "ghost", true)
    grid = Map.get(assigns.options, "grid", "standard")

    assigns = assign(assigns, me: me, other: other_player, ghost?: ghost?, grid: grid)

    ~H"""
    <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
      <div>
        <h3 class="font-semibold mb-2">나 ({@player_id |> String.slice(0..7)})</h3>
        <%= if @me do %>
          <div class="flex gap-2 items-start">
            <.tetris_board board={with_ghost_and_current(@me, @ghost?)} grid={@grid} />
            <div class="flex flex-col gap-2">
              <.piece_preview label="홀드" piece={@me.hold} dim={Map.get(@me, :hold_used, false)} />
              <.piece_preview label="다음" piece={@me.next} />
              <%= if Map.get(@me, :lock_delay_ms) do %>
                <div class="text-xs text-warning">잠금 {@me.lock_delay_ms}ms</div>
              <% end %>
            </div>
          </div>
          <div class="text-sm mt-2 space-y-1">
            <div>점수: <strong>{@me.score}</strong></div>
            <div>라인: {@me.lines} · 레벨: {@me.level}</div>
            <div>
              받을 가비지:
              <span class={if @me.pending_garbage > 0, do: "text-error font-bold", else: ""}>
                {@me.pending_garbage}
              </span>
            </div>
            <div class="flex gap-2">
              <%= if Map.get(@me, :combo, -1) >= 1 do %>
                <span class="badge badge-warning">콤보 ×{@me.combo}</span>
              <% end %>
              <%= if Map.get(@me, :b2b, false) do %>
                <span class="badge badge-info">B2B</span>
              <% end %>
            </div>
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
          <div class="flex gap-2 items-start">
            <.tetris_board board={with_ghost_and_current(@other, false)} grid={@grid} />
            <div class="flex flex-col gap-2">
              <.piece_preview
                label="홀드"
                piece={@other.hold}
                dim={Map.get(@other, :hold_used, false)}
              />
              <.piece_preview label="다음" piece={@other.next} />
            </div>
          </div>
          <div class="text-sm mt-2 space-y-1">
            <div>점수: {@other.score} · 라인: {@other.lines} · 레벨: {@other.level}</div>
            <div class="flex gap-2">
              <%= if Map.get(@other, :combo, -1) >= 1 do %>
                <span class="badge badge-warning">콤보 ×{@other.combo}</span>
              <% end %>
              <%= if Map.get(@other, :b2b, false) do %>
                <span class="badge badge-info">B2B</span>
              <% end %>
            </div>
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

  attr :label, :string, required: true
  attr :piece, :atom, default: nil
  attr :dim, :boolean, default: false

  defp piece_preview(assigns) do
    ~H"""
    <div class={["bg-base-200 p-2 rounded text-center min-w-[80px]", @dim && "opacity-40"]}>
      <div class="text-xs text-base-content/60 mb-1">{@label}</div>
      <%= if @piece do %>
        <div class="grid grid-cols-4 gap-px">
          <%= for {r, c} <- piece_preview_cells(@piece) do %>
            <div
              class={["w-3 h-3", cell_color(@piece)]}
              style={"grid-row: #{r + 1}; grid-column: #{c + 1};"}
            >
            </div>
          <% end %>
        </div>
      <% else %>
        <div class="h-8"></div>
      <% end %>
    </div>
    """
  end

  defp piece_preview_cells(type) do
    HappyTrizn.Games.Tetris.Piece.cells(type, 0)
  end

  # 1. board, 2. ghost (옵션 켜졌고 origin != landing 시), 3. current piece — 순으로 overlay.
  defp with_ghost_and_current(%{board: board, current: cur, top_out: false} = p, ghost?) do
    board
    |> maybe_overlay_ghost(p, ghost?)
    |> overlay_cells(
      HappyTrizn.Games.Tetris.Piece.absolute_cells(cur.type, cur.rotation, cur.origin),
      cur.type
    )
  end

  defp with_ghost_and_current(%{board: board}, _), do: board

  defp maybe_overlay_ghost(board, _, false), do: board

  defp maybe_overlay_ghost(board, %{current: cur} = _p, true) do
    landing =
      HappyTrizn.Games.Tetris.Board.hard_drop_position(board, cur.type, cur.rotation, cur.origin)

    if landing == cur.origin do
      board
    else
      cells = HappyTrizn.Games.Tetris.Piece.absolute_cells(cur.type, cur.rotation, landing)
      overlay_cells(board, cells, :ghost)
    end
  end

  defp overlay_cells(board, cells, value) do
    Enum.reduce(cells, board, fn {r, c}, acc ->
      if r >= 0 and r < length(acc) do
        row = Enum.at(acc, r) |> List.replace_at(c, value)
        List.replace_at(acc, r, row)
      else
        acc
      end
    end)
  end

  # 22x10 board → 20x10 (visible) 만 표시. grid 옵션: none / standard / partial / vertical / full.
  attr :board, :list, required: true
  attr :grid, :string, default: "standard"

  defp tetris_board(assigns) do
    visible = Enum.drop(assigns.board, 2)
    assigns = assign(assigns, visible: visible)

    ~H"""
    <div class="inline-block bg-base-300 p-1">
      <%= for row <- @visible do %>
        <div class="flex">
          <%= for cell <- row do %>
            <div class={["w-5 h-5", cell_color(cell), grid_class(@grid)]}></div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp grid_class("none"), do: ""
  defp grid_class("standard"), do: "border border-base-100"
  defp grid_class("partial"), do: "border-l border-t border-base-100"
  defp grid_class("vertical"), do: "border-l border-r border-base-100/50"
  defp grid_class("full"), do: "border border-base-100/80"
  defp grid_class(_), do: "border border-base-100"

  defp cell_color(nil), do: "bg-base-100"
  defp cell_color(:i), do: "bg-cyan-400"
  defp cell_color(:o), do: "bg-yellow-400"
  defp cell_color(:t), do: "bg-purple-500"
  defp cell_color(:s), do: "bg-green-500"
  defp cell_color(:z), do: "bg-red-500"
  defp cell_color(:l), do: "bg-orange-500"
  defp cell_color(:j), do: "bg-blue-500"
  defp cell_color(:garbage), do: "bg-gray-500"
  defp cell_color(:ghost), do: "bg-base-100 ring-1 ring-base-content/30"
  defp cell_color(_), do: "bg-base-100"

  defp format_result(%{winner: w}), do: "승자: #{String.slice(w, 0..7)}!"
  defp format_result(other), do: inspect(other)
end
