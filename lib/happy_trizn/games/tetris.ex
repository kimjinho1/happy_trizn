defmodule HappyTrizn.Games.Tetris do
  @moduledoc """
  Tetris (Jstris-like) — 멀티 1v1.

  - 10x22 board (상단 2행 hidden spawn buffer).
  - 7 piece (I, O, T, S, Z, L, J), 7-bag random.
  - Basic rotation (no SRS wall kicks — Sprint 3c 추가 가능).
  - Gravity tick (level 따라 빨라짐).
  - Line clear + Tetris 점수 (single 100, double 300, triple 500, tetris 800, level 곱).
  - Garbage 라우팅 (Jstris 표준: cleared-1 lines, tetris=4).
  - Top out → 상대 자동 승.

  state.players[player_id]:
    - board, current (type/rotation/origin), next, bag (7-bag remaining)
    - score, lines, level, gravity_counter, pending_garbage, top_out
  """

  @behaviour HappyTrizn.Games.GameBehaviour

  alias HappyTrizn.Games.Tetris.{Board, Piece}

  # tick 50ms (20fps). gravity_counter 누적해서 level 별 interval 도달 시 1칸 drop.
  @tick_ms 50
  @lines_per_level 10

  @impl true
  def meta do
    %{
      name: "Tetris",
      slug: "tetris",
      mode: :multi,
      max_players: 2,
      min_players: 2,
      description: "Jstris 클론 1v1",
      tick_interval_ms: @tick_ms
    }
  end

  @impl true
  def init(_config) do
    {:ok, %{status: :waiting, winner: nil, players: %{}}}
  end

  # ============================================================================
  # Player join / leave
  # ============================================================================

  @impl true
  def handle_player_join(player_id, _meta, %{players: players} = state) do
    cond do
      Map.has_key?(players, player_id) ->
        {:ok, state, []}

      map_size(players) >= 2 ->
        {:reject, :full}

      true ->
        new_player = new_player_state()
        new_players = Map.put(players, player_id, new_player)
        new_status = if map_size(new_players) == 2, do: :playing, else: :waiting

        {:ok, %{state | players: new_players, status: new_status},
         [{:player_joined, player_id}]}
    end
  end

  @impl true
  def handle_player_leave(player_id, _reason, state) do
    new_players = Map.delete(state.players, player_id)
    alive = new_players |> Enum.reject(fn {_, p} -> p.top_out end)

    cond do
      state.status == :playing and length(alive) == 1 ->
        winner = alive |> List.first() |> elem(0)
        {:ok, %{state | players: new_players, status: :over, winner: winner}, [{:winner, winner}]}

      map_size(new_players) == 0 ->
        {:ok, %{state | players: new_players, status: :over}, [{:player_left, player_id}]}

      true ->
        {:ok, %{state | players: new_players}, [{:player_left, player_id}]}
    end
  end

  # ============================================================================
  # Input
  # ============================================================================

  @impl true
  def handle_input(player_id, %{"action" => action}, state) do
    with %{} = player <- Map.get(state.players, player_id),
         false <- player.top_out,
         :playing <- state.status do
      do_action(player_id, action, player, state)
    else
      _ -> {:ok, state, []}
    end
  end

  def handle_input(_, _, state), do: {:ok, state, []}

  defp do_action(player_id, "left", player, state),
    do: move_horizontal(player_id, player, state, -1)

  defp do_action(player_id, "right", player, state),
    do: move_horizontal(player_id, player, state, 1)

  defp do_action(player_id, "rotate", player, state) do
    new_rotation = rem(player.current.rotation + 1, 4)
    new_current = %{player.current | rotation: new_rotation}

    if Board.valid_placement?(player.board, new_current.type, new_current.rotation, new_current.origin) do
      new_player = %{player | current: new_current}
      new_state = put_in(state.players[player_id], new_player)
      {:ok, new_state, [{:player_state, player_id, public_player(new_player)}]}
    else
      {:ok, state, []}
    end
  end

  defp do_action(player_id, "soft_drop", player, state) do
    case Board.try_drop(player.board, player.current.type, player.current.rotation, player.current.origin) do
      {:ok, new_origin} ->
        new_current = %{player.current | origin: new_origin}
        new_player = %{player | current: new_current, score: player.score + 1}
        new_state = put_in(state.players[player_id], new_player)
        {:ok, new_state, [{:player_state, player_id, public_player(new_player)}]}

      :landed ->
        lock_and_advance(player_id, player, state)
    end
  end

  defp do_action(player_id, "hard_drop", player, state) do
    landing =
      Board.hard_drop_position(
        player.board,
        player.current.type,
        player.current.rotation,
        player.current.origin
      )

    {row_orig, _} = player.current.origin
    {row_land, _} = landing
    drop_distance = row_land - row_orig

    new_current = %{player.current | origin: landing}
    new_player = %{player | current: new_current, score: player.score + 2 * drop_distance}
    new_state = put_in(state.players[player_id], new_player)

    lock_and_advance(player_id, new_player, new_state)
  end

  defp do_action(_, _, _, state), do: {:ok, state, []}

  defp move_horizontal(player_id, player, state, dx) do
    {row, col} = player.current.origin
    new_origin = {row, col + dx}

    if Board.valid_placement?(player.board, player.current.type, player.current.rotation, new_origin) do
      new_current = %{player.current | origin: new_origin}
      new_player = %{player | current: new_current}
      new_state = put_in(state.players[player_id], new_player)
      {:ok, new_state, [{:player_state, player_id, public_player(new_player)}]}
    else
      {:ok, state, []}
    end
  end

  # ============================================================================
  # Lock + clear + garbage + spawn next
  # ============================================================================

  defp lock_and_advance(player_id, player, state) do
    locked_board =
      Board.lock_piece(
        player.board,
        player.current.type,
        player.current.rotation,
        player.current.origin
      )

    {cleared_board, cleared} = Board.clear_lines(locked_board)
    score_gain = score_for_clear(cleared, player.level)
    garbage_send = garbage_for_clear(cleared)

    new_lines = player.lines + cleared
    new_level = div(new_lines, @lines_per_level) + 1

    {board_with_garbage, top_out_garbage} =
      if cleared == 0 and player.pending_garbage > 0 do
        case Board.add_garbage(cleared_board, player.pending_garbage) do
          {:ok, b} -> {b, false}
          {:error, :top_out} -> {cleared_board, true}
        end
      else
        {cleared_board, false}
      end

    pending_after = if cleared == 0, do: 0, else: player.pending_garbage

    spawn_origin = Piece.spawn_origin(player.next)

    if top_out_garbage or
         not Board.valid_placement?(board_with_garbage, player.next, 0, spawn_origin) do
      new_player =
        %{player | board: board_with_garbage, top_out: true, score: player.score + score_gain, lines: new_lines, level: new_level}

      new_players = Map.put(state.players, player_id, new_player)
      maybe_finish(state, new_players, [{:top_out, player_id}])
    else
      {next_piece, new_bag} = take_from_bag(player.bag)

      new_player = %{
        player
        | board: board_with_garbage,
          current: %{type: player.next, rotation: 0, origin: spawn_origin},
          next: next_piece,
          bag: new_bag,
          score: player.score + score_gain,
          lines: new_lines,
          level: new_level,
          pending_garbage: pending_after,
          gravity_counter: 0
      }

      new_players = Map.put(state.players, player_id, new_player)
      base_broadcasts = [{:player_state, player_id, public_player(new_player)}]

      if garbage_send > 0 do
        target = state.players |> Map.keys() |> Enum.find(&(&1 != player_id))

        if target do
          new_players =
            Map.update!(new_players, target, fn p ->
              %{p | pending_garbage: p.pending_garbage + garbage_send}
            end)

          {:ok, %{state | players: new_players},
           base_broadcasts ++
             [{:garbage_sent, %{from: player_id, to: target, lines: garbage_send}}]}
        else
          {:ok, %{state | players: new_players}, base_broadcasts}
        end
      else
        {:ok, %{state | players: new_players}, base_broadcasts}
      end
    end
  end

  defp maybe_finish(state, new_players, extra_broadcasts) do
    alive = new_players |> Enum.reject(fn {_, p} -> p.top_out end)

    cond do
      state.status == :playing and length(alive) == 1 ->
        winner = alive |> List.first() |> elem(0)

        {:ok, %{state | players: new_players, status: :over, winner: winner},
         extra_broadcasts ++ [{:winner, winner}]}

      length(alive) == 0 ->
        {:ok, %{state | players: new_players, status: :over}, extra_broadcasts}

      true ->
        {:ok, %{state | players: new_players}, extra_broadcasts}
    end
  end

  defp score_for_clear(0, _), do: 0
  defp score_for_clear(1, level), do: 100 * level
  defp score_for_clear(2, level), do: 300 * level
  defp score_for_clear(3, level), do: 500 * level
  defp score_for_clear(4, level), do: 800 * level

  defp garbage_for_clear(1), do: 0
  defp garbage_for_clear(2), do: 1
  defp garbage_for_clear(3), do: 2
  defp garbage_for_clear(4), do: 4
  defp garbage_for_clear(_), do: 0

  # ============================================================================
  # Tick (gravity)
  # ============================================================================

  @impl true
  def tick(%{status: :playing} = state) do
    {new_state, broadcasts} =
      Enum.reduce(state.players, {state, []}, fn {pid, player}, {acc_state, acc_b} ->
        if player.top_out do
          {acc_state, acc_b}
        else
          interval = gravity_interval(player.level)
          new_counter = player.gravity_counter + @tick_ms

          if new_counter >= interval do
            updated_player = %{player | gravity_counter: 0}
            updated_state = put_in(acc_state.players[pid], updated_player)

            case do_action(pid, "soft_drop", updated_player, updated_state) do
              {:ok, ns, b} -> {ns, acc_b ++ b}
            end
          else
            updated_player = %{player | gravity_counter: new_counter}
            {put_in(acc_state.players[pid], updated_player), acc_b}
          end
        end
      end)

    {:ok, new_state, broadcasts}
  end

  def tick(state), do: {:ok, state, []}

  defp gravity_interval(level) when level >= 20, do: @tick_ms

  defp gravity_interval(level) do
    base = 1000
    decay = 0.85

    (base * :math.pow(decay, level - 1))
    |> max(@tick_ms * 1.0)
    |> round()
  end

  # ============================================================================
  # Game over
  # ============================================================================

  @impl true
  def game_over?(%{status: :over, winner: w} = state) do
    public_players =
      Map.new(state.players, fn {id, p} ->
        {id, %{score: p.score, lines: p.lines, level: p.level, top_out: p.top_out}}
      end)

    {:yes, %{winner: w, players: public_players}}
  end

  def game_over?(_), do: :no

  @impl true
  def terminate(_, _), do: :ok

  # ============================================================================
  # Public player view (board / current piece + 작은 stats — bag 등 internal 제외)
  # ============================================================================

  @doc false
  def public_player(p) do
    %{
      board: p.board,
      current: p.current,
      next: p.next,
      score: p.score,
      lines: p.lines,
      level: p.level,
      pending_garbage: p.pending_garbage,
      top_out: p.top_out
    }
  end

  # ============================================================================
  # Player state init + 7-bag
  # ============================================================================

  defp new_player_state do
    bag = new_bag()
    {first_piece, bag1} = take_from_bag(bag)
    {next_piece, bag2} = take_from_bag(bag1)

    %{
      board: Board.new(),
      current: %{type: first_piece, rotation: 0, origin: Piece.spawn_origin(first_piece)},
      next: next_piece,
      bag: bag2,
      score: 0,
      lines: 0,
      level: 1,
      gravity_counter: 0,
      pending_garbage: 0,
      top_out: false
    }
  end

  defp new_bag, do: Enum.shuffle(Piece.types())

  defp take_from_bag([]), do: take_from_bag(new_bag())
  defp take_from_bag([first | rest]), do: {first, if(rest == [], do: new_bag(), else: rest)}
end
