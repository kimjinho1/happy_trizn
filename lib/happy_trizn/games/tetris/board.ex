defmodule HappyTrizn.Games.Tetris.Board do
  @moduledoc """
  10x22 board (10 col, 22 row, 상단 2행은 spawn buffer hidden).

  cell value:
    - `nil` = empty
    - atom (:i, :o, :t, :s, :z, :l, :j, :garbage) = 채워진 piece type

  좌표: {row, col}, row=0 이 최상단, col=0 이 왼쪽.
  """

  alias HappyTrizn.Games.Tetris.Piece

  @width 10
  @height 22
  @visible_height 20
  @hidden_rows 2

  def width, do: @width
  def height, do: @height
  def visible_height, do: @visible_height
  def hidden_rows, do: @hidden_rows

  @doc "빈 board (nil 채워진 list of list)."
  def new do
    List.duplicate(List.duplicate(nil, @width), @height)
  end

  @doc "Board 의 (row, col) 셀 값."
  def get(board, row, col) when row in 0..(@height - 1) and col in 0..(@width - 1) do
    board |> Enum.at(row) |> Enum.at(col)
  end

  def get(_, _, _), do: :out_of_bounds

  @doc "Board 의 (row, col) 셀 set."
  def put(board, row, col, value) do
    new_row = board |> Enum.at(row) |> List.replace_at(col, value)
    List.replace_at(board, row, new_row)
  end

  @doc """
  Piece 가 주어진 origin/rotation 으로 board 에 놓일 수 있는지 검증.
  - 모든 cell 이 board 안에 있어야
  - 비어있어야 (nil)
  """
  def valid_placement?(board, type, rotation, origin) do
    cells = Piece.absolute_cells(type, rotation, origin)

    Enum.all?(cells, fn {r, c} ->
      r >= 0 and r < @height and c >= 0 and c < @width and get(board, r, c) == nil
    end)
  end

  @doc "Piece 를 board 에 lock (cell 들에 type atom 채움)."
  def lock_piece(board, type, rotation, origin) do
    Piece.absolute_cells(type, rotation, origin)
    |> Enum.reduce(board, fn {r, c}, acc -> put(acc, r, c, type) end)
  end

  @doc """
  완성된 라인들 제거 + 빈 행 위에 추가.
  Returns {new_board, cleared_count}.
  """
  def clear_lines(board) do
    {kept, cleared_count} =
      Enum.reduce(board, {[], 0}, fn row, {acc, n} ->
        if Enum.all?(row, &(&1 != nil)) do
          {acc, n + 1}
        else
          {[row | acc], n}
        end
      end)

    new_rows = Enum.reverse(kept)
    padding = List.duplicate(List.duplicate(nil, @width), cleared_count)
    {padding ++ new_rows, cleared_count}
  end

  @doc """
  Garbage 라인 추가 (board 하단에 lines 만큼 새 row 추가, 상단 같은 수 만큼 잘림).
  각 garbage 라인은 1 col 만 hole (random).
  Returns {:ok, new_board} | {:error, :top_out}
  """
  def add_garbage(board, lines) when lines > 0 do
    visible = Enum.drop(board, @hidden_rows)
    top_out_check = Enum.take(visible, lines)

    if Enum.any?(top_out_check, fn row -> Enum.any?(row, &(&1 != nil)) end) do
      # 상단 lines 안에 이미 채워진 cell 있으면 top_out (밀려서 위로 넘어감)
      shifted = Enum.drop(board, lines)

      garbage_rows =
        for _ <- 1..lines do
          hole = :rand.uniform(@width) - 1
          for c <- 0..(@width - 1), do: if(c == hole, do: nil, else: :garbage)
        end

      new_board = shifted ++ garbage_rows
      # 상단 밀려난 cell 검사 — hidden 영역 위로 넘어가면 top_out
      if length(new_board) == @height and over_top?(new_board) do
        {:error, :top_out}
      else
        {:ok, new_board}
      end
    else
      shifted = Enum.drop(board, lines)

      garbage_rows =
        for _ <- 1..lines do
          hole = :rand.uniform(@width) - 1
          for c <- 0..(@width - 1), do: if(c == hole, do: nil, else: :garbage)
        end

      {:ok, shifted ++ garbage_rows}
    end
  end

  def add_garbage(board, _), do: {:ok, board}

  @doc "Spawn 영역 (상단 2행) 에 piece 못 놓으면 top_out."
  def over_top?(board) do
    board
    |> Enum.take(@hidden_rows)
    |> Enum.any?(fn row -> Enum.any?(row, &(&1 != nil)) end)
  end

  @doc "Soft drop — piece 한 칸 아래로 (불가능하면 nil)."
  def try_drop(board, type, rotation, {row, col}) do
    new_origin = {row + 1, col}

    if valid_placement?(board, type, rotation, new_origin) do
      {:ok, new_origin}
    else
      :landed
    end
  end

  @doc "Hard drop — piece 가 닿는 가장 아래까지."
  def hard_drop_position(board, type, rotation, origin) do
    case try_drop(board, type, rotation, origin) do
      {:ok, new_origin} -> hard_drop_position(board, type, rotation, new_origin)
      :landed -> origin
    end
  end
end
