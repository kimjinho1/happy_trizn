defmodule HappyTriznWeb.GameSettingsLive do
  @moduledoc """
  사용자 게임 옵션 페이지.

  - `/settings/games` — 게임 목록 + 옵션 링크.
  - `/settings/games/:game_type` — 해당 게임 옵션 폼 (key bindings + DAS/ARR/grid/...).

  게스트는 (user=nil) DB 저장 안 함 → 화면은 보이되 저장 비활성, localStorage 활용 안내.
  """

  use HappyTriznWeb, :live_view

  alias HappyTrizn.UserGameSettings
  alias HappyTrizn.Games.Registry, as: GameRegistry

  @impl true
  def mount(_params, _session, socket) do
    nickname = socket.assigns[:current_nickname]

    cond do
      is_nil(nickname) ->
        {:ok, socket |> put_flash(:error, "먼저 입장하세요.") |> redirect(to: ~p"/")}

      true ->
        {:ok, assign(socket, :nickname, nickname)}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case socket.assigns.live_action do
      :index ->
        games = list_games()
        {:noreply, socket |> assign(:games, games) |> assign(:page_title, "게임 옵션")}

      :show ->
        game_type = params["game_type"]

        if GameRegistry.valid_slug?(game_type) do
          settings = UserGameSettings.get_for(socket.assigns[:current_user], game_type)
          meta = GameRegistry.get_meta(game_type)

          {:noreply,
           socket
           |> assign(:game_type, game_type)
           |> assign(:meta, meta)
           |> assign(:settings, settings)
           |> assign(:page_title, "#{meta.name} 옵션")}
        else
          {:noreply, socket |> put_flash(:error, "없는 게임") |> redirect(to: ~p"/settings/games")}
        end
    end
  end

  # ============================================================================
  # Save key binding (single action, multi-key)
  # ============================================================================

  @impl true
  def handle_event("save_binding", %{"action" => action, "keys" => keys_str}, socket) do
    user = socket.assigns[:current_user]

    if is_nil(user) do
      {:noreply, put_flash(socket, :error, "게스트는 옵션 저장 불가 (브라우저 임시 저장만)")}
    else
      keys = UserGameSettings.parse_keys_input(keys_str)

      new_bindings = Map.put(socket.assigns.settings.bindings, action, keys)

      case UserGameSettings.upsert(user, socket.assigns.game_type, %{
             key_bindings: new_bindings,
             options: socket.assigns.settings.options
           }) do
        {:ok, _} ->
          settings = UserGameSettings.get_for(user, socket.assigns.game_type)
          {:noreply, socket |> assign(:settings, settings) |> put_flash(:info, "저장됨")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "저장 실패")}
      end
    end
  end

  def handle_event("save_options", params, socket) do
    user = socket.assigns[:current_user]

    if is_nil(user) do
      {:noreply, put_flash(socket, :error, "게스트는 옵션 저장 불가")}
    else
      raw = Map.get(params, "options", %{})
      base = socket.assigns.settings.options

      new_options =
        Enum.reduce(raw, base, fn {k, v}, acc ->
          Map.put(acc, k, normalize_option_value(k, v))
        end)

      case UserGameSettings.upsert(user, socket.assigns.game_type, %{
             key_bindings: socket.assigns.settings.bindings,
             options: new_options
           }) do
        {:ok, _} ->
          settings = UserGameSettings.get_for(user, socket.assigns.game_type)
          {:noreply, socket |> assign(:settings, settings) |> put_flash(:info, "저장됨")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "저장 실패")}
      end
    end
  end

  def handle_event("reset", _, socket) do
    user = socket.assigns[:current_user]

    if is_nil(user) do
      {:noreply, put_flash(socket, :error, "게스트는 reset 불가")}
    else
      :ok = UserGameSettings.reset(user, socket.assigns.game_type)
      settings = UserGameSettings.get_for(user, socket.assigns.game_type)
      {:noreply, socket |> assign(:settings, settings) |> put_flash(:info, "초기화 완료")}
    end
  end

  # ============================================================================
  # Render
  # ============================================================================

  @impl true
  def render(%{live_action: :index} = assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto p-3 sm:p-6">
      <Layouts.flash_group flash={@flash} />
      <header class="mb-6">
        <h1 class="text-2xl font-bold">게임 옵션</h1>
        <p class="text-sm text-base-content/60">게임별로 키 바인딩 / 속도 / 표시 옵션을 설정하세요.</p>
      </header>

      <section class="mb-8">
        <h2 class="text-lg font-semibold mb-2">테마</h2>
        <p class="text-xs text-base-content/60 mb-3">브라우저에 저장됩니다. 로그인 안 해도 적용.</p>
        <Layouts.theme_picker />
      </section>

      <section>
        <h2 class="text-lg font-semibold mb-3">게임별 옵션</h2>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <%= for game <- @games do %>
            <.link
              navigate={~p"/settings/games/#{game.slug}"}
              class="card bg-base-200 hover:bg-base-300"
            >
              <div class="card-body p-4">
                <h3 class="font-semibold">{game.name}</h3>
                <p class="text-xs text-base-content/60">{game.description}</p>
              </div>
            </.link>
          <% end %>
        </div>
      </section>
    </div>
    """
  end

  def render(%{live_action: :show, game_type: "tetris"} = assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto p-3 sm:p-6">
      <Layouts.flash_group flash={@flash} />
      <header class="mb-6 flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold">{@meta.name} 옵션</h1>
          <%= if is_nil(@current_user) do %>
            <p class="text-warning text-sm">게스트는 변경 후 저장 안 됨 (브라우저 다시 열면 초기화).</p>
          <% end %>
        </div>
        <.link navigate={~p"/settings/games"} class="btn btn-ghost btn-sm">← 게임 목록</.link>
      </header>

      <section class="mb-6">
        <h2 class="text-lg font-semibold mb-2">키 바인딩</h2>
        <p class="text-xs text-base-content/60 mb-3">
          여러 키 콤마(,)로 구분. 예: <code>ArrowLeft, j</code>
        </p>
        <div class="space-y-2">
          <%= for {action, label} <- tetris_actions() do %>
            <form phx-submit="save_binding" class="flex items-center gap-2">
              <label class="w-32 text-sm">{label}</label>
              <input type="hidden" name="action" value={action} />
              <input
                type="text"
                name="keys"
                value={display_keys(@settings.bindings[action] || [])}
                class="input input-bordered input-sm flex-1"
                disabled={is_nil(@current_user)}
              />
              <button type="submit" class="btn btn-sm btn-primary" disabled={is_nil(@current_user)}>
                저장
              </button>
            </form>
          <% end %>
        </div>
      </section>

      <section class="mb-6">
        <h2 class="text-lg font-semibold mb-2">게임 설정</h2>
        <form phx-submit="save_options" class="space-y-3">
          <div class="grid grid-cols-2 gap-3">
            <label class="label">
              <span class="label-text">DAS (ms): {@settings.options["das"]}</span>
              <input
                type="number"
                name="options[das]"
                min="0"
                max="500"
                value={@settings.options["das"]}
                class="input input-bordered input-sm"
              />
            </label>
            <label class="label">
              <span class="label-text">ARR (ms): {@settings.options["arr"]}</span>
              <input
                type="number"
                name="options[arr]"
                min="0"
                max="100"
                value={@settings.options["arr"]}
                class="input input-bordered input-sm"
              />
            </label>
            <label class="label">
              <span class="label-text">소프트드롭 속도</span>
              <select name="options[soft_drop_speed]" class="select select-bordered select-sm">
                <%= for s <- ~w(slow medium fast very_fast instant) do %>
                  <option value={s} selected={@settings.options["soft_drop_speed"] == s}>{s}</option>
                <% end %>
              </select>
            </label>
            <label class="label">
              <span class="label-text">그리드</span>
              <select name="options[grid]" class="select select-bordered select-sm">
                <%= for g <- ~w(none standard partial vertical full) do %>
                  <option value={g} selected={@settings.options["grid"] == g}>{g}</option>
                <% end %>
              </select>
            </label>
            <label class="label">
              <span class="label-text">블록 스킨</span>
              <select name="options[block_skin]" class="select select-bordered select-sm">
                <%= for s <- ~w(default_jstris vivid monochrome neon) do %>
                  <option value={s} selected={@settings.options["block_skin"] == s}>{s}</option>
                <% end %>
              </select>
            </label>
            <label class="label">
              <span class="label-text">렌더러</span>
              <select name="options[tetris_renderer]" class="select select-bordered select-sm">
                <%= for r <- ~w(dom canvas) do %>
                  <option value={r} selected={@settings.options["tetris_renderer"] == r}>
                    {r}
                  </option>
                <% end %>
              </select>
            </label>
            <label class="label cursor-pointer">
              <span class="label-text">고스트</span>
              <input
                type="checkbox"
                name="options[ghost]"
                value="true"
                checked={@settings.options["ghost"]}
                class="checkbox checkbox-sm"
              />
            </label>
            <label class="label">
              <span class="label-text">사운드 볼륨: {@settings.options["sound_volume"]}%</span>
              <input
                type="range"
                name="options[sound_volume]"
                min="0"
                max="100"
                value={@settings.options["sound_volume"]}
                class="range range-sm"
              />
            </label>
          </div>

          <div class="flex gap-2">
            <button type="submit" class="btn btn-primary btn-sm" disabled={is_nil(@current_user)}>
              옵션 저장
            </button>
            <button
              type="button"
              phx-click="reset"
              class="btn btn-ghost btn-sm"
              disabled={is_nil(@current_user)}
              data-confirm="정말 초기화?"
            >
              초기화
            </button>
          </div>
        </form>
      </section>
    </div>
    """
  end

  def render(assigns) do
    # 다른 게임 — 제너릭 폼: bindings 각 action 별 text input + options 각 key 별 text/checkbox.
    ~H"""
    <div class="max-w-3xl mx-auto p-3 sm:p-6">
      <Layouts.flash_group flash={@flash} />
      <header class="mb-6 flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold">{@meta.name} 옵션</h1>
          <%= if is_nil(@current_user) do %>
            <p class="text-warning text-sm">게스트는 변경 후 저장 안 됨.</p>
          <% end %>
        </div>
        <.link navigate={~p"/settings/games"} class="btn btn-ghost btn-sm">← 게임 목록</.link>
      </header>

      <%= if map_size(@settings.bindings) > 0 do %>
        <section class="mb-6">
          <h2 class="text-lg font-semibold mb-2">키 바인딩</h2>
          <p class="text-xs text-base-content/60 mb-3">여러 키 콤마(,)로 구분.</p>
          <div class="space-y-2">
            <%= for action <- @settings.bindings |> Map.keys() |> Enum.sort() do %>
              <form phx-submit="save_binding" class="flex items-center gap-2">
                <label class="w-32 text-sm">{action}</label>
                <input type="hidden" name="action" value={action} />
                <input
                  type="text"
                  name="keys"
                  value={display_keys(@settings.bindings[action] || [])}
                  class="input input-bordered input-sm flex-1"
                  disabled={is_nil(@current_user)}
                />
                <button type="submit" class="btn btn-sm btn-primary" disabled={is_nil(@current_user)}>
                  저장
                </button>
              </form>
            <% end %>
          </div>
        </section>
      <% end %>

      <%= if map_size(@settings.options) > 0 do %>
        <section class="mb-6">
          <h2 class="text-lg font-semibold mb-2">게임 설정</h2>
          <form phx-submit="save_options" class="space-y-2">
            <%= for {k, v} <- @settings.options |> Enum.sort_by(&elem(&1, 0)) do %>
              <label class="flex items-center gap-2">
                <span class="w-40 text-sm">{k}</span>
                <%= cond do %>
                  <% is_boolean(v) -> %>
                    <input type="hidden" name={"options[#{k}]"} value="false" />
                    <input
                      type="checkbox"
                      name={"options[#{k}]"}
                      value="true"
                      checked={v}
                      class="checkbox checkbox-sm"
                      disabled={is_nil(@current_user)}
                    />
                  <% true -> %>
                    <input
                      type="text"
                      name={"options[#{k}]"}
                      value={to_string(v)}
                      class="input input-bordered input-sm flex-1"
                      disabled={is_nil(@current_user)}
                    />
                <% end %>
              </label>
            <% end %>

            <div class="flex gap-2 pt-2">
              <button type="submit" class="btn btn-primary btn-sm" disabled={is_nil(@current_user)}>
                옵션 저장
              </button>
              <button
                type="button"
                phx-click="reset"
                class="btn btn-ghost btn-sm"
                disabled={is_nil(@current_user)}
                data-confirm="정말 초기화?"
              >
                초기화
              </button>
            </div>
          </form>
        </section>
      <% end %>

      <%= if map_size(@settings.bindings) == 0 and map_size(@settings.options) == 0 do %>
        <p class="text-base-content/60">이 게임의 옵션은 추후 추가 예정.</p>
      <% end %>
    </div>
    """
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp list_games do
    GameRegistry.list_all()
  end

  defp tetris_actions do
    [
      {"move_left", "왼쪽 이동"},
      {"move_right", "오른쪽 이동"},
      {"soft_drop", "소프트 드랍"},
      {"hard_drop", "하드 드랍"},
      {"rotate_cw", "오른쪽 회전"},
      {"rotate_ccw", "왼쪽 회전"},
      {"rotate_180", "180 회전"},
      {"hold", "홀드"},
      {"pause", "일시정지"}
    ]
  end

  defp display_keys(keys), do: UserGameSettings.display_keys(keys)
  defp normalize_option_value(k, v), do: UserGameSettings.normalize_option_value(k, v)
end
