defmodule HappyTriznWeb.TrizmonPokedexLive do
  @moduledoc """
  Trizmon 도감 (Sprint 5c-3d).

  본 종 vs 잡은 종 list. 종 클릭 시 정보 (5c-late). 진화 트리 / 통계 = 5c-late.

  spec: docs/TRIZMON_SPEC.md §12
  """

  use HappyTriznWeb, :live_view

  alias HappyTrizn.Trizmon.Pokedex

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns[:current_user]

    cond do
      is_nil(user) ->
        {:ok,
         socket
         |> put_flash(:error, "도감은 로그인 사용자만.")
         |> redirect(to: ~p"/lobby")}

      true ->
        entries = Pokedex.list_for_user(user.id)
        stats = Pokedex.stats_for_user(user.id) || %{seen_count: 0, caught_count: 0}

        {:ok,
         socket
         |> assign(:entries, entries)
         |> assign(:stats, stats)
         |> assign(:page_title, "Trizmon — 도감")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto p-3 sm:p-6">
      <Layouts.flash_group flash={@flash} />
      <header class="mb-4 flex items-center justify-between flex-wrap gap-2">
        <div>
          <h1 class="text-2xl font-bold">📖 도감</h1>
          <p class="text-xs text-base-content/60">
            본 종: <strong>{@stats.seen_count}</strong> · 잡은 종: <strong>{@stats.caught_count}</strong>
          </p>
        </div>
        <.link navigate={~p"/trizmon"} class="btn btn-ghost btn-sm">← 메뉴</.link>
      </header>

      <%= if @entries == [] do %>
        <div class="alert alert-info">
          아직 만난 트리즈몬이 없어. 모험 모드 풀숲을 돌아다녀봐!
        </div>
      <% else %>
        <div class="grid grid-cols-2 sm:grid-cols-3 gap-3">
          <%= for e <- @entries do %>
            <div class={"card shadow-sm " <> card_class(e.status)}>
              <div class="card-body p-3">
                <div class="flex items-center justify-between mb-1">
                  <span class="font-bold">{e.name_ko}</span>
                  <span class={"badge badge-xs " <> status_class(e.status)}>
                    {status_label(e.status)}
                  </span>
                </div>
                <div class="text-xs opacity-70">
                  {type_label(e.type1)}
                  <%= if e.type2 do %>
                    / {type_label(e.type2)}
                  <% end %>
                </div>
                <div class="text-xs opacity-50 mt-1">
                  처음 만남: {format_dt(e.first_seen_at)}
                  <%= if e.first_caught_at do %>
                    <br />처음 잡음: {format_dt(e.first_caught_at)}
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp card_class("caught"), do: "bg-base-200"
  defp card_class(_), do: "bg-base-300 opacity-60"

  defp status_class("caught"), do: "badge-success"
  defp status_class(_), do: "badge-ghost"

  defp status_label("caught"), do: "잡음 ✓"
  defp status_label(_), do: "본 적"

  defp type_label(t) do
    case HappyTrizn.Trizmon.TypeChart.from_slug(t) do
      nil -> t
      a -> HappyTrizn.Trizmon.TypeChart.display_name(a)
    end
  end

  defp format_dt(nil), do: ""

  defp format_dt(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d")
  end
end
