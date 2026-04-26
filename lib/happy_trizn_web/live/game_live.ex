defmodule HappyTriznWeb.GameLive do
  @moduledoc """
  싱글 게임 진입점 (`/play/:game_type`).

  GameRegistry 에서 모듈 dispatch + GameBehaviour state 를 LiveView assign 으로 보유.
  사용자 옵션 (UserGameSettings) → init/1 config 로 주입 (board_size / difficulty).

  멀티 게임은 GameMultiLive (Sprint 3b 부터).
  """

  use HappyTriznWeb, :live_view

  alias HappyTrizn.Games.Registry, as: GameRegistry
  alias HappyTrizn.UserGameSettings

  @impl true
  def mount(%{"game_type" => slug}, _session, socket) do
    nickname = socket.assigns[:current_nickname]

    cond do
      is_nil(nickname) ->
        {:ok, socket |> put_flash(:error, "먼저 입장하세요.") |> redirect(to: ~p"/")}

      not GameRegistry.valid_slug?(slug) ->
        {:ok, socket |> put_flash(:error, "없는 게임") |> redirect(to: ~p"/lobby")}

      true ->
        meta = GameRegistry.get_meta(slug)

        if meta.mode != :single do
          {:ok, socket |> put_flash(:error, "이 게임은 멀티 — 방을 만들어 주세요") |> redirect(to: ~p"/lobby")}
        else
          module = GameRegistry.get_module(slug)
          settings = UserGameSettings.get_for(socket.assigns[:current_user], slug)
          options = settings.options
          bindings = settings.bindings
          {:ok, game_state} = module.init(options)
          # 싱글 게임은 player_id = nickname.
          {:ok, game_state, _} = module.handle_player_join(nickname, %{}, game_state)

          # tick_interval_ms 가 있는 게임 (Pac-Man 등) — LiveView 안에서 직접 timer.
          # Multi 게임은 GameSession 이 처리. 싱글은 GameLive 가 tick 발행.
          if connected?(socket) and Map.get(meta, :tick_interval_ms) do
            :timer.send_interval(meta.tick_interval_ms, self(), :game_tick)
          end

          {:ok,
           socket
           |> assign(:slug, slug)
           |> assign(:meta, meta)
           |> assign(:module, module)
           |> assign(:game_state, game_state)
           |> assign(:nickname, nickname)
           |> assign(:options, options)
           |> assign(:bindings, bindings)
           |> assign(:key_settings, settings)
           |> assign(:settings_open, false)
           |> assign(:result, nil)}
        end
    end
  end

  @impl true
  def handle_info(:game_tick, socket) do
    %{module: module, game_state: state} = socket.assigns

    if function_exported?(module, :tick, 1) do
      {:ok, new_state, _bc} = module.tick(state)
      socket = assign(socket, game_state: new_state)

      case module.game_over?(new_state) do
        {:yes, results} -> {:noreply, assign(socket, result: results)}
        :no -> {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def handle_event("input", payload, socket) do
    %{module: module, game_state: state, nickname: nickname} = socket.assigns
    {:ok, new_state, _broadcast} = module.handle_input(nickname, payload, state)

    socket = assign(socket, game_state: new_state)

    case module.game_over?(new_state) do
      {:yes, results} -> {:noreply, assign(socket, result: results)}
      :no -> {:noreply, socket}
    end
  end

  def handle_event("restart", _, socket) do
    %{module: module, nickname: nickname, options: options} = socket.assigns
    {:ok, fresh} = module.init(options)
    {:ok, fresh, _} = module.handle_player_join(nickname, %{}, fresh)
    {:noreply, assign(socket, game_state: fresh, result: nil)}
  end

  # ============================================================================
  # 옵션 모달 (Sprint 4f-3 — game_multi 와 동일 패턴, 페이지 이동 X)
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

          {:noreply,
           socket
           |> assign(:key_settings, new_settings)
           |> assign(:bindings, new_settings.bindings)
           |> put_flash(:info, "저장됨")}

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
           |> assign(:options, new_settings.options)
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

      {:noreply,
       socket
       |> assign(:key_settings, new_settings)
       |> assign(:bindings, new_settings.bindings)
       |> assign(:options, new_settings.options)
       |> put_flash(:info, "초기화 완료")}
    end
  end

  def handle_event("keydown", %{"key" => key}, socket) do
    case key_to_action(socket.assigns.slug, key, socket.assigns[:bindings] || %{}) do
      nil ->
        {:noreply, socket}

      payload ->
        %{module: module, game_state: state, nickname: nickname} = socket.assigns
        {:ok, new_state, _} = module.handle_input(nickname, payload, state)
        socket = assign(socket, game_state: new_state)

        case module.game_over?(new_state) do
          {:yes, results} -> {:noreply, assign(socket, result: results)}
          :no -> {:noreply, socket}
        end
    end
  end

  # ============================================================================
  # 키보드 → input action map (싱글 게임)
  # ============================================================================

  # 2048 — 화살표 + WASD + HJKL.
  defp key_to_action("2048", k, _) when k in ~w(ArrowUp w W k K),
    do: %{"action" => "move", "dir" => "up"}

  defp key_to_action("2048", k, _) when k in ~w(ArrowDown s S j J),
    do: %{"action" => "move", "dir" => "down"}

  defp key_to_action("2048", k, _) when k in ~w(ArrowLeft a A h H),
    do: %{"action" => "move", "dir" => "left"}

  defp key_to_action("2048", k, _) when k in ~w(ArrowRight d D l L),
    do: %{"action" => "move", "dir" => "right"}

  # Pac-Man — 화살표 + WASD.
  defp key_to_action("pacman", k, _) when k in ~w(ArrowUp w W),
    do: %{"action" => "set_dir", "dir" => "up"}

  defp key_to_action("pacman", k, _) when k in ~w(ArrowDown s S),
    do: %{"action" => "set_dir", "dir" => "down"}

  defp key_to_action("pacman", k, _) when k in ~w(ArrowLeft a A),
    do: %{"action" => "set_dir", "dir" => "left"}

  defp key_to_action("pacman", k, _) when k in ~w(ArrowRight d D),
    do: %{"action" => "set_dir", "dir" => "right"}

  # 지뢰찾기 (Sprint 4f) — bindings 기반. 사용자 옵션에서 변경한 키 즉시 반영.
  defp key_to_action("minesweeper", key, bindings) do
    cond do
      key in Map.get(bindings, "move_up", []) ->
        %{"action" => "move_cursor", "dir" => "up"}

      key in Map.get(bindings, "move_down", []) ->
        %{"action" => "move_cursor", "dir" => "down"}

      key in Map.get(bindings, "move_left", []) ->
        %{"action" => "move_cursor", "dir" => "left"}

      key in Map.get(bindings, "move_right", []) ->
        %{"action" => "move_cursor", "dir" => "right"}

      key in Map.get(bindings, "reveal", []) ->
        %{"action" => "reveal_cursor"}

      key in Map.get(bindings, "flag", []) ->
        %{"action" => "flag_cursor"}

      true ->
        nil
    end
  end

  defp key_to_action(_, _, _), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={"game-page-#{@slug}"}
      phx-hook="GameKeyCapture"
      data-keys="ArrowUp,ArrowDown,ArrowLeft,ArrowRight,w,W,a,A,s,S,d,D,h,H,j,J,k,K,l,L,f,F, ,Spacebar,Enter"
      class="min-h-screen p-3 sm:p-6 max-w-3xl mx-auto"
    >
      <header class="flex items-center justify-between mb-4">
        <h1 class="text-2xl font-bold">{@meta.name}</h1>
        <div class="flex items-center gap-2">
          <span class="text-sm text-base-content/70">{@nickname}</span>
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

      <%= if @result do %>
        <div class="alert alert-success mb-4">
          <span>게임 종료! {format_result(@result)}</span>
          <button phx-click="restart" class="btn btn-sm">다시 하기</button>
        </div>
      <% end %>

      <div id={"game-#{@slug}"}>
        <.game_view slug={@slug} state={@game_state} />
      </div>

      <p class="text-xs text-base-content/40 mt-4">
        ⚙️ 옵션 클릭 → 모달에서 즉시 변경 (옵션 저장 시 자동 적용).
      </p>

      <%= if @settings_open do %>
        <.settings_modal slug={@slug} settings={@key_settings} />
      <% end %>
    </div>
    """
  end

  # ============================================================================
  # 옵션 모달 (Sprint 4f-3 — game_multi 와 동일 패턴, 코드는 모두 단일 게임용)
  # ============================================================================

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
                    value={UserGameSettings.display_keys(@settings.bindings[action] || [])}
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

  # ============================================================================
  # 게임별 partial (server-rendered HTML, JS hook 이 꾸밈)
  # ============================================================================

  defp game_view(%{slug: "2048"} = assigns) do
    ~H"""
    <div class="space-y-2">
      <div class="text-lg">점수: <strong>{@state.score}</strong> · 보드: {@state.size}×{@state.size}</div>
      <div
        class="grid gap-1 bg-base-300 p-1 w-fit"
        style={"grid-template-columns: repeat(#{@state.size}, minmax(0, 1fr))"}
      >
        <%= for row <- @state.board, cell <- row do %>
          <div class={[
            "w-16 h-16 flex items-center justify-center text-xl font-bold rounded",
            if(cell, do: "bg-warning text-base-100", else: "bg-base-200 text-base-content/30")
          ]}>
            {cell || ""}
          </div>
        <% end %>
      </div>
      <div class="grid grid-cols-3 gap-2 w-48 text-sm">
        <div></div>
        <button phx-click="input" phx-value-action="move" phx-value-dir="up" class="btn btn-sm">
          ↑
        </button>
        <div></div>
        <button phx-click="input" phx-value-action="move" phx-value-dir="left" class="btn btn-sm">
          ←
        </button>
        <button phx-click="input" phx-value-action="move" phx-value-dir="down" class="btn btn-sm">
          ↓
        </button>
        <button phx-click="input" phx-value-action="move" phx-value-dir="right" class="btn btn-sm">
          →
        </button>
      </div>
      <div class="text-xs text-base-content/50">
        키: 화살표 / WASD / HJKL · 버튼 클릭도 동작.
      </div>
    </div>
    """
  end

  defp game_view(%{slug: "minesweeper"} = assigns) do
    {cur_r, cur_c} = Map.get(assigns.state, :cursor, {0, 0})
    assigns = assign(assigns, cur_r: cur_r, cur_c: cur_c)

    ~H"""
    <div class="space-y-2">
      <div class="text-sm">
        {@state.rows}×{@state.cols} · 지뢰 {@state.mine_count}개
        <%= if @state.difficulty do %>
          ({@state.difficulty})
        <% end %>
      </div>
      <div class="text-xs text-base-content/60">
        키: 화살표 cursor 이동 · Space/Enter reveal · F flag · 우클릭 flag · 좌클릭 reveal
      </div>
      <div class="inline-block bg-base-300 p-1 overflow-auto max-w-full">
        <%= for r <- 0..(@state.rows - 1) do %>
          <div class="flex">
            <%= for c <- 0..(@state.cols - 1) do %>
              <% cell = Map.fetch!(@state.cells, {r, c}) %>
              <% cursor? = r == @cur_r and c == @cur_c %>
              <%= cond do %>
                <% cell.revealed and cell.mine -> %>
                  <div class={[
                    "w-7 h-7 bg-error text-base-100 flex items-center justify-center text-xs font-bold border border-base-100",
                    cursor? && "outline outline-2 outline-primary -outline-offset-2"
                  ]}>
                    💣
                  </div>
                <% cell.revealed -> %>
                  <div class={[
                    "w-7 h-7 bg-base-200 flex items-center justify-center text-xs border border-base-100",
                    cursor? && "outline outline-2 outline-primary -outline-offset-2"
                  ]}>
                    {if cell.neighbors > 0, do: cell.neighbors, else: ""}
                  </div>
                <% cell.flagged -> %>
                  <button
                    phx-click="input"
                    phx-value-action="flag"
                    phx-value-r={r}
                    phx-value-c={c}
                    class={[
                      "w-7 h-7 bg-warning flex items-center justify-center text-xs border border-base-100",
                      cursor? && "outline outline-2 outline-primary -outline-offset-2"
                    ]}
                    title="좌클릭 = flag 해제"
                  >
                    🚩
                  </button>
                <% true -> %>
                  <button
                    phx-click="input"
                    phx-value-action="reveal"
                    phx-value-r={r}
                    phx-value-c={c}
                    phx-hook="MinesweeperCell"
                    id={"ms-#{r}-#{c}"}
                    data-r={r}
                    data-c={c}
                    class={[
                      "w-7 h-7 bg-base-100 hover:bg-base-content/10 border border-base-300",
                      cursor? && "outline outline-2 outline-primary -outline-offset-2"
                    ]}
                  >
                  </button>
              <% end %>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp game_view(%{slug: "pacman"} = assigns) do
    s = assigns.state
    # 캔버스에 그릴 압축 payload — JSON 직렬화 위해 tuple → list.
    walls = MapSet.to_list(s.walls) |> Enum.map(fn {r, c} -> [r, c] end)
    dots = MapSet.to_list(s.dots) |> Enum.map(fn {r, c} -> [r, c] end)
    pellets = MapSet.to_list(s.pellets) |> Enum.map(fn {r, c} -> [r, c] end)
    door = if s.ghost_door, do: [elem(s.ghost_door, 0), elem(s.ghost_door, 1)], else: nil

    ghosts =
      Enum.map(s.ghosts, fn {id, g} ->
        %{
          id: id,
          row: g.row,
          col: g.col,
          dir: g.dir,
          mode: g.mode
        }
      end)

    payload = %{
      rows: s.rows,
      cols: s.cols,
      walls: walls,
      dots: dots,
      pellets: pellets,
      door: door,
      pacman: %{
        row: s.pacman.row,
        col: s.pacman.col,
        dir: s.pacman.dir,
        alive: s.status != :dying
      },
      ghosts: ghosts,
      frightened: s.frightened_ticks > 0,
      tick_no: s.tick_no
    }

    assigns =
      assign(assigns,
        score: s.score,
        lives: s.lives,
        level: s.level,
        status: s.status,
        payload: payload
      )

    ~H"""
    <div class="space-y-3">
      <div class="flex items-center gap-4 text-sm">
        <span>점수 <strong class="text-lg">{@score}</strong></span>
        <span>라이프 <strong>{@lives}</strong></span>
        <span>레벨 <strong>{@level}</strong></span>
        <%= if @status == :over do %>
          <span class="badge badge-error">GAME OVER</span>
        <% end %>
      </div>

      <div
        id="pacman-canvas-host"
        phx-hook="PacmanCanvas"
        data-payload={Jason.encode!(@payload)}
        class="bg-black rounded-lg p-1 inline-block ring-2 ring-blue-900"
      >
        <canvas id="pacman-canvas" width="560" height="620" class="block"></canvas>
      </div>

      <p class="text-xs text-base-content/50">
        화살표 / WASD — 이동. 점수: dot 10, pellet 50, frightened ghost 200/400/800/1600.
      </p>
    </div>
    """
  end

  defp game_view(assigns) do
    ~H"""
    <div class="text-base-content/60">{@slug}: 풀 구현 예정.</div>
    """
  end

  defp format_result(%{score: s, won: w}), do: "score=#{s}, won=#{w}"
  defp format_result(%{result: r, elapsed_seconds: e}), do: "#{r} (#{e}s)"
  defp format_result(other), do: inspect(other)
end
