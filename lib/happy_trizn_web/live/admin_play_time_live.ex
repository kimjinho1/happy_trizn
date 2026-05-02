defmodule HappyTriznWeb.AdminPlayTimeLive do
  @moduledoc """
  Admin 전체 플레이 시간 통계 (Sprint 5b).

  `/admin/playtime` — 사용자별 통합 + 게임별 전체. 일/주/월/년 filter.
  EnsureAdmin plug pipeline 으로 보호.
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
    {:ok,
     socket
     |> assign(:period, :all)
     |> assign(:periods, @periods)
     |> assign(:page_title, "Admin: 플레이 시간 통계")
     |> load_data()}
  end

  @impl true
  def handle_event("set_period", %{"period" => p}, socket) do
    {:noreply, socket |> assign(:period, parse_period(p)) |> load_data()}
  end

  defp parse_period("day"), do: :day
  defp parse_period("week"), do: :week
  defp parse_period("month"), do: :month
  defp parse_period("year"), do: :year
  defp parse_period(_), do: :all

  defp load_data(socket) do
    period = socket.assigns.period

    socket
    |> assign(:total, PlayTime.total_seconds_admin(period))
    |> assign(:by_game, PlayTime.by_game_admin(period))
    |> assign(:top_users, PlayTime.top_users(period, limit: 50))
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
    <div class="max-w-5xl mx-auto p-3 sm:p-6">
      <Layouts.flash_group flash={@flash} />
      <header class="mb-6">
        <h1 class="text-2xl font-bold">⏱️ Admin: 플레이 시간 통계</h1>
        <p class="text-sm text-base-content/60">
          실제 게임 진행 시간만 카운트. 게스트는 nickname "(게스트)" 표시.
        </p>
      </header>

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

      <section class="mb-6">
        <div class="stats shadow w-full">
          <div class="stat">
            <div class="stat-title">전체 누적</div>
            <div class="stat-value text-primary">{PlayTime.format_duration(@total)}</div>
            <div class="stat-desc">기간: {period_label(@period, @periods)}</div>
          </div>
        </div>
      </section>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <!-- 게임별 -->
        <section>
          <h2 class="text-lg font-semibold mb-3">게임별</h2>
          <%= if @by_game == [] do %>
            <p class="text-base-content/50 text-sm py-4 text-center">데이터 없음.</p>
          <% else %>
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
          <% end %>
        </section>

        <!-- 사용자 top -->
        <section>
          <h2 class="text-lg font-semibold mb-3">사용자별 (Top 50)</h2>
          <%= if @top_users == [] do %>
            <p class="text-base-content/50 text-sm py-4 text-center">데이터 없음.</p>
          <% else %>
            <table class="table table-zebra w-full">
              <thead>
                <tr>
                  <th>#</th>
                  <th>닉네임</th>
                  <th class="text-right">시간</th>
                </tr>
              </thead>
              <tbody>
                <%= for {row, idx} <- Enum.with_index(@top_users, 1) do %>
                  <tr>
                    <td class="text-base-content/60">{idx}</td>
                    <td>
                      <%= if row.user_id do %>
                        <span class="font-semibold">{row.nickname}</span>
                      <% else %>
                        <span class="text-base-content/50">(게스트)</span>
                      <% end %>
                    </td>
                    <td class="text-right font-mono">{PlayTime.format_duration(row.seconds)}</td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          <% end %>
        </section>
      </div>
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
