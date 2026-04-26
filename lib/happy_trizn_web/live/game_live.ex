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
          options = UserGameSettings.get_for(socket.assigns[:current_user], slug).options
          {:ok, game_state} = module.init(options)
          # 싱글 게임은 player_id = nickname.
          {:ok, game_state, _} = module.handle_player_join(nickname, %{}, game_state)

          {:ok,
           socket
           |> assign(:slug, slug)
           |> assign(:meta, meta)
           |> assign(:module, module)
           |> assign(:game_state, game_state)
           |> assign(:nickname, nickname)
           |> assign(:options, options)
           |> assign(:result, nil)}
        end
    end
  end

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

  def handle_event("keydown", %{"key" => key}, socket) do
    case key_to_action(socket.assigns.slug, key) do
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
  defp key_to_action("2048", k) when k in ~w(ArrowUp w W k K),
    do: %{"action" => "move", "dir" => "up"}

  defp key_to_action("2048", k) when k in ~w(ArrowDown s S j J),
    do: %{"action" => "move", "dir" => "down"}

  defp key_to_action("2048", k) when k in ~w(ArrowLeft a A h H),
    do: %{"action" => "move", "dir" => "left"}

  defp key_to_action("2048", k) when k in ~w(ArrowRight d D l L),
    do: %{"action" => "move", "dir" => "right"}

  defp key_to_action(_, _), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={"game-page-#{@slug}"}
      phx-hook="GameKeyCapture"
      data-keys="ArrowUp,ArrowDown,ArrowLeft,ArrowRight,w,W,a,A,s,S,d,D,h,H,j,J,k,K,l,L"
      class="min-h-screen p-6 max-w-3xl mx-auto"
    >
      <header class="flex items-center justify-between mb-4">
        <h1 class="text-2xl font-bold">{@meta.name}</h1>
        <div class="flex items-center gap-2">
          <span class="text-sm text-base-content/70">{@nickname}</span>
          <.link navigate={~p"/settings/games/#{@slug}"} class="btn btn-ghost btn-sm">⚙️ 옵션</.link>
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
        ⚙️ 옵션 에서 변경 (board 크기 / 난이도). 저장 후 다시 시작 시 적용.
      </p>
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
    ~H"""
    <div class="space-y-2">
      <div class="text-sm">
        {@state.rows}×{@state.cols} · 지뢰 {@state.mine_count}개
        <%= if @state.difficulty do %>
          ({@state.difficulty})
        <% end %>
      </div>
      <div class="inline-block bg-base-300 p-1 overflow-auto max-w-full">
        <%= for r <- 0..(@state.rows - 1) do %>
          <div class="flex">
            <%= for c <- 0..(@state.cols - 1) do %>
              <% cell = Map.fetch!(@state.cells, {r, c}) %>
              <%= cond do %>
                <% cell.revealed and cell.mine -> %>
                  <div class="w-7 h-7 bg-error text-base-100 flex items-center justify-center text-xs font-bold border border-base-100">
                    💣
                  </div>
                <% cell.revealed -> %>
                  <div class="w-7 h-7 bg-base-200 flex items-center justify-center text-xs border border-base-100">
                    {if cell.neighbors > 0, do: cell.neighbors, else: ""}
                  </div>
                <% cell.flagged -> %>
                  <div class="w-7 h-7 bg-warning flex items-center justify-center text-xs border border-base-100">
                    🚩
                  </div>
                <% true -> %>
                  <button
                    phx-click="input"
                    phx-value-action="reveal"
                    phx-value-r={r}
                    phx-value-c={c}
                    class="w-7 h-7 bg-base-100 hover:bg-base-content/10 border border-base-300"
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
    ~H"""
    <div class="text-base-content/60">
      Pac-Man stub. 풀 구현은 Sprint 3g. 점수: {@state.score}, 라이프: {@state.lives}.
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
