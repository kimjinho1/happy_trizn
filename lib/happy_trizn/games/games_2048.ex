defmodule HappyTrizn.Games.Games2048 do
  @moduledoc """
  2048 — 4x4 grid 싱글 게임. 같은 숫자 합쳐서 2048 만들기.

  state:
    - board: [[int | nil, ...], ...] 4x4
    - score: integer
    - won: boolean (2048 도달)
    - over: boolean (이동 불가)

  input:
    - %{"action" => "move", "dir" => "up" | "down" | "left" | "right"}
    - %{"action" => "restart"}
  """

  @behaviour HappyTrizn.Games.GameBehaviour

  @size 4
  @win_value 2048

  @impl true
  def meta do
    %{
      name: "2048",
      slug: "2048",
      mode: :single,
      max_players: 1,
      min_players: 1,
      description: "같은 숫자 합쳐서 2048 만들기"
    }
  end

  @impl true
  def init(_config) do
    {:ok, new_game()}
  end

  @impl true
  def handle_player_join(_player_id, _meta, state), do: {:ok, state, []}

  @impl true
  def handle_player_leave(_player_id, _reason, state), do: {:ok, state, []}

  @impl true
  def handle_input(_player_id, %{"action" => "move", "dir" => dir}, state)
      when dir in ["up", "down", "left", "right"] do
    if state.over or state.won do
      {:ok, state, []}
    else
      {new_board, gained} = move(state.board, dir_atom(dir))

      if new_board == state.board do
        # 변화 없음 → 이동 무효
        {:ok, state, []}
      else
        new_board = spawn_tile(new_board)
        new_score = state.score + gained
        won = state.won or has_value?(new_board, @win_value)
        over = not won and not any_move?(new_board)

        new_state = %{state | board: new_board, score: new_score, won: won, over: over}
        {:ok, new_state, [{:state_changed, new_state}]}
      end
    end
  end

  def handle_input(_player_id, %{"action" => "restart"}, _state) do
    new = new_game()
    {:ok, new, [{:state_changed, new}]}
  end

  def handle_input(_, _, state), do: {:ok, state, []}

  @impl true
  def tick(state), do: {:ok, state, []}

  @impl true
  def game_over?(%{over: true} = state), do: {:yes, %{score: state.score, won: state.won}}
  def game_over?(_), do: :no

  @impl true
  def terminate(_, _), do: :ok

  # ============================================================================
  # Game logic
  # ============================================================================

  @doc false
  def new_game do
    empty = empty_board()

    %{board: empty |> spawn_tile() |> spawn_tile(), score: 0, won: false, over: false}
  end

  defp empty_board, do: List.duplicate(List.duplicate(nil, @size), @size)

  defp dir_atom("up"), do: :up
  defp dir_atom("down"), do: :down
  defp dir_atom("left"), do: :left
  defp dir_atom("right"), do: :right

  @doc false
  def move(board, dir) do
    rows = transpose_for_dir(board, dir)
    {merged, gained} = Enum.reduce(rows, {[], 0}, fn row, {acc, g} ->
      {new_row, row_gain} = compress_and_merge(row)
      {[new_row | acc], g + row_gain}
    end)

    new_rows = Enum.reverse(merged)
    new_board = transpose_back(new_rows, dir)
    {new_board, gained}
  end

  # left 기준으로 압축. 다른 방향은 transpose 또는 reverse 후 left 처리 후 되돌림.
  defp transpose_for_dir(board, :left), do: board
  defp transpose_for_dir(board, :right), do: Enum.map(board, &Enum.reverse/1)

  defp transpose_for_dir(board, :up) do
    board |> transpose() |> transpose_for_dir(:left)
  end

  defp transpose_for_dir(board, :down) do
    board |> transpose() |> Enum.map(&Enum.reverse/1)
  end

  defp transpose_back(rows, :left), do: rows
  defp transpose_back(rows, :right), do: Enum.map(rows, &Enum.reverse/1)
  defp transpose_back(rows, :up), do: rows |> transpose()
  defp transpose_back(rows, :down), do: rows |> Enum.map(&Enum.reverse/1) |> transpose()

  defp transpose(matrix) do
    matrix
    |> List.zip()
    |> Enum.map(&Tuple.to_list/1)
  end

  # left compress: nil 제거 → 인접한 같은 값 merge → 뒤를 nil padding.
  defp compress_and_merge(row) do
    compressed = Enum.reject(row, &is_nil/1)
    {merged, gained} = merge_adjacent(compressed, [], 0)
    pad = @size - length(merged)
    {merged ++ List.duplicate(nil, pad), gained}
  end

  defp merge_adjacent([], acc, gained), do: {Enum.reverse(acc), gained}

  defp merge_adjacent([a, a | rest], acc, gained) do
    new = a * 2
    merge_adjacent(rest, [new | acc], gained + new)
  end

  defp merge_adjacent([a | rest], acc, gained) do
    merge_adjacent(rest, [a | acc], gained)
  end

  defp spawn_tile(board) do
    empties =
      for {row, r} <- Enum.with_index(board),
          {nil, c} <- Enum.with_index(row),
          do: {r, c}

    case empties do
      [] ->
        board

      _ ->
        {r, c} = Enum.random(empties)
        value = if :rand.uniform() < 0.9, do: 2, else: 4
        put_at(board, r, c, value)
    end
  end

  defp put_at(board, r, c, val) do
    row = Enum.at(board, r) |> List.replace_at(c, val)
    List.replace_at(board, r, row)
  end

  defp has_value?(board, target) do
    Enum.any?(board, fn row -> Enum.any?(row, &(&1 == target)) end)
  end

  defp any_move?(board) do
    [:up, :down, :left, :right]
    |> Enum.any?(fn dir ->
      {new_board, _} = move(board, dir)
      new_board != board
    end)
  end
end
