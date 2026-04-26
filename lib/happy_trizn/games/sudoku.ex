defmodule HappyTrizn.Games.Sudoku do
  @moduledoc """
  Sudoku — 9×9 싱글 puzzle.

  ## 생성 알고리즘
  1. base/2 = 모든 valid sudoku 의 기본 패턴 (3-stripe).
  2. 무작위 transform 적용 — validity 보존:
     - digit 1..9 random permutation
     - 각 band (3 rows) 안에서 row swap
     - 각 stack (3 cols) 안에서 col swap
     - band 끼리 swap
     - stack 끼리 swap
  3. clue 수만큼 random 위치 남기고 나머지 nil → puzzle.

  ## State
      %{
        puzzle: 9×9 (nil | 1..9, 사용자 입력 전 원본),
        solution: 9×9 (1..9 full),
        user: 9×9 (nil | 1..9, 사용자 누적),
        fixed: %{{r,c} => true},
        cursor: {r, c},
        difficulty: "easy" | "medium" | "hard",
        clues: int,
        over: nil | :win,
        started_at: DateTime
      }

  ## 난이도 → clue 수
  - easy: 40, medium: 32, hard: 26
  """

  @behaviour HappyTrizn.Games.GameBehaviour

  alias HappyTrizn.Games.GameBehaviour

  @difficulties %{"easy" => 40, "medium" => 32, "hard" => 26}
  @default_difficulty "easy"

  @impl GameBehaviour
  def meta do
    %{
      name: "스도쿠",
      slug: "sudoku",
      mode: :single,
      max_players: 1,
      min_players: 1,
      description: "9×9 클래식 puzzle"
    }
  end

  @impl GameBehaviour
  def init(opts) do
    diff = Map.get(opts || %{}, "difficulty", @default_difficulty)
    diff = if Map.has_key?(@difficulties, diff), do: diff, else: @default_difficulty
    {:ok, new_game(diff)}
  end

  @impl GameBehaviour
  def handle_player_join(_player_id, _meta, state), do: {:ok, state, []}

  @impl GameBehaviour
  def handle_player_leave(_player_id, _reason, state), do: {:ok, state, []}

  @impl GameBehaviour
  def handle_input(_player_id, %{"action" => "set_cursor", "r" => r, "c" => c}, state) do
    {r, c} = {to_int(r), to_int(c)}

    if r in 0..8 and c in 0..8 do
      {:ok, %{state | cursor: {r, c}}, []}
    else
      {:ok, state, []}
    end
  end

  def handle_input(_player_id, %{"action" => "move_cursor", "dir" => dir}, state) do
    {cr, cc} = state.cursor
    {dr, dc} = dir_to_delta(dir)
    new_r = max(0, min(8, cr + dr))
    new_c = max(0, min(8, cc + dc))
    {:ok, %{state | cursor: {new_r, new_c}}, []}
  end

  def handle_input(_player_id, %{"action" => "enter", "n" => n}, state) do
    n = to_int(n)
    {r, c} = state.cursor

    cond do
      state.over -> {:ok, state, []}
      Map.has_key?(state.fixed, {r, c}) -> {:ok, state, []}
      n < 0 or n > 9 -> {:ok, state, []}
      true -> set_cell(state, r, c, n)
    end
  end

  def handle_input(_player_id, %{"action" => "clear_cursor"}, state) do
    {r, c} = state.cursor

    if Map.has_key?(state.fixed, {r, c}) do
      {:ok, state, []}
    else
      set_cell(state, r, c, 0)
    end
  end

  def handle_input(_player_id, %{"action" => "restart"}, state) do
    diff = Map.get(state, :difficulty, @default_difficulty)
    {:ok, new_game(diff), []}
  end

  def handle_input(_, _, state), do: {:ok, state, []}

  @impl GameBehaviour
  def game_over?(%{over: :win} = state) do
    elapsed_s =
      DateTime.utc_now() |> DateTime.diff(state.started_at, :second)

    {:yes, %{result: :win, elapsed_seconds: elapsed_s, difficulty: state.difficulty}}
  end

  def game_over?(_), do: :no

  @impl GameBehaviour
  def terminate(_, _), do: :ok

  # ============================================================================
  # Cell set + win check
  # ============================================================================

  defp set_cell(state, r, c, n) do
    n_or_nil = if n == 0, do: nil, else: n
    new_user = put_grid(state.user, r, c, n_or_nil)
    new_state = %{state | user: new_user}
    new_state = if board_complete?(new_user, state.solution), do: %{new_state | over: :win}, else: new_state
    {:ok, new_state, []}
  end

  defp put_grid(grid, r, c, v) do
    row = Enum.at(grid, r)
    new_row = List.replace_at(row, c, v)
    List.replace_at(grid, r, new_row)
  end

  defp board_complete?(user, solution) do
    user == solution
  end

  defp dir_to_delta("up"), do: {-1, 0}
  defp dir_to_delta("down"), do: {1, 0}
  defp dir_to_delta("left"), do: {0, -1}
  defp dir_to_delta("right"), do: {0, 1}
  defp dir_to_delta(_), do: {0, 0}

  defp to_int(n) when is_integer(n), do: n
  defp to_int(s) when is_binary(s), do: String.to_integer(s)

  # ============================================================================
  # Generation
  # ============================================================================

  @doc false
  def new_game(difficulty) when is_binary(difficulty) do
    clue_count = Map.get(@difficulties, difficulty, Map.fetch!(@difficulties, @default_difficulty))
    solution = random_solution()
    {puzzle, fixed_set} = remove_cells(solution, clue_count)

    %{
      puzzle: puzzle,
      solution: solution,
      user: puzzle,
      fixed: fixed_set,
      cursor: {0, 0},
      difficulty: difficulty,
      clues: clue_count,
      over: nil,
      started_at: DateTime.utc_now()
    }
  end

  @doc """
  완전한 valid sudoku 9×9 board random 생성.

  base 패턴 (3-stripe) + symmetry-preserving 변환:
  - digit permutation
  - row swap (각 band 안)
  - col swap (각 stack 안)
  - band swap, stack swap
  """
  def random_solution do
    base_board()
    |> permute_digits()
    |> swap_rows_in_bands()
    |> swap_cols_in_stacks()
    |> swap_bands()
    |> swap_stacks()
  end

  # base(r, c) = ((r * 3 + div(r, 3) + c) mod 9) + 1
  defp base_board do
    for r <- 0..8 do
      for c <- 0..8 do
        rem(r * 3 + div(r, 3) + c, 9) + 1
      end
    end
  end

  defp permute_digits(board) do
    perm = Enum.shuffle(1..9)
    map = Enum.with_index(perm, 1) |> Map.new(fn {to, from} -> {from, to} end)
    Enum.map(board, fn row -> Enum.map(row, &Map.fetch!(map, &1)) end)
  end

  # band = 3 rows (0-2 / 3-5 / 6-8). 각 band 안에서 random row order.
  defp swap_rows_in_bands(board) do
    Enum.chunk_every(board, 3)
    |> Enum.flat_map(&Enum.shuffle/1)
  end

  # stack = 3 cols. transpose → swap_rows_in_bands → transpose.
  defp swap_cols_in_stacks(board) do
    board
    |> transpose()
    |> swap_rows_in_bands()
    |> transpose()
  end

  defp swap_bands(board) do
    bands = Enum.chunk_every(board, 3) |> Enum.shuffle()
    Enum.flat_map(bands, & &1)
  end

  defp swap_stacks(board) do
    board
    |> transpose()
    |> swap_bands()
    |> transpose()
  end

  defp transpose(rows) do
    rows |> Enum.zip() |> Enum.map(&Tuple.to_list/1)
  end

  # solution 에서 (81 - clue_count) 개 cell 을 nil 로. 나머지가 fixed (게임 시작 시 보임).
  defp remove_cells(solution, clue_count) do
    all_positions = for r <- 0..8, c <- 0..8, do: {r, c}
    keep = all_positions |> Enum.shuffle() |> Enum.take(clue_count) |> MapSet.new()

    fixed = Map.new(keep, fn pos -> {pos, true} end)

    puzzle =
      for r <- 0..8 do
        for c <- 0..8 do
          if MapSet.member?(keep, {r, c}) do
            Enum.at(Enum.at(solution, r), c)
          else
            nil
          end
        end
      end

    {puzzle, fixed}
  end

  # ============================================================================
  # Validation helpers (test 용 + 외부 노출)
  # ============================================================================

  @doc "주어진 9×9 board 가 valid 한 sudoku solution 인지 검증."
  def valid_solution?(board) do
    valid_rows?(board) and valid_cols?(board) and valid_boxes?(board)
  end

  defp valid_rows?(board) do
    Enum.all?(board, &(Enum.sort(&1) == Enum.to_list(1..9)))
  end

  defp valid_cols?(board) do
    valid_rows?(transpose(board))
  end

  defp valid_boxes?(board) do
    for br <- 0..2, bc <- 0..2 do
      cells =
        for r <- (br * 3)..(br * 3 + 2), c <- (bc * 3)..(bc * 3 + 2) do
          Enum.at(Enum.at(board, r), c)
        end

      Enum.sort(cells) == Enum.to_list(1..9)
    end
    |> Enum.all?()
  end
end
