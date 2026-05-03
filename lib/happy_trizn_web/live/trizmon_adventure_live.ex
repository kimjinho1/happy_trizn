defmodule HappyTriznWeb.TrizmonAdventureLive do
  @moduledoc """
  Trizmon 모험 모드 (Sprint 5c-3a).

  Tile-based 2D canvas. 화살표 / WASD 입력 → server move + 충돌 체크 + save 갱신.
  야생 인카운터 / NPC = 5c-3b/c. 현재 5c-3a smoke = 단순 grid 돌아다니기.

  spec: docs/TRIZMON_SPEC.md §9
  """

  use HappyTriznWeb, :live_view

  alias HappyTrizn.Trizmon.{Saves, World}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns[:current_user]

    cond do
      is_nil(user) ->
        {:ok,
         socket
         |> put_flash(:error, "Trizmon 모험은 로그인 사용자만. @trizn.kr 가입 필요.")
         |> redirect(to: ~p"/lobby")}

      true ->
        save = Saves.get_or_init!(user)
        map = World.get_map(save.current_map)

        {:ok,
         socket
         |> assign(:user, user)
         |> assign(:save, save)
         |> assign(:map, map)
         |> assign(:player_dir, "down")
         |> assign(:last_msg, nil)
         |> assign(:page_title, "Trizmon — 모험: #{map.name}")}
    end
  end

  @impl true
  def handle_event("move", %{"dir" => dir_str}, socket) do
    dir = parse_dir(dir_str)
    save = socket.assigns.save
    map = socket.assigns.map

    case World.try_move(map, save.player_x, save.player_y, dir) do
      {:ok, nx, ny} ->
        new_save = Saves.update_position!(save, nx, ny)

        # Sprint 5c-3b — 야생 인카운터 roll. tall_grass + 8% 확률.
        case World.roll_encounter(map, nx, ny) do
          nil ->
            {:noreply,
             socket
             |> assign(:save, new_save)
             |> assign(:player_dir, Atom.to_string(dir))
             |> assign(:last_msg, nil)}

          species_slug ->
            {:noreply,
             socket
             |> assign(:save, new_save)
             |> assign(:player_dir, Atom.to_string(dir))
             |> put_flash(:info, "야생 트리즈몬이 나타났다!")
             |> redirect(to: ~p"/trizmon/battle?wild=#{species_slug}")}
        end

      :blocked ->
        {:noreply,
         socket
         |> assign(:player_dir, Atom.to_string(dir))
         |> assign(:last_msg, "막혔다.")}
    end
  end

  def handle_event("keydown", %{"key" => key}, socket) do
    case key_to_dir(key) do
      nil -> {:noreply, socket}
      dir -> handle_event("move", %{"dir" => dir}, socket)
    end
  end

  def handle_event("reset_save", _, socket) do
    save = Saves.reset!(socket.assigns.user)
    map = World.get_map(save.current_map)

    {:noreply,
     socket
     |> assign(:save, save)
     |> assign(:map, map)
     |> assign(:player_dir, "down")
     |> assign(:last_msg, "리셋 완료.")}
  end

  defp parse_dir("up"), do: :up
  defp parse_dir("down"), do: :down
  defp parse_dir("left"), do: :left
  defp parse_dir("right"), do: :right
  defp parse_dir(_), do: :down

  defp key_to_dir(k) when k in ~w(ArrowUp w W k K), do: "up"
  defp key_to_dir(k) when k in ~w(ArrowDown s S j J), do: "down"
  defp key_to_dir(k) when k in ~w(ArrowLeft a A h H), do: "left"
  defp key_to_dir(k) when k in ~w(ArrowRight d D l L), do: "right"
  defp key_to_dir(_), do: nil

  @impl true
  def render(assigns) do
    payload = %{
      map: World.render_payload(assigns.map),
      player: %{
        x: assigns.save.player_x,
        y: assigns.save.player_y,
        dir: assigns.player_dir
      }
    }

    assigns = assign(assigns, :payload, payload)

    ~H"""
    <div
      id={"trizmon-adventure-page"}
      phx-hook="GameKeyCapture"
      data-keys="ArrowUp,ArrowDown,ArrowLeft,ArrowRight,w,W,a,A,s,S,d,D,h,H,j,J,k,K,l,L"
      class="max-w-4xl mx-auto p-3 sm:p-6"
    >
      <Layouts.flash_group flash={@flash} />
      <header class="mb-4 flex items-center justify-between flex-wrap gap-2">
        <div>
          <h1 class="text-2xl font-bold">🐉 Trizmon — 모험</h1>
          <p class="text-xs text-base-content/60">
            맵: {@map.name} · 위치: ({@save.player_x}, {@save.player_y})
          </p>
        </div>
        <div class="flex gap-2">
          <.link navigate={~p"/trizmon"} class="btn btn-ghost btn-sm">← 메뉴</.link>
          <button phx-click="reset_save" data-confirm="진행 초기화?" class="btn btn-ghost btn-sm">
            🗑️ 리셋
          </button>
        </div>
      </header>

      <%= if @last_msg do %>
        <div class="alert alert-info text-sm py-2 mb-2">{@last_msg}</div>
      <% end %>

      <!-- canvas + payload -->
      <div
        id="trizmon-adventure-canvas-host"
        phx-hook="TrizmonAdventureCanvas"
        data-payload={Jason.encode!(@payload)}
        class="bg-black rounded-lg p-1 inline-block ring-2 ring-base-300"
      >
        <canvas id="trizmon-adventure-canvas" class="block"></canvas>
      </div>

      <!-- 모바일 D-pad (화살표) -->
      <section class="mt-4 max-w-xs mx-auto">
        <div class="grid grid-cols-3 gap-2">
          <div></div>
          <button phx-click="move" phx-value-dir="up" class="btn btn-md">↑</button>
          <div></div>
          <button phx-click="move" phx-value-dir="left" class="btn btn-md">←</button>
          <button phx-click="move" phx-value-dir="down" class="btn btn-md">↓</button>
          <button phx-click="move" phx-value-dir="right" class="btn btn-md">→</button>
        </div>
      </section>

      <p class="text-xs text-base-content/50 mt-3">
        키: 화살표 / WASD / HJKL · 풀숲 = 인카운터 가능 (Sprint 5c-3b) · NPC = 대화 (5c-3c)
      </p>
    </div>
    """
  end
end
