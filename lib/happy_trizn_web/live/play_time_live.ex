defmodule HappyTriznWeb.PlayTimeLive do
  @moduledoc """
  사용자 본인 플레이 시간 통계 (Sprint 5b).

  `/me/playtime` — login user 본인 데이터만 노출. 게스트는 redirect.
  - 게임별 합 + 총합
  - 일/주/월/년 기간 filter

  Admin 전체 통계는 `/admin/playtime` (HappyTriznWeb.AdminPlayTimeLive).
  """

  use HappyTriznWeb, :live_view

  alias HappyTrizn.Games.Registry, as: GameRegistry
  alias HappyTrizn.PlayTime

  @periods [
    {:day, "오늘"},
    {:week, "최근 7일"},
    {:month, "최근 30일"},
    {:year, "최근 365일"},
    {:all, "전체"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns[:current_user]

    cond do
      is_nil(user) ->
        {:ok, socket |> put_flash(:error, "게스트는 본인 통계 페이지 사용 불가. @trizn.kr 가입 필요.") |> redirect(to: ~p"/lobby")}

      true ->
        {:ok,
         socket
         |> assign(:period, :all)
         |> assign(:periods, @periods)
         |> assign(:page_title, "내 플레이 시간")
         |> load_data()}
    end
  end

  @impl true
  def handle_event("set_period", %{"period" => p}, socket) do
    period = parse_period(p)
    {:noreply, socket |> assign(:period, period) |> load_data()}
  end

  defp parse_period("day"), do: :day
  defp parse_period("week"), do: :week
  defp parse_period("month"), do: :month
  defp parse_period("year"), do: :year
  defp parse_period(_), do: :all

  defp load_data(socket) do
    user = socket.assigns.current_user
    period = socket.assigns.period

    by_game = PlayTime.by_game_for_user(user.id, period)
    total = PlayTime.total_seconds_for_user(user.id, period: period)
    by_day = PlayTime.by_period_for_user(user.id, nil, period)

    socket
    |> assign(:by_game, by_game)
    |> assign(:total, total)
    |> assign(:by_day, by_day)
  end

  defp game_name(slug) do
    case GameRegistry.get_meta(slug) do
      %{name: name} -> name
      _ -> slug
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto p-3 sm:p-6">
      <Layouts.flash_group flash={@flash} />
      <header class="mb-6">
        <h1 class="text-2xl font-bold">⏱️ 내 플레이 시간</h1>
        <p class="text-sm text-base-content/60">
          실제 게임이 진행 중일 때만 카운트 (대기 / countdown / 종료 후는 제외).
        </p>
      </header>

      <!-- 기간 filter -->
      <section class="mb-4">
        <div class="join">
          <%= for {p, label} <- @periods do %>
            <button
              type="button"
              phx-click="set_period"
              phx-value-period={p}
              class={"btn btn-sm join-item " <> if(@period == p, do: "btn-primary", else: "btn-ghost")}
            >
              {label}
            </button>
          <% end %>
        </div>
      </section>

      <!-- 총합 -->
      <section class="mb-6">
        <div class="stats shadow w-full">
          <div class="stat">
            <div class="stat-title">총 플레이 시간</div>
            <div class="stat-value text-primary">{PlayTime.format_duration(@total)}</div>
            <div class="stat-desc">기간: {period_label(@period, @periods)}</div>
          </div>
        </div>
      </section>

      <!-- 게임별 -->
      <section class="mb-6">
        <h2 class="text-lg font-semibold mb-3">게임별</h2>
        <%= if @by_game == [] do %>
          <p class="text-base-content/50 text-sm py-4 text-center">데이터 없음. 게임 한 판 해보세요!</p>
        <% else %>
          <div class="overflow-x-auto">
            <table class="table table-zebra w-full">
              <thead>
                <tr>
                  <th>게임</th>
                  <th class="text-right">시간</th>
                  <th class="text-right">비율</th>
                </tr>
              </thead>
              <tbody>
                <%= for {slug, seconds} <- @by_game do %>
                  <tr>
                    <td class="font-semibold">{game_name(slug)}</td>
                    <td class="text-right font-mono">{PlayTime.format_duration(seconds)}</td>
                    <td class="text-right text-base-content/60">{percent(seconds, @total)}</td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      </section>

      <!-- 일별 -->
      <section>
        <h2 class="text-lg font-semibold mb-3">일별</h2>
        <%= if @by_day == [] do %>
          <p class="text-base-content/50 text-sm py-4 text-center">데이터 없음.</p>
        <% else %>
          <div class="overflow-x-auto">
            <table class="table table-zebra w-full">
              <thead>
                <tr>
                  <th>날짜</th>
                  <th class="text-right">시간</th>
                </tr>
              </thead>
              <tbody>
                <%= for {date, seconds} <- @by_day do %>
                  <tr>
                    <td class="font-mono">{date}</td>
                    <td class="text-right font-mono">{PlayTime.format_duration(seconds)}</td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      </section>
    </div>
    """
  end

  defp percent(_seconds, 0), do: "0%"

  defp percent(seconds, total) when is_integer(total) and total > 0 do
    "#{Float.round(seconds / total * 100, 1)}%"
  end

  defp percent(_, _), do: "0%"

  defp period_label(p, periods) do
    case Enum.find(periods, fn {k, _} -> k == p end) do
      {_, label} -> label
      _ -> "전체"
    end
  end
end
