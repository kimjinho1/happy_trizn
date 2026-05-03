defmodule HappyTrizn.Trizmon.ExpCurves do
  @moduledoc """
  4 경험치 곡선 (Sprint 5c-1).

  포켓몬 컨벤션 — 100lv 도달 총 exp:
    fast        :   800,000
    medium_fast : 1,000,000
    medium_slow : 1,059,860
    slow        : 1,250,000

  spec: docs/TRIZMON_SPEC.md §8
  """

  @curves [:fast, :medium_fast, :medium_slow, :slow]

  @doc "4 곡선 atom list."
  def all, do: @curves

  @doc """
  특정 곡선 + level → 그 level 에 도달하기 위한 누적 exp.

  level 1 = 0 exp.
  """
  def exp_for_level(_curve, 1), do: 0

  def exp_for_level(curve, level) when is_integer(level) and level >= 1 and level <= 100 do
    case curve do
      :fast -> floor(4 * :math.pow(level, 3) / 5)
      :medium_fast -> floor(:math.pow(level, 3))
      :medium_slow -> medium_slow(level)
      :slow -> floor(5 * :math.pow(level, 3) / 4)
    end
  end

  def exp_for_level(_, _), do: 0

  defp medium_slow(level) do
    # 6/5 n^3 - 15 n^2 + 100 n - 140. 최저 level 1~14 에서 음수 → 0 floor.
    val = 6 / 5 * :math.pow(level, 3) - 15 * :math.pow(level, 2) + 100 * level - 140
    max(floor(val), 0)
  end

  @doc """
  현재 누적 exp + 곡선 → 현재 level (1..100).
  """
  def level_from_exp(curve, exp) when is_integer(exp) and exp >= 0 do
    Enum.reduce_while(2..100, 1, fn lv, _acc ->
      if exp >= exp_for_level(curve, lv), do: {:cont, lv}, else: {:halt, lv - 1}
    end)
  end

  @doc "string slug → atom."
  def from_slug(slug) when is_binary(slug) do
    case Enum.find(@curves, fn c -> Atom.to_string(c) == slug end) do
      nil -> :medium_fast
      c -> c
    end
  end

  def from_slug(_), do: :medium_fast
end
