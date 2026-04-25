defmodule HappyTrizn.Games.Minesweeper do
  @moduledoc """
  Minesweeper — 10x10 grid 싱글. 지뢰 찾고 모든 안전 셀 reveal 하면 승.

  state:
    - rows / cols / mine_count
    - cells: %{{r, c} => %{mine: bool, revealed: bool, flagged: bool, neighbors: int}}
    - mines_placed: bool (첫 클릭 후 placement)
    - over: :win | :lose | nil
    - started_at: DateTime (시간 기록)

  input:
    - %{"action" => "reveal", "r" => r, "c" => c}
    - %{"action" => "flag", "r" => r, "c" => c}
    - %{"action" => "restart"}
  """

  @behaviour HappyTrizn.Games.GameBehaviour

  @rows 10
  @cols 10
  @mine_count 12

  @impl true
  def meta do
    %{
      name: "Minesweeper",
      slug: "minesweeper",
      mode: :single,
      max_players: 1,
      min_players: 1,
      description: "지뢰 피하며 안전 셀 모두 열기"
    }
  end

  @impl true
  def init(_config), do: {:ok, new_game()}

  @impl true
  def handle_player_join(_player_id, _meta, state), do: {:ok, state, []}

  @impl true
  def handle_player_leave(_player_id, _reason, state), do: {:ok, state, []}

  @impl true
  def handle_input(_player_id, %{"action" => "reveal", "r" => r, "c" => c}, state) do
    cond do
      state.over -> {:ok, state, []}
      not in_bounds?(r, c) -> {:ok, state, []}
      true -> reveal_cell(state, r, c)
    end
  end

  def handle_input(_player_id, %{"action" => "flag", "r" => r, "c" => c}, state) do
    cond do
      state.over ->
        {:ok, state, []}

      not in_bounds?(r, c) ->
        {:ok, state, []}

      true ->
        cell = Map.fetch!(state.cells, {r, c})

        if cell.revealed do
          {:ok, state, []}
        else
          new_cell = %{cell | flagged: not cell.flagged}
          new_cells = Map.put(state.cells, {r, c}, new_cell)
          new_state = %{state | cells: new_cells}
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
  def game_over?(%{over: nil}), do: :no

  def game_over?(state) do
    elapsed_s =
      DateTime.utc_now()
      |> DateTime.diff(state.started_at, :second)

    {:yes, %{result: state.over, elapsed_seconds: elapsed_s}}
  end

  @impl true
  def terminate(_, _), do: :ok

  # ============================================================================
  # Game logic
  # ============================================================================

  @doc false
  def new_game do
    cells =
      for r <- 0..(@rows - 1), c <- 0..(@cols - 1), into: %{} do
        {{r, c}, %{mine: false, revealed: false, flagged: false, neighbors: 0}}
      end

    %{
      rows: @rows,
      cols: @cols,
      mine_count: @mine_count,
      cells: cells,
      mines_placed: false,
      over: nil,
      started_at: DateTime.utc_now()
    }
  end

  defp in_bounds?(r, c), do: r >= 0 and r < @rows and c >= 0 and c < @cols

  defp reveal_cell(state, r, c) do
    state =
      if state.mines_placed do
        state
      else
        place_mines(state, {r, c})
      end

    cell = Map.fetch!(state.cells, {r, c})

    cond do
      cell.revealed or cell.flagged ->
        {:ok, state, []}

      cell.mine ->
        # 모든 mine reveal + over=lose
        new_cells =
          Enum.reduce(state.cells, %{}, fn {pos, c}, acc ->
            new_c = if c.mine, do: %{c | revealed: true}, else: c
            Map.put(acc, pos, new_c)
          end)

        new_state = %{state | cells: new_cells, over: :lose}
        {:ok, new_state, [{:state_changed, new_state}]}

      true ->
        new_state = flood_reveal(state, [{r, c}])

        new_state =
          if all_safe_revealed?(new_state) do
            %{new_state | over: :win}
          else
            new_state
          end

        {:ok, new_state, [{:state_changed, new_state}]}
    end
  end

  # 첫 클릭 위치 + 인접 셀에는 mine 안 놓음 (첫 클릭 즉사 회피).
  defp place_mines(state, {fr, fc}) do
    safe_zone =
      for dr <- -1..1, dc <- -1..1, into: MapSet.new(), do: {fr + dr, fc + dc}

    candidates =
      for r <- 0..(@rows - 1), c <- 0..(@cols - 1), {r, c} not in safe_zone, do: {r, c}

    mine_positions = Enum.take_random(candidates, @mine_count)

    cells_with_mines =
      Enum.reduce(mine_positions, state.cells, fn pos, acc ->
        Map.update!(acc, pos, &%{&1 | mine: true})
      end)

    cells_with_neighbors =
      Map.new(cells_with_mines, fn {{r, c} = pos, cell} ->
        n = count_neighbor_mines(cells_with_mines, r, c)
        {pos, %{cell | neighbors: n}}
      end)

    %{state | cells: cells_with_neighbors, mines_placed: true}
  end

  defp count_neighbor_mines(cells, r, c) do
    for dr <- -1..1, dc <- -1..1, not (dr == 0 and dc == 0), reduce: 0 do
      acc ->
        case Map.get(cells, {r + dr, c + dc}) do
          %{mine: true} -> acc + 1
          _ -> acc
        end
    end
  end

  # BFS flood fill — neighbors=0 셀은 인접 셀까지 자동 reveal.
  defp flood_reveal(state, queue) do
    Enum.reduce(queue, state, fn {r, c}, acc ->
      cell = Map.fetch!(acc.cells, {r, c})

      cond do
        cell.revealed or cell.flagged or cell.mine ->
          acc

        true ->
          new_cells = Map.put(acc.cells, {r, c}, %{cell | revealed: true})
          new_state = %{acc | cells: new_cells}

          if cell.neighbors == 0 do
            neighbors =
              for dr <- -1..1,
                  dc <- -1..1,
                  not (dr == 0 and dc == 0),
                  in_bounds?(r + dr, c + dc),
                  do: {r + dr, c + dc}

            flood_reveal(new_state, neighbors)
          else
            new_state
          end
      end
    end)
  end

  defp all_safe_revealed?(state) do
    Enum.all?(state.cells, fn {_, c} -> c.mine or c.revealed end)
  end
end
