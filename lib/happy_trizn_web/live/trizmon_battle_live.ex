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
  def mount(params, _session, socket) do
    user = socket.assigns[:current_user]
    wild_slug = Map.get(params, "wild")
    trainer_id = Map.get(params, "trainer")
    trainer = if trainer_id, do: HappyTrizn.Trizmon.World.npc_by_id(trainer_id), else: nil

    format =
      cond do
        wild_slug -> :"1v1"
        trainer -> length(trainer.party) |> trainer_format()
        true -> parse_format(Map.get(params, "format"))
      end

    cond do
      is_nil(user) ->
        {:ok, socket |> put_flash(:error, "Trizmon 은 로그인 사용자만. @trizn.kr 가입 필요.") |> redirect(to: ~p"/lobby")}

      trainer_id && is_nil(trainer) ->
        {:ok, socket |> put_flash(:error, "트레이너 없음.") |> redirect(to: ~p"/trizmon/adventure")}

      true ->
        engine =
          cond do
            wild_slug -> build_wild_engine(user, wild_slug)
            trainer -> build_trainer_engine(user, trainer, format)
            true -> build_engine(user, format)
          end

        title =
          cond do
            wild_slug -> "Trizmon — 야생 배틀!"
            trainer -> "Trizmon — #{trainer.name}"
            true -> "Trizmon — #{format_label(format)} 배틀"
          end

        {:ok,
         socket
         |> assign(:user, user)
         |> assign(:format, format)
         |> assign(:wild_slug, wild_slug)
         |> assign(:trainer, trainer)
         |> assign(:engine, engine)
         |> assign(:difficulty, :easy)
         |> assign(:page_title, title)}
    end
  end

  defp trainer_format(n) when n <= 1, do: :"1v1"
  defp trainer_format(n) when n <= 3, do: :"3v3"
  defp trainer_format(_), do: :"6v6"

  defp parse_format("3v3"), do: :"3v3"
  defp parse_format("6v6"), do: :"6v6"
  defp parse_format(_), do: :"3v3"

  defp format_label(:"1v1"), do: "1v1"
  defp format_label(:"3v3"), do: "3v3"
  defp format_label(:"6v6"), do: "6v6"
  defp format_label(_), do: "?"

  defp format_size(:"1v1"), do: 1
  defp format_size(:"3v3"), do: 3
  defp format_size(:"6v6"), do: 6
  defp format_size(_), do: 1

  defp build_engine(user, format) do
    size = format_size(format)
    my_team = Party.battle_team(user, size)
    cpu_team = Party.random_team(size, hd(my_team).level)
    Engine.new_team(my_team, cpu_team, format)
  end

  # Sprint 5c-3b — 야생 인카운터 1v1 배틀.
  defp build_wild_engine(user, species_slug) do
    my_team = Party.battle_team(user, 1)
    my_first = hd(my_team)
    cpu = Party.cpu_mon_for_species(species_slug, my_first.level)
    Engine.new_team(my_team, [cpu], :"1v1")
  end

  # Sprint 5c-3c — 트레이너 배틀. 트레이너 party 의 species_slug 들 을 사용자 첫
  # 마리 level 로 in-memory CPU mons 생성.
  defp build_trainer_engine(user, trainer, format) do
    size = format_size(format)
    my_team = Party.battle_team(user, size)
    my_first = hd(my_team)

    cpu_team =
      Enum.map(trainer.party, fn slug ->
        Party.cpu_mon_for_species(slug, my_first.level)
      end)

    Engine.new_team(my_team, cpu_team, format)
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
    engine =
      cond do
        socket.assigns.wild_slug ->
          build_wild_engine(socket.assigns.user, socket.assigns.wild_slug)

        socket.assigns.trainer ->
          build_trainer_engine(socket.assigns.user, socket.assigns.trainer, socket.assigns.format)

        true ->
          build_engine(socket.assigns.user, socket.assigns.format)
      end

    {:noreply, assign(socket, :engine, engine)}
  end

  def handle_event("flee", _, socket) do
    # 야생 도망 — adventure 로 복귀.
    {:noreply, redirect(socket, to: ~p"/trizmon/adventure")}
  end

  def handle_event("set_format", %{"format" => f}, socket) do
    format = parse_format(f)
    engine = build_engine(socket.assigns.user, format)

    {:noreply,
     socket
     |> assign(:format, format)
     |> assign(:engine, engine)
     |> assign(:page_title, "Trizmon — #{format_label(format)} 배틀")}
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

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto p-3 sm:p-6">
      <Layouts.flash_group flash={@flash} />
      <header class="mb-4">
        <h1 class="text-2xl font-bold">
          <%= cond do %>
            <% @wild_slug -> %>🌿 야생 배틀!
            <% @trainer -> %>⚔️ {@trainer.name} 의 도전
            <% true -> %>🐉 Trizmon — {format_label(@format)} 배틀
          <% end %>
        </h1>
        <p class="text-xs text-base-content/60">
          <%= cond do %>
            <% @wild_slug -> %>모험 모드 풀숲에서 야생 트리즈몬과 마주쳤다. (잡기 = 5c-3d)
            <% @trainer -> %>{@trainer.greeting}
            <% true -> %>파티 부족분은 random in-memory fill.
          <% end %>
        </p>
      </header>

      <!-- format + 난이도 picker — wild / trainer 시 format 숨김 (강제) -->
      <section class="mb-3 flex flex-wrap gap-3">
        <%= if !@wild_slug && !@trainer do %>
          <div class="join">
            <%= for {f, label} <- [{"3v3", "3v3"}, {"6v6", "6v6"}] do %>
              <button
                type="button"
                phx-click="set_format"
                phx-value-format={f}
                class={"btn btn-xs join-item " <> if(to_string(@format) == f, do: "btn-primary", else: "btn-ghost")}
              >
                {label}
              </button>
            <% end %>
          </div>
        <% end %>
        <div class="join">
          <%= for {d, label} <- [{"easy", "easy"}, {"normal", "normal"}, {"hard", "hard"}] do %>
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
        <%= if @wild_slug do %>
          <button
            type="button"
            phx-click="flee"
            data-confirm="도망친다 (배틀 종료, 모험 복귀)"
            class="btn btn-xs btn-ghost ml-auto"
          >
            🏃 도망
          </button>
        <% end %>
      </section>

      <!-- team status — 남은 마리 -->
      <section class="mb-3 flex justify-between text-xs">
        <div>
          상대: <.team_dots team={@engine.team_b} active={@engine.active_b} />
        </div>
        <div>
          내: <.team_dots team={@engine.team_a} active={@engine.active_a} />
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
          <div>
            <%= case @engine.winner do %>
              <% :a -> %>🎉 승리!
              <% :b -> %>💀 패배!
              <% _ -> %>무승부
            <% end %>
            <%= if @trainer do %>
              <p class="text-sm mt-1">
                <%= if @engine.winner == :a do %>
                  <em>"{@trainer.win_text}"</em>
                <% else %>
                  <em>"{@trainer.lose_text}"</em>
                <% end %>
              </p>
            <% end %>
          </div>
          <div class="flex gap-2">
            <button phx-click="restart" class="btn btn-sm btn-primary">다시 도전</button>
            <%= if @wild_slug || @trainer do %>
              <.link navigate={~p"/trizmon/adventure"} class="btn btn-sm">
                🗺️ 모험 복귀
              </.link>
            <% end %>
          </div>
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

  attr :team, :list, required: true
  attr :active, :integer, required: true

  defp team_dots(assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1">
      <%= for {mon, idx} <- Enum.with_index(@team) do %>
        <%= cond do %>
          <% idx == @active -> %>
            <span class="badge badge-primary badge-xs" title={mon.name}>●</span>
          <% mon.fainted? -> %>
            <span class="badge badge-ghost badge-xs opacity-30" title={mon.name <> " (KO)"}>×</span>
          <% true -> %>
            <span class="badge badge-success badge-xs" title={mon.name}>○</span>
        <% end %>
      <% end %>
    </span>
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
