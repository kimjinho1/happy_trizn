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
              # WebSocket connect 됐을 때만 GameSession 에 join — HTTP 첫 mount 는
              # 즉시 종료되는 임시 프로세스라 join → terminate → leave 사이클이 도는데,
              # 그 사이에 GameSession 이 player 0 명 → :stop 으로 종료돼버림 (호스트가
              # 만든 직후 다른 사용자가 들어오면 호스트가 안 보이는 원인).
              if connected?(socket) do
                join_connected(socket, slug, meta, room_id, nickname, user)
              else
                # HTTP 첫 mount — 화면 초기 렌더만, GameSession 건드리지 않음.
                # 실제 join 은 WS 가 붙은 후의 mount 에서.
                {:ok,
                 socket
                 |> assign(:slug, slug)
                 |> assign(:meta, meta)
                 |> assign(:room_id, room_id)
                 |> assign(:session_pid, nil)
                 |> assign(:player_id, socket.assigns.current_session.id)
                 |> assign(:nickname, nickname)
                 |> assign(:game_state, %{status: :waiting, players: %{}})
                 |> assign(:key_settings, UserGameSettings.get_for(user, slug))
                 |> assign(:settings_open, false)
                 |> assign(:result, nil)
                 |> assign(:joined, false)}
              end

            _ ->
              {:ok, socket |> put_flash(:error, "방 종료됨") |> redirect(to: ~p"/lobby")}
          end
        end
    end
  end

  defp join_connected(socket, slug, meta, room_id, nickname, user) do
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
            GameSession.subscribe_room(room_id)
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
             |> assign(:settings_open, false)
             |> assign(:result, nil)
             |> assign(:joined, true)}

          {:reject, reason} ->
            {:ok, socket |> put_flash(:error, "입장 거부: #{reason}") |> redirect(to: ~p"/lobby")}
        end

      {:error, _} ->
        {:ok, socket |> put_flash(:error, "게임 세션 시작 실패") |> redirect(to: ~p"/lobby")}
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

  def handle_event("start_practice", _, socket) do
    GameSession.handle_input(socket.assigns.session_pid, socket.assigns.player_id, %{
      "action" => "start_practice"
    })

    {:noreply, socket}
  end

  def handle_event("restart", _, socket) do
    GameSession.handle_input(socket.assigns.session_pid, socket.assigns.player_id, %{
      "action" => "restart"
    })

    {:noreply, assign(socket, :result, nil)}
  end

  # ============================================================================
  # 옵션 모달 (game LiveView 그대로 유지, 새 페이지/탭 안 옮김)
  # ============================================================================

  def handle_event("open_settings", _, socket) do
    {:noreply, assign(socket, :settings_open, true)}
  end

  def handle_event("close_settings", _, socket) do
    {:noreply, assign(socket, :settings_open, false)}
  end

  def handle_event("modal_save_binding", %{"action" => action, "keys" => keys_str}, socket) do
    user = socket.assigns[:current_user]

    if is_nil(user) do
      {:noreply, put_flash(socket, :error, "게스트는 옵션 저장 불가")}
    else
      keys = UserGameSettings.parse_keys_input(keys_str)
      new_bindings = Map.put(socket.assigns.key_settings.bindings, action, keys)

      case UserGameSettings.upsert(user, socket.assigns.slug, %{
             key_bindings: new_bindings,
             options: socket.assigns.key_settings.options
           }) do
        {:ok, _} ->
          new_settings = UserGameSettings.get_for(user, socket.assigns.slug)

          # 단일 키 저장은 모달 안 닫음 — 사용자가 여러 액션 연속 저장 가능.
          {:noreply, socket |> assign(:key_settings, new_settings) |> put_flash(:info, "저장됨")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "저장 실패")}
      end
    end
  end

  def handle_event("modal_save_options", params, socket) do
    user = socket.assigns[:current_user]

    if is_nil(user) do
      {:noreply, put_flash(socket, :error, "게스트는 옵션 저장 불가")}
    else
      raw = Map.get(params, "options", %{})
      base = socket.assigns.key_settings.options

      new_options =
        Enum.reduce(raw, base, fn {k, v}, acc ->
          Map.put(acc, k, UserGameSettings.normalize_option_value(k, v))
        end)

      case UserGameSettings.upsert(user, socket.assigns.slug, %{
             key_bindings: socket.assigns.key_settings.bindings,
             options: new_options
           }) do
        {:ok, _} ->
          new_settings = UserGameSettings.get_for(user, socket.assigns.slug)

          {:noreply,
           socket
           |> assign(:key_settings, new_settings)
           |> assign(:settings_open, false)
           |> put_flash(:info, "저장됨")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "저장 실패")}
      end
    end
  end

  def handle_event("modal_reset", _, socket) do
    user = socket.assigns[:current_user]

    if is_nil(user) do
      {:noreply, put_flash(socket, :error, "게스트는 reset 불가")}
    else
      :ok = UserGameSettings.reset(user, socket.assigns.slug)
      new_settings = UserGameSettings.get_for(user, socket.assigns.slug)
      # reset 도 모달 유지 — 변경 사항 확인 후 사용자가 직접 닫음.
      {:noreply, socket |> assign(:key_settings, new_settings) |> put_flash(:info, "초기화 완료")}
    end
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
  defp key_to_action("tetris", "Space"), do: "hard_drop"
  defp key_to_action("tetris", "space"), do: "hard_drop"
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
  def handle_info({:game_event, {:player_state, pid, player_state}}, socket) do
    # payload 에 새 player state 포함 — GenServer.call(get_state) 안 해도 됨.
    # 매 50ms tick + 매 input 마다 GenServer call 하면 mailbox 폭주 → freeze.
    game_state = socket.assigns.game_state
    new_players = Map.put(game_state.players || %{}, pid, player_state)
    new_game_state = %{game_state | players: new_players}
    {:noreply, assign(socket, :game_state, new_game_state)}
  end

  def handle_info({:game_event, {:winner, w}}, socket) do
    new_socket = refresh_state(socket)
    {:noreply, assign(new_socket, result: %{winner: w})}
  end

  def handle_info({:game_event, {:game_over, results}}, socket) do
    socket = sfx(socket, sfx_for_game_over(results, socket.assigns.player_id))
    {:noreply, socket |> refresh_state() |> assign(result: results)}
  end

  def handle_info({:game_event, {:restart, _}}, socket) do
    # 라운드 시작 — result 클리어, 보드 갱신.
    {:noreply, socket |> refresh_state() |> assign(:result, nil)}
  end

  def handle_info({:game_event, {:top_out, pid}}, socket) do
    socket = if pid == socket.assigns.player_id, do: sfx(socket, "top_out"), else: socket
    {:noreply, refresh_state(socket)}
  end

  def handle_info({:game_event, {:line_clear, %{player: pid, lines: lines, b2b: b2b}}}, socket) do
    socket =
      cond do
        pid != socket.assigns.player_id -> socket
        b2b and lines >= 2 -> sfx(socket, "b2b")
        lines == 4 -> sfx(socket, "tetris")
        lines >= 1 -> sfx(socket, "line_clear")
        true -> socket
      end

    {:noreply, refresh_state(socket)}
  end

  def handle_info({:game_event, {:garbage_sent, %{to: to}}}, socket) do
    socket = if to == socket.assigns.player_id, do: sfx(socket, "garbage"), else: socket
    {:noreply, refresh_state(socket)}
  end

  def handle_info({:game_event, {:countdown_start, _}}, socket) do
    {:noreply, sfx(socket, "countdown") |> refresh_state()}
  end

  def handle_info({:game_event, {:countdown_tick, ms}}, socket) when is_integer(ms) do
    # 1초마다 (1000ms 경계) "초읽기" tick 사운드. 마지막 0 도달 시 game_over 가 :tetris.
    socket =
      cond do
        ms <= 0 -> socket
        rem(ms, 1000) == 0 -> sfx(socket, "countdown")
        true -> socket
      end

    {:noreply, refresh_state(socket)}
  end

  def handle_info({:game_event, {:rotated, pid}}, socket) do
    socket = if pid == socket.assigns.player_id, do: sfx(socket, "rotate"), else: socket
    {:noreply, refresh_state(socket)}
  end

  def handle_info({:game_event, {:locked, pid}}, socket) do
    socket = if pid == socket.assigns.player_id, do: sfx(socket, "lock"), else: socket
    {:noreply, refresh_state(socket)}
  end

  def handle_info({:game_event, _other}, socket), do: {:noreply, refresh_state(socket)}

  def handle_info(_, socket), do: {:noreply, socket}

  defp sfx_for_game_over(%{winner: w}, me) when is_binary(w) and w == me, do: "tetris"
  defp sfx_for_game_over(_, _), do: "top_out"

  defp sfx(socket, event) when is_binary(event) do
    Phoenix.LiveView.push_event(socket, "tetris:sfx", %{event: event})
  end

  defp refresh_state(socket) do
    pid = socket.assigns[:session_pid]

    if pid && Process.alive?(pid) do
      try do
        # 5초 timeout — GenServer 가 다른 호출 처리 중이어도 LiveView 안 멈춤.
        assign(socket, game_state: GenServer.call(pid, :get_state, 5_000))
      catch
        :exit, _ ->
          # GameSession busy / dead — 기존 game_state 유지.
          socket
      end
    else
      socket
    end
  end

  # ============================================================================
  # Terminate (LiveView 떠날 때 player_leave)
  # ============================================================================

  @impl true
  def terminate(_reason, socket) do
    # joined: true 인 경우만 leave — HTTP 첫 mount 는 join 안 했으니 leave 도 안 함.
    if socket.assigns[:joined] && socket.assigns[:session_pid] do
      pid = socket.assigns.session_pid

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
      phx-window-keyup={if @slug == "tetris", do: nil, else: "key"}
      data-das={@key_settings.das}
      data-arr={@key_settings.arr}
      data-key-bindings={Jason.encode!(@key_settings.bindings)}
      class="min-h-screen p-6 max-w-6xl mx-auto"
    >
      <%= if @slug == "tetris" do %>
        <div
          id="tetris-sound"
          phx-hook="TetrisSound"
          data-sound-volume={@key_settings.options["sound_volume"] || 16}
          data-sound-rotate={to_string(@key_settings.options["sound_rotate"] != false)}
          data-sound-lock={to_string(@key_settings.options["sound_lock"] != false)}
          data-sound-line-clear={to_string(@key_settings.options["sound_line_clear"] != false)}
          data-sound-tetris={to_string(@key_settings.options["sound_tetris"] != false)}
          data-sound-b2b={to_string(@key_settings.options["sound_b2b"] != false)}
          data-sound-garbage={to_string(@key_settings.options["sound_garbage"] != false)}
          data-sound-top-out={to_string(@key_settings.options["sound_top_out"] != false)}
          data-sound-countdown={to_string(@key_settings.options["sound_countdown"] != false)}
          class="hidden"
        >
        </div>
      <% end %>
      <header class="flex items-center justify-between mb-4">
        <div>
          <h1 class="text-2xl font-bold">{@meta.name}</h1>
          <p class="text-xs text-base-content/60">방: <code>{@room_id}</code> · {@nickname}</p>
        </div>
        <div class="flex gap-2">
          <button
            phx-click="open_settings"
            class="btn btn-ghost btn-sm"
            title="옵션 모달 — 게임 유지"
            type="button"
          >
            ⚙️ 옵션
          </button>
          <.link navigate={~p"/lobby"} class="btn btn-ghost btn-sm">로비로</.link>
        </div>
      </header>

      <%= if @result && @result != %{} do %>
        <.game_over_panel result={@result} player_id={@player_id} />
      <% end %>

      <%= if @slug == "tetris" do %>
        <.tetris_status_banner game_state={@game_state} player_id={@player_id} />
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

      <%= if @settings_open do %>
        <.settings_modal slug={@slug} settings={@key_settings} />
      <% end %>
    </div>
    """
  end

  attr :slug, :string, required: true
  attr :settings, :map, required: true

  defp settings_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 z-40 flex items-center justify-center bg-black/50">
      <div
        id="settings-modal-box"
        class="bg-base-100 rounded-lg shadow-xl max-w-2xl w-full max-h-[90vh] overflow-y-auto p-6"
        phx-click-away="close_settings"
      >
        <header class="flex items-center justify-between mb-4">
          <h2 class="text-xl font-bold">⚙️ {String.upcase(@slug)} 옵션</h2>
          <button phx-click="close_settings" class="btn btn-sm btn-ghost" type="button">✕</button>
        </header>

        <p class="text-xs text-base-content/60 mb-4">
          저장 즉시 반영. 게임 그대로 진행 중.
        </p>

        <%= if map_size(@settings.bindings) > 0 do %>
          <section class="mb-6">
            <h3 class="font-semibold mb-2">키 바인딩</h3>
            <p class="text-xs text-base-content/60 mb-2">
              콤마(,)로 여러 키 등록. 예: <code>ArrowLeft, j</code>
            </p>
            <div class="space-y-2">
              <%= for action <- @settings.bindings |> Map.keys() |> Enum.sort() do %>
                <form phx-submit="modal_save_binding" class="flex items-center gap-2">
                  <label class="w-28 text-sm">{action}</label>
                  <input type="hidden" name="action" value={action} />
                  <input
                    type="text"
                    name="keys"
                    value={HappyTrizn.UserGameSettings.display_keys(@settings.bindings[action] || [])}
                    class="input input-bordered input-sm flex-1"
                  />
                  <button type="submit" class="btn btn-sm btn-primary">저장</button>
                </form>
              <% end %>
            </div>
          </section>
        <% end %>

        <%= if map_size(@settings.options) > 0 do %>
          <section class="mb-4">
            <h3 class="font-semibold mb-2">게임 설정</h3>
            <form phx-submit="modal_save_options" class="space-y-2">
              <%= for {k, v} <- @settings.options |> Enum.sort_by(&elem(&1, 0)) do %>
                <label class="flex items-center gap-2">
                  <span class="w-32 text-sm">{k}</span>
                  <%= cond do %>
                    <% is_boolean(v) -> %>
                      <input type="hidden" name={"options[#{k}]"} value="false" />
                      <input
                        type="checkbox"
                        name={"options[#{k}]"}
                        value="true"
                        checked={v}
                        class="checkbox checkbox-sm"
                      />
                    <% true -> %>
                      <input
                        type="text"
                        name={"options[#{k}]"}
                        value={to_string(v)}
                        class="input input-bordered input-sm flex-1"
                      />
                  <% end %>
                </label>
              <% end %>
              <div class="flex gap-2 pt-2">
                <button type="submit" class="btn btn-primary btn-sm">옵션 저장</button>
                <button
                  type="button"
                  phx-click="modal_reset"
                  class="btn btn-ghost btn-sm"
                  data-confirm="정말 초기화?"
                >
                  초기화
                </button>
              </div>
            </form>
          </section>
        <% end %>
      </div>
    </div>
    """
  end

  attr :game_state, :map, required: true
  attr :player_id, :string, required: true

  defp tetris_status_banner(assigns) do
    status = Map.get(assigns.game_state, :status)
    countdown = Map.get(assigns.game_state, :countdown_ms)
    me_alone? = map_size(assigns.game_state.players) == 1
    in_room? = Map.has_key?(assigns.game_state.players, assigns.player_id)

    assigns =
      assign(assigns,
        status: status,
        countdown: countdown,
        me_alone?: me_alone?,
        in_room?: in_room?
      )

    ~H"""
    <%= cond do %>
      <% @status == :countdown -> %>
        <div class="alert alert-warning mb-4 text-center text-2xl font-bold">
          시작까지 {countdown_seconds(@countdown)}…
        </div>
      <% @status == :waiting and @me_alone? and @in_room? -> %>
        <div class="alert alert-info mb-4 flex items-center justify-between">
          <span>혼자 있어요. 상대 기다리는 동안 연습하기 가능.</span>
          <button phx-click="start_practice" class="btn btn-sm btn-primary">🎯 스프린트 (연습)</button>
        </div>
      <% @status == :practice -> %>
        <div class="alert alert-success mb-4 text-sm">
          연습 중. 상대 입장 시 자동으로 멀티 게임 시작 (3-2-1 카운트다운).
        </div>
      <% true -> %>
        {[]}
    <% end %>
    """
  end

  defp countdown_seconds(ms) when is_integer(ms) and ms > 0, do: div(ms - 1, 1000) + 1
  defp countdown_seconds(_), do: 0

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
            <!-- 좌측: 홀드 -->
            <div class="flex flex-col gap-2">
              <.piece_preview label="홀드" piece={@me.hold} dim={Map.get(@me, :hold_used, false)} />
              <%= if Map.get(@me, :lock_delay_ms) do %>
                <div class="text-xs text-warning">잠금 {@me.lock_delay_ms}ms</div>
              <% end %>
            </div>
            <!-- 중앙: 보드 -->
            <.tetris_board
              board={with_ghost_and_current(@me, @ghost?)}
              grid={@grid}
              pending={@me.pending_garbage}
            />
            <!-- 우측: 다음 큐 -->
            <.next_queue nexts={Map.get(@me, :nexts, [@me.next])} />
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
            <div class="flex flex-col gap-2">
              <.piece_preview
                label="홀드"
                piece={@other.hold}
                dim={Map.get(@other, :hold_used, false)}
              />
            </div>
            <.tetris_board
              board={with_ghost_and_current(@other, false)}
              grid={@grid}
              pending={@other.pending_garbage}
            />
            <.next_queue nexts={Map.get(@other, :nexts, [@other.next])} />
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

  attr :nexts, :list, required: true

  defp next_queue(assigns) do
    ~H"""
    <div class="flex flex-col gap-1 bg-base-200 p-2 rounded min-w-[80px]">
      <div class="text-xs text-base-content/60 mb-1 text-center">다음</div>
      <%= for piece <- @nexts || [] do %>
        <div class="grid grid-cols-4 gap-px">
          <%= for {r, c} <- piece_preview_cells(piece) do %>
            <div
              class={["w-3 h-3", cell_color(piece)]}
              style={"grid-row: #{r + 1}; grid-column: #{c + 1};"}
            >
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
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
      # ghost 셀은 piece type 을 들고 다님 — 색은 같지만 opacity 낮춰 표시.
      overlay_cells(board, cells, {:ghost, cur.type})
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
  # pending: 사용자가 받을 garbage 수 (board 좌측에 빨간 spoiler bar 로 표시).
  attr :board, :list, required: true
  attr :grid, :string, default: "standard"
  attr :pending, :integer, default: 0

  defp tetris_board(assigns) do
    # board overflow 방어 — drop hidden 2 + take visible 20. board state 가
    # 어쩌다 길이 비정상이어도 UI 는 20×10 보장.
    visible = assigns.board |> Enum.drop(2) |> Enum.take(20)
    pending_capped = min(assigns.pending, 20)
    assigns = assign(assigns, visible: visible, pending_capped: pending_capped)

    ~H"""
    <div class="inline-flex bg-base-300 p-1 gap-px">
      <!-- pending garbage spoiler bar — board 좌측, 받을 양만큼 빨갛게 채움. 아래부터 위로. -->
      <div class="flex flex-col-reverse w-1.5 bg-base-100 overflow-hidden">
        <%= for _ <- 1..max(@pending_capped, 1)//1 do %>
          <%= if @pending_capped > 0 do %>
            <div class="h-5 bg-error animate-pulse"></div>
          <% end %>
        <% end %>
      </div>
      <div>
        <%= for row <- @visible do %>
          <div class="flex">
            <%= for cell <- row do %>
              <div class={["w-5 h-5", cell_color(cell), grid_class(@grid)]}></div>
            <% end %>
          </div>
        <% end %>
      </div>
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

  # Ghost — piece 와 같은 색이지만 50% opacity + 두꺼운 윤곽선. 잘 보임.
  defp cell_color({:ghost, :i}), do: "bg-cyan-400/40 border-2 border-cyan-300"
  defp cell_color({:ghost, :o}), do: "bg-yellow-400/40 border-2 border-yellow-300"
  defp cell_color({:ghost, :t}), do: "bg-purple-500/40 border-2 border-purple-300"
  defp cell_color({:ghost, :s}), do: "bg-green-500/40 border-2 border-green-300"
  defp cell_color({:ghost, :z}), do: "bg-red-500/40 border-2 border-red-300"
  defp cell_color({:ghost, :l}), do: "bg-orange-500/40 border-2 border-orange-300"
  defp cell_color({:ghost, :j}), do: "bg-blue-500/40 border-2 border-blue-300"
  defp cell_color({:ghost, _}), do: "bg-base-200 border-2 border-base-content/60"

  defp cell_color(_), do: "bg-base-100"

  attr :result, :map, required: true
  attr :player_id, :string, required: true

  defp game_over_panel(assigns) do
    winner = Map.get(assigns.result, :winner)
    me_won? = is_binary(winner) and winner == assigns.player_id
    summary = Map.get(assigns.result, :winners_summary, [])
    assigns = assign(assigns, winner: winner, me_won?: me_won?, summary: summary)

    ~H"""
    <div class={[
      "rounded-lg border-2 p-4 mb-4",
      if(@me_won?, do: "bg-success/20 border-success", else: "bg-base-200 border-base-300")
    ]}>
      <div class="flex items-center justify-between gap-3 mb-3">
        <div class="text-lg font-bold">
          <%= cond do %>
            <% @me_won? -> %>
              🏆 승리!
            <% is_binary(@winner) -> %>
              😢 패배
            <% true -> %>
              💀 게임 종료
          <% end %>
        </div>
        <button phx-click="restart" class="btn btn-primary btn-sm">🔄 다시 하기</button>
      </div>

      <%= if @summary != [] do %>
        <div class="text-sm">
          <div class="font-semibold text-base-content/70 mb-1">방 누적 우승</div>
          <div class="flex flex-wrap gap-2">
            <%= for entry <- @summary do %>
              <span class="badge badge-lg">
                {entry.nickname} · <strong class="ml-1">{entry.wins}회</strong>
              </span>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
