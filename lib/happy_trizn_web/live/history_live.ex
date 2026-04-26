defmodule HappyTriznWeb.HistoryLive do
  @moduledoc """
  매치 결과 + 개인 기록 + 리더보드 페이지.

  - `/history` — 본인 우승 결과 list (등록자만) + 본인 게임별 최고 기록.
  - `/history/leaderboard/:game_type` — 게임별 최고 기록 top N.
  """

  use HappyTriznWeb, :live_view

  alias HappyTrizn.{MatchResults, PersonalRecords}
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
        user = socket.assigns[:current_user]
        wins = MatchResults.for_user(user) |> Enum.take(50)
        records = PersonalRecords.list_for_user(user)

        {:noreply,
         socket
         |> assign(:wins, wins)
         |> assign(:records, records)
         |> assign(:page_title, "내 기록")}

      :leaderboard ->
        game_type = params["game_type"]

        if GameRegistry.valid_slug?(game_type) do
          rows = PersonalRecords.leaderboard(game_type, 20)
          meta = GameRegistry.get_meta(game_type)

          {:noreply,
           socket
           |> assign(:game_type, game_type)
           |> assign(:meta, meta)
           |> assign(:rows, rows)
           |> assign(:page_title, "#{meta.name} 리더보드")}
        else
          {:noreply, socket |> put_flash(:error, "없는 게임") |> redirect(to: ~p"/history")}
        end
    end
  end

  @impl true
  def render(%{live_action: :index} = assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto p-3 sm:p-6">
      <Layouts.flash_group flash={@flash} />
      <header class="mb-6 flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold">내 기록</h1>
          <p class="text-sm text-base-content/60">최근 우승 + 게임별 최고 기록.</p>
        </div>
        <.link navigate={~p"/lobby"} class="btn btn-ghost btn-sm">🏠 로비</.link>
      </header>

      <%= if is_nil(@current_user) do %>
        <div class="alert alert-warning mb-4">게스트는 기록 저장 안 됨. @trizn.kr 가입 필요.</div>
      <% end %>

      <section class="mb-6">
        <h2 class="text-lg font-semibold mb-2">게임별 최고 기록</h2>
        <%= if @records == [] do %>
          <p class="text-base-content/50 text-sm">아직 기록 없음.</p>
        <% else %>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <%= for r <- @records do %>
              <div class="card bg-base-200">
                <div class="card-body p-4">
                  <div class="flex items-center justify-between">
                    <h3 class="font-semibold">{r.game_type}</h3>
                    <.link
                      navigate={~p"/history/leaderboard/#{r.game_type}"}
                      class="link text-xs"
                    >
                      리더보드 →
                    </.link>
                  </div>
                  <div class="text-sm space-y-1 mt-2">
                    <div>최고 점수: <strong>{r.max_score}</strong></div>
                    <div>최다 라인: {r.max_lines}</div>
                    <div>총 우승: {r.total_wins}회</div>
                    <%= if r.metadata && r.metadata != %{} do %>
                      <div class="text-xs text-base-content/60">
                        <%= for {k, v} <- r.metadata |> Enum.sort_by(&elem(&1, 0)) do %>
                          <span class="mr-2">{k}: {format_metric(v)}</span>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </section>

      <section>
        <h2 class="text-lg font-semibold mb-2">최근 우승 ({length(@wins)}건)</h2>
        <%= if @wins == [] do %>
          <p class="text-base-content/50 text-sm">아직 우승 기록 없음.</p>
        <% else %>
          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>일시</th>
                  <th>게임</th>
                  <th>시간</th>
                  <th>점수</th>
                </tr>
              </thead>
              <tbody>
                <%= for w <- @wins do %>
                  <tr>
                    <td>{format_dt(w.finished_at)}</td>
                    <td>{w.game_type}</td>
                    <td>{format_duration(w.duration_ms)}</td>
                    <td>{stat_score(w.stats)}</td>
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

  def render(%{live_action: :leaderboard} = assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto p-3 sm:p-6">
      <Layouts.flash_group flash={@flash} />
      <header class="mb-6 flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold">{@meta.name} 리더보드</h1>
          <p class="text-sm text-base-content/60">최고 점수 top 20.</p>
        </div>
        <div class="flex gap-2">
          <.link navigate={~p"/history"} class="btn btn-ghost btn-sm">← 내 기록</.link>
          <.link navigate={~p"/lobby"} class="btn btn-ghost btn-sm">🏠 로비</.link>
        </div>
      </header>

      <%= if @rows == [] do %>
        <p class="text-base-content/50">아직 기록 없음.</p>
      <% else %>
        <div class="overflow-x-auto">
          <table class="table">
            <thead>
              <tr>
                <th>#</th>
                <th>닉네임</th>
                <th>최고 점수</th>
                <th>최다 라인</th>
                <th>우승</th>
              </tr>
            </thead>
            <tbody>
              <%= for {r, idx} <- Enum.with_index(@rows) do %>
                <tr>
                  <td>{idx + 1}</td>
                  <td class="font-mono">{r.user.nickname}</td>
                  <td>{r.max_score}</td>
                  <td>{r.max_lines}</td>
                  <td>{r.total_wins}회</td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end

  defp format_dt(nil), do: ""

  defp format_dt(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  end

  defp format_duration(ms) when is_integer(ms) and ms > 0 do
    seconds = div(ms, 1000)

    "#{div(seconds, 60)}:#{seconds |> rem(60) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  defp format_duration(_), do: "—"

  defp stat_score(%{} = stats) do
    cond do
      stats["players"] ->
        stats["players"]
        |> Map.values()
        |> Enum.map(&Map.get(&1, "score", 0))
        |> Enum.max(fn -> 0 end)

      true ->
        0
    end
  end

  defp stat_score(_), do: 0

  defp format_metric(v) when is_float(v), do: Float.round(v, 2) |> to_string()
  defp format_metric(v), do: to_string(v)
end
