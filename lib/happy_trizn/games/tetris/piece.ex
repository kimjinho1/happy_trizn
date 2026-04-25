defmodule HappyTrizn.Games.Tetris.Piece do
  @moduledoc """
  Tetromino piece — 7 종류 (I, O, T, S, Z, L, J), 각 4 회전 + SRS wall kick.

  SRS (Super Rotation System):
  - rotate_cw / rotate_ccw / rotate_180
  - wall kick test offsets (5-test for J/L/T/S/Z, 5-test for I)
  - 첫 매칭 offset 으로 placement valid 면 그 위치, 아니면 원래 위치 (회전 무효).
  """

  @type type :: :i | :o | :t | :s | :z | :l | :j
  @type rotation :: 0 | 1 | 2 | 3
  @type cell :: {integer(), integer()}

  @types ~w(i o t s z l j)a

  def types, do: @types

  @doc "Piece type → 4 회전별 cell offsets ({row_delta, col_delta} list)."
  def shapes do
    %{
      i: {
        [{1, 0}, {1, 1}, {1, 2}, {1, 3}],
        [{0, 2}, {1, 2}, {2, 2}, {3, 2}],
        [{2, 0}, {2, 1}, {2, 2}, {2, 3}],
        [{0, 1}, {1, 1}, {2, 1}, {3, 1}]
      },
      o: {
        [{0, 1}, {0, 2}, {1, 1}, {1, 2}],
        [{0, 1}, {0, 2}, {1, 1}, {1, 2}],
        [{0, 1}, {0, 2}, {1, 1}, {1, 2}],
        [{0, 1}, {0, 2}, {1, 1}, {1, 2}]
      },
      t: {
        [{0, 1}, {1, 0}, {1, 1}, {1, 2}],
        [{0, 1}, {1, 1}, {1, 2}, {2, 1}],
        [{1, 0}, {1, 1}, {1, 2}, {2, 1}],
        [{0, 1}, {1, 0}, {1, 1}, {2, 1}]
      },
      s: {
        [{0, 1}, {0, 2}, {1, 0}, {1, 1}],
        [{0, 1}, {1, 1}, {1, 2}, {2, 2}],
        [{1, 1}, {1, 2}, {2, 0}, {2, 1}],
        [{0, 0}, {1, 0}, {1, 1}, {2, 1}]
      },
      z: {
        [{0, 0}, {0, 1}, {1, 1}, {1, 2}],
        [{0, 2}, {1, 1}, {1, 2}, {2, 1}],
        [{1, 0}, {1, 1}, {2, 1}, {2, 2}],
        [{0, 1}, {1, 0}, {1, 1}, {2, 0}]
      },
      l: {
        [{0, 2}, {1, 0}, {1, 1}, {1, 2}],
        [{0, 1}, {1, 1}, {2, 1}, {2, 2}],
        [{1, 0}, {1, 1}, {1, 2}, {2, 0}],
        [{0, 0}, {0, 1}, {1, 1}, {2, 1}]
      },
      j: {
        [{0, 0}, {1, 0}, {1, 1}, {1, 2}],
        [{0, 1}, {0, 2}, {1, 1}, {2, 1}],
        [{1, 0}, {1, 1}, {1, 2}, {2, 2}],
        [{0, 1}, {1, 1}, {2, 0}, {2, 1}]
      }
    }
  end

  @doc "주어진 piece type + rotation 의 cell list."
  @spec cells(type(), rotation()) :: [cell()]
  def cells(type, rotation) when type in @types and rotation in 0..3 do
    shapes()[type] |> elem(rotation)
  end

  @doc "Piece 의 절대 board 좌표 list. origin = {row, col}."
  @spec absolute_cells(type(), rotation(), {integer(), integer()}) :: [cell()]
  def absolute_cells(type, rotation, {row, col}) do
    cells(type, rotation) |> Enum.map(fn {dr, dc} -> {row + dr, col + dc} end)
  end

  @doc "Spawn 시 origin (board 상단)."
  def spawn_origin(_type), do: {0, 3}

  # ============================================================================
  # SRS Wall Kick offsets
  # ============================================================================
  # state transitions:
  # 0->1, 1->2, 2->3, 3->0  (cw)
  # 0->3, 1->0, 2->1, 3->2  (ccw)
  # 0->2, 1->3, 2->0, 3->1  (180)
  #
  # JLSTZ pieces use 5-test table A. I piece uses 5-test table B. O 는 회전 동일.
  # offsets are {row_delta, col_delta} 적용 순서로 시도.

  @jlstz_kicks_cw %{
    {0, 1} => [{0, 0}, {0, -1}, {-1, -1}, {2, 0}, {2, -1}],
    {1, 2} => [{0, 0}, {0, 1}, {1, 1}, {-2, 0}, {-2, 1}],
    {2, 3} => [{0, 0}, {0, 1}, {-1, 1}, {2, 0}, {2, 1}],
    {3, 0} => [{0, 0}, {0, -1}, {1, -1}, {-2, 0}, {-2, -1}]
  }

  @jlstz_kicks_ccw %{
    {0, 3} => [{0, 0}, {0, 1}, {-1, 1}, {2, 0}, {2, 1}],
    {1, 0} => [{0, 0}, {0, 1}, {1, 1}, {-2, 0}, {-2, 1}],
    {2, 1} => [{0, 0}, {0, -1}, {-1, -1}, {2, 0}, {2, -1}],
    {3, 2} => [{0, 0}, {0, -1}, {1, -1}, {-2, 0}, {-2, -1}]
  }

  @i_kicks_cw %{
    {0, 1} => [{0, 0}, {0, -2}, {0, 1}, {1, -2}, {-2, 1}],
    {1, 2} => [{0, 0}, {0, -1}, {0, 2}, {-2, -1}, {1, 2}],
    {2, 3} => [{0, 0}, {0, 2}, {0, -1}, {-1, 2}, {2, -1}],
    {3, 0} => [{0, 0}, {0, 1}, {0, -2}, {2, 1}, {-1, -2}]
  }

  @i_kicks_ccw %{
    {0, 3} => [{0, 0}, {0, -1}, {0, 2}, {-2, -1}, {1, 2}],
    {1, 0} => [{0, 0}, {0, 2}, {0, -1}, {-1, 2}, {2, -1}],
    {2, 1} => [{0, 0}, {0, 1}, {0, -2}, {2, 1}, {-1, -2}],
    {3, 2} => [{0, 0}, {0, -2}, {0, 1}, {1, -2}, {-2, 1}]
  }

  # 180 회전 wall kick (TETR.IO 표준 — "180 무브")
  @kicks_180 %{
    {0, 2} => [{0, 0}, {-1, 0}],
    {1, 3} => [{0, 0}, {0, 1}],
    {2, 0} => [{0, 0}, {1, 0}],
    {3, 1} => [{0, 0}, {0, -1}]
  }

  @doc """
  CW 회전 시 시도할 wall kick offsets.
  Returns offset list — 차례로 시도.
  """
  def wall_kicks(type, from_rotation, to_rotation, direction \\ :cw)

  def wall_kicks(:o, _, _, _), do: [{0, 0}]

  def wall_kicks(:i, from, to, :cw), do: Map.fetch!(@i_kicks_cw, {from, to})
  def wall_kicks(:i, from, to, :ccw), do: Map.fetch!(@i_kicks_ccw, {from, to})

  def wall_kicks(_type, from, to, :cw), do: Map.fetch!(@jlstz_kicks_cw, {from, to})
  def wall_kicks(_type, from, to, :ccw), do: Map.fetch!(@jlstz_kicks_ccw, {from, to})

  def wall_kicks(_, from, to, :rotate_180), do: Map.fetch!(@kicks_180, {from, to})

  @doc "현재 rotation 에서 방향 따라 다음 rotation."
  def next_rotation(r, :cw), do: rem(r + 1, 4)
  def next_rotation(r, :ccw), do: rem(r + 3, 4)
  def next_rotation(r, :rotate_180), do: rem(r + 2, 4)
end
