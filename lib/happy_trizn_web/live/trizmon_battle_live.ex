defmodule HappyTriznWeb.TrizmonBattleLive do
  @moduledoc """
  Trizmon 1v1 배틀 화면 (Sprint 5c-2c smoke).

  PvE 미러 매치 — 사용자 starter vs CPU (같은 종 미러). 6vs6 team / format
  picker / PvP / 모험 = 5c-2b 이후.

  spec: docs/TRIZMON_SPEC.md §7
  """

  use HappyTriznWeb, :live_view

  alias HappyTrizn.Trizmon.Battle.Engine
  alias HappyTrizn.Trizmon.Party

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns[:current_user]

    cond do
      is_nil(user) ->
        {:ok, socket |> put_flash(:error, "Trizmon 은 로그인 사용자만. @trizn.kr 가입 필요.") |> redirect(to: ~p"/lobby")}

      true ->
        my_instance = Party.ensure_starter!(user)
        my_mon = Party.to_battle_mon(my_instance)
        cpu_mon = build_cpu_mirror(my_mon)

        engine = Engine.new(my_mon, cpu_mon)

        {:ok,
         socket
         |> assign(:user, user)
         |> assign(:engine, engine)
         |> assign(:difficulty, :easy)
         |> assign(:page_title, "Trizmon — 1v1 배틀")}
    end
  end

  @impl true
  def handle_event("use_move", %{"idx" => idx_str}, socket) do
    idx = String.to_integer(idx_str)
    engine = socket.assigns.engine

    if engine.status == :ended do
      {:noreply, socket}
    else
      move = Enum.at(engine.a.moves, idx)

      if move && move.pp > 0 do
        action = {:move, idx, %{priority: move.priority}}
        new_engine = Engine.submit_player_and_resolve(engine, action, socket.assigns.difficulty)
        {:noreply, assign(socket, :engine, new_engine)}
      else
        {:noreply, put_flash(socket, :error, "PP 가 없거나 잘못된 기술")}
      end
    end
  end

  def handle_event("restart", _, socket) do
    user = socket.assigns.user
    my_instance = Party.ensure_starter!(user)
    my_mon = Party.to_battle_mon(my_instance)
    cpu_mon = build_cpu_mirror(my_mon)
    engine = Engine.new(my_mon, cpu_mon)
    {:noreply, assign(socket, :engine, engine)}
  end

  def handle_event("set_difficulty", %{"difficulty" => d}, socket) do
    diff =
      case d do
        "easy" -> :easy
        "normal" -> :normal
        "hard" -> :hard
        _ -> :easy
      end

    {:noreply, assign(socket, :difficulty, diff)}
  end

  # CPU 는 같은 종 미러 — 5c-2d 부터 다양한 종 random pick.
  defp build_cpu_mirror(my_mon) do
    %{my_mon | name: "야생 #{my_mon.name}", instance_id: nil}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto p-3 sm:p-6">
      <Layouts.flash_group flash={@flash} />
      <header class="mb-4">
        <h1 class="text-2xl font-bold">🐉 Trizmon — 1v1 배틀 (smoke)</h1>
        <p class="text-xs text-base-content/60">
          5c-2c smoke. 미러 매치. 6vs6 / 다양 종 / 이미지 = 후속 Sprint.
        </p>
      </header>

      <!-- 난이도 picker -->
      <section class="mb-3">
        <div class="join">
          <%= for {d, label} <- [{"easy", "easy (random)"}, {"normal", "normal (best dmg)"}, {"hard", "hard (=normal, 5c-late)"}] do %>
            <button
              type="button"
              phx-click="set_difficulty"
              phx-value-difficulty={d}
              class={"btn btn-xs join-item " <> if(to_string(@difficulty) == d, do: "btn-primary", else: "btn-ghost")}
            >
              {label}
            </button>
          <% end %>
        </div>
      </section>

      <!-- 양쪽 mon -->
      <div class="grid grid-cols-2 gap-3 mb-4">
        <.mon_card mon={@engine.b} side="상대" />
        <.mon_card mon={@engine.a} side="내" />
      </div>

      <!-- log -->
      <section class="mb-4">
        <div class="bg-base-200 rounded p-3 max-h-48 overflow-y-auto text-sm font-mono space-y-1">
          <%= for line <- @engine.log do %>
            <div>{line}</div>
          <% end %>
        </div>
      </section>

      <!-- 종료 / 진행 -->
      <%= if @engine.status == :ended do %>
        <div class={"alert mb-3 " <> winner_alert_class(@engine.winner)}>
          <span>
            <%= case @engine.winner do %>
              <% :a -> %>🎉 승리!
              <% :b -> %>💀 패배!
              <% _ -> %>무승부
            <% end %>
          </span>
          <button phx-click="restart" class="btn btn-sm btn-primary">다시 도전</button>
        </div>
      <% else %>
        <section>
          <h2 class="text-lg font-semibold mb-2">기술 선택</h2>
          <div class="grid grid-cols-2 gap-2">
            <%= for {move, idx} <- Enum.with_index(@engine.a.moves) do %>
              <button
                phx-click="use_move"
                phx-value-idx={idx}
                disabled={move.pp <= 0 or @engine.a.fainted?}
                class="btn btn-md btn-outline"
              >
                <span class="font-bold">{move.name_ko}</span>
                <span class="text-xs opacity-70">
                  {type_label(move.type)} · {category_label(move.category)} · PP {move.pp}/{move.max_pp}
                </span>
              </button>
            <% end %>
          </div>
        </section>
      <% end %>
    </div>
    """
  end

  attr :mon, :map, required: true
  attr :side, :string, required: true

  defp mon_card(assigns) do
    ~H"""
    <div class="card bg-base-200 shadow-sm">
      <div class="card-body p-3">
        <div class="flex items-center justify-between">
          <span class="text-xs uppercase opacity-60">{@side}</span>
          <span class="badge badge-sm">Lv {@mon.level}</span>
        </div>
        <div class="font-bold text-lg">{@mon.name}</div>
        <div class="text-xs opacity-60">
          {@mon.types |> Enum.map(&type_label/1) |> Enum.join(" / ")}
        </div>
        <div class="mt-2">
          <div class="text-xs">
            HP {@mon.current_hp} / {@mon.max_hp}
            <%= if @mon.status do %>
              · <span class="badge badge-xs badge-warning">{status_label(@mon.status)}</span>
            <% end %>
          </div>
          <progress
            class={"progress w-full " <> hp_color(@mon.current_hp, @mon.max_hp)}
            value={@mon.current_hp}
            max={@mon.max_hp}
          />
        </div>
      </div>
    </div>
    """
  end

  defp hp_color(hp, max) when max > 0 do
    ratio = hp / max

    cond do
      ratio > 0.5 -> "progress-success"
      ratio > 0.2 -> "progress-warning"
      true -> "progress-error"
    end
  end

  defp hp_color(_, _), do: ""

  defp winner_alert_class(:a), do: "alert-success"
  defp winner_alert_class(:b), do: "alert-error"
  defp winner_alert_class(_), do: "alert-info"

  defp type_label(t), do: HappyTrizn.Trizmon.TypeChart.display_name(t)

  defp category_label(:physical), do: "물리"
  defp category_label(:special), do: "특수"
  defp category_label(:status), do: "변화"
  defp category_label(_), do: ""

  defp status_label(:burn), do: "화상"
  defp status_label(:poison), do: "독"
  defp status_label(:paralysis), do: "마비"
  defp status_label(:sleep), do: "수면"
  defp status_label(:freeze), do: "동결"
  defp status_label(_), do: "?"
end
