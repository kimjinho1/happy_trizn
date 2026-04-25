defmodule HappyTrizn.Games.Tetris.Piece do
  @moduledoc """
  Tetromino piece — 7 종류 (I, O, T, S, Z, L, J), 각 4 회전.

  좌표: piece-local 4x4 grid. {row, col} list (cell 차지하는 위치).
  Board 좌표는 piece의 origin {x, y} 에 더해서 결정.

  No SRS wall kick (basic rotation). Sprint 3c 에서 풀 SRS 추가 가능.
  """

  @type type :: :i | :o | :t | :s | :z | :l | :j
  @type rotation :: 0 | 1 | 2 | 3
  @type cell :: {integer(), integer()}

  @types ~w(i o t s z l j)a

  @doc "사용 가능한 모든 piece type."
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

  @doc """
  Piece 의 절대 board 좌표 list. origin = {row, col} (top-left of 4x4 grid).
  """
  @spec absolute_cells(type(), rotation(), {integer(), integer()}) :: [cell()]
  def absolute_cells(type, rotation, {row, col}) do
    cells(type, rotation) |> Enum.map(fn {dr, dc} -> {row + dr, col + dc} end)
  end

  @doc "Spawn 시 origin (board 상단 가운데)."
  def spawn_origin(:i), do: {0, 3}
  def spawn_origin(_), do: {0, 3}
end
