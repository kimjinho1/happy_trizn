defmodule HappyTrizn.Trizmon.Battle.Turn do
  @moduledoc """
  턴 우선도 결정 (Sprint 5c-2a).

  spec: docs/TRIZMON_SPEC.md §7

  우선도 = move.priority (높은 쪽 먼저) → 동일 시 effective speed (높은 쪽 먼저) →
  동일 시 random.

  effective speed = stats.spe * status_modifier (마비 0.5).
  """

  alias HappyTrizn.Trizmon.Battle.{Mon, Status}

  @doc """
  두 행동 → 실행 순서 결정.

  action: {:move, move_idx, %{priority: int}} | {:switch, ...} | {:run}

  return: [:a, :b] 또는 [:b, :a] — 앞 element 가 먼저 행동.

  `:switch` / `:run` 는 우선도 6 (move 보다 높음). 동일하면 random.
  """
  def order(mon_a, mon_b, action_a, action_b) do
    pri_a = priority(action_a)
    pri_b = priority(action_b)

    cond do
      pri_a > pri_b -> [:a, :b]
      pri_a < pri_b -> [:b, :a]
      true -> by_speed(mon_a, mon_b)
    end
  end

  defp priority({:move, _idx, %{priority: p}}), do: p
  defp priority({:switch, _}), do: 6
  defp priority({:run}), do: 6
  defp priority(_), do: 0

  defp by_speed(mon_a, mon_b) do
    spe_a = effective_speed(mon_a)
    spe_b = effective_speed(mon_b)

    cond do
      spe_a > spe_b -> [:a, :b]
      spe_a < spe_b -> [:b, :a]
      :rand.uniform(2) == 1 -> [:a, :b]
      true -> [:b, :a]
    end
  end

  @doc "보정된 속도 — status 영향 + boost 단계 (boost 단계는 5c-late 본격 도입)."
  def effective_speed(%Mon{stats: %{spe: spe}} = mon) do
    spe * Status.speed_modifier(mon) * boost_multiplier(mon.boost_spe)
  end

  # boost 단계 -6..+6 — 단계당 stat 증감.
  # +1 = 1.5x, +2 = 2x, +3 = 2.5x, ...; -1 = 2/3, -2 = 0.5, ...
  defp boost_multiplier(0), do: 1.0
  defp boost_multiplier(stage) when stage > 0, do: (2.0 + stage) / 2.0
  defp boost_multiplier(stage) when stage < 0, do: 2.0 / (2.0 - stage)
end
