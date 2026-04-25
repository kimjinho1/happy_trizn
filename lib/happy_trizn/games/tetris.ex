defmodule HappyTrizn.Games.Tetris do
  @moduledoc """
  Tetris (Jstris-like) — 멀티 1v1, Jstris 수준 logic.

  ## 기능

  - 7 piece (I, O, T, S, Z, L, J), 7-bag random
  - **SRS rotation** + wall kick (5-test for JLSTZ, 5-test for I)
  - **CW / CCW / 180 회전** (별도 액션)
  - **Hold piece** — 라운드당 1회 swap, lock 후 재사용 가능
  - Move L/R, soft/hard drop
  - Line clear: Tetris 표준 점수 (single 100 / double 300 / triple 500 / tetris 800 × level)
  - **Combo**: 연속 line clear, combo bonus
  - **B2B (Back-to-Back)**: tetris/T-spin 연속 시 ×1.5 보너스
  - **T-spin detection**: T piece 회전 후 3-corner 검증
  - **Garbage** (Jstris 표준): cleared - 1, tetris=4, t-spin double=4, t-spin triple=6, b2b +1, combo +
  - **Top out** → 상대 자동 winner
  - Tick 50ms (20fps) gravity, level 별 interval

  ## state.players[player_id]

      board, current (type/rotation/origin), next, bag (7-bag),
      hold (type | nil), hold_used (bool),
      score, lines, level, gravity_counter, pending_garbage,
      combo (last clear streak, -1 = no streak),
      b2b (last clear was tetris/t-spin),
      last_was_rotate (T-spin detect),
      top_out
  """

  @behaviour HappyTrizn.Games.GameBehaviour

  alias HappyTrizn.Games.Tetris.{Board, Piece}

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

        {:ok, %{state | players: new_players, status: new_status}, [{:player_joined, player_id}]}
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

  defp do_action(player_id, "rotate", player, state),
    do: rotate(player_id, player, state, :cw)

  defp do_action(player_id, "rotate_cw", player, state),
    do: rotate(player_id, player, state, :cw)

  defp do_action(player_id, "rotate_ccw", player, state),
    do: rotate(player_id, player, state, :ccw)

  defp do_action(player_id, "rotate_180", player, state),
    do: rotate(player_id, player, state, :rotate_180)

  defp do_action(player_id, "soft_drop", player, state) do
    case Board.try_drop(
           player.board,
           player.current.type,
           player.current.rotation,
           player.current.origin
         ) do
      {:ok, new_origin} ->
        new_current = %{player.current | origin: new_origin}

        new_player = %{
          player
          | current: new_current,
            score: player.score + 1,
            last_was_rotate: false
        }

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

    # last_was_rotate 보존 — T-spin detection 은 lock 직전 마지막 의도적 액션이 회전이었는지 판정.
    # Hard drop 자체는 "이동" 으로 보지 않음 (Jstris 표준).
    new_player = %{player | current: new_current, score: player.score + 2 * drop_distance}
    new_state = put_in(state.players[player_id], new_player)

    lock_and_advance(player_id, new_player, new_state)
  end

  defp do_action(player_id, "hold", player, state) do
    if player.hold_used do
      {:ok, state, []}
    else
      do_hold(player_id, player, state)
    end
  end

  defp do_action(_, _, _, state), do: {:ok, state, []}

  defp move_horizontal(player_id, player, state, dx) do
    {row, col} = player.current.origin
    new_origin = {row, col + dx}

    if Board.valid_placement?(
         player.board,
         player.current.type,
         player.current.rotation,
         new_origin
       ) do
      new_current = %{player.current | origin: new_origin}
      new_player = %{player | current: new_current, last_was_rotate: false}
      new_state = put_in(state.players[player_id], new_player)
      {:ok, new_state, [{:player_state, player_id, public_player(new_player)}]}
    else
      {:ok, state, []}
    end
  end

  defp rotate(player_id, player, state, direction) do
    from_rotation = player.current.rotation
    to_rotation = Piece.next_rotation(from_rotation, direction)

    type = player.current.type
    {orig_row, orig_col} = player.current.origin

    kicks = Piece.wall_kicks(type, from_rotation, to_rotation, direction)

    case try_kicks(player.board, type, to_rotation, orig_row, orig_col, kicks) do
      nil ->
        {:ok, state, []}

      new_origin ->
        new_current = %{player.current | rotation: to_rotation, origin: new_origin}
        new_player = %{player | current: new_current, last_was_rotate: true}
        new_state = put_in(state.players[player_id], new_player)
        {:ok, new_state, [{:player_state, player_id, public_player(new_player)}]}
    end
  end

  defp try_kicks(_board, _type, _rot, _r, _c, []), do: nil

  defp try_kicks(board, type, rotation, row, col, [{dr, dc} | rest]) do
    candidate = {row + dr, col + dc}

    if Board.valid_placement?(board, type, rotation, candidate) do
      candidate
    else
      try_kicks(board, type, rotation, row, col, rest)
    end
  end

  defp do_hold(player_id, player, state) do
    case player.hold do
      nil ->
        # 첫 hold — 현재 piece 를 hold 에 넣고 next 에서 새 piece spawn
        {next_after, new_bag} = take_from_bag(player.bag)
        spawn_origin = Piece.spawn_origin(player.next)

        if not Board.valid_placement?(player.board, player.next, 0, spawn_origin) do
          # spawn 못 함 → top out
          new_player = %{player | hold: player.current.type, top_out: true, hold_used: true}
          new_players = Map.put(state.players, player_id, new_player)
          maybe_finish(state, new_players, [{:top_out, player_id}])
        else
          new_player = %{
            player
            | hold: player.current.type,
              current: %{type: player.next, rotation: 0, origin: spawn_origin},
              next: next_after,
              bag: new_bag,
              hold_used: true,
              last_was_rotate: false,
              gravity_counter: 0
          }

          new_state = put_in(state.players[player_id], new_player)
          {:ok, new_state, [{:player_state, player_id, public_player(new_player)}]}
        end

      held_type ->
        # hold 에 이미 있음 → 현재 piece 와 swap. spawn from top.
        spawn_origin = Piece.spawn_origin(held_type)

        if not Board.valid_placement?(player.board, held_type, 0, spawn_origin) do
          new_player = %{player | top_out: true, hold_used: true}
          new_players = Map.put(state.players, player_id, new_player)
          maybe_finish(state, new_players, [{:top_out, player_id}])
        else
          new_player = %{
            player
            | hold: player.current.type,
              current: %{type: held_type, rotation: 0, origin: spawn_origin},
              hold_used: true,
              last_was_rotate: false,
              gravity_counter: 0
          }

          new_state = put_in(state.players[player_id], new_player)
          {:ok, new_state, [{:player_state, player_id, public_player(new_player)}]}
        end
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

    # T-spin detection — 마지막 action 이 회전이고 T piece 일 때
    tspin_kind = detect_tspin(player, locked_board)

    {cleared_board, cleared} = Board.clear_lines(locked_board)
    is_tetris = cleared == 4
    is_b2b_eligible = is_tetris or tspin_kind != :none

    # Combo update
    new_combo =
      cond do
        cleared == 0 -> -1
        true -> player.combo + 1
      end

    # B2B update
    new_b2b =
      cond do
        cleared == 0 -> player.b2b
        is_b2b_eligible and player.b2b -> true
        is_b2b_eligible -> true
        true -> false
      end

    base_score = score_for_clear(cleared, tspin_kind, player.level)

    b2b_bonus =
      if cleared > 0 and is_b2b_eligible and player.b2b, do: round(base_score * 0.5), else: 0

    combo_bonus = if new_combo > 0, do: 50 * new_combo * player.level, else: 0

    score_gain = base_score + b2b_bonus + combo_bonus

    garbage_send =
      garbage_for_clear(cleared, tspin_kind)
      |> apply_b2b_bonus(is_b2b_eligible and player.b2b and cleared > 0)
      |> apply_combo_bonus(new_combo)

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
      new_player = %{
        player
        | board: board_with_garbage,
          top_out: true,
          score: player.score + score_gain,
          lines: new_lines,
          level: new_level,
          combo: new_combo,
          b2b: new_b2b
      }

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
          gravity_counter: 0,
          combo: new_combo,
          b2b: new_b2b,
          hold_used: false,
          last_was_rotate: false
      }

      new_players = Map.put(state.players, player_id, new_player)
      base_broadcasts = [{:player_state, player_id, public_player(new_player)}]

      base_broadcasts =
        if cleared > 0 do
          base_broadcasts ++
            [
              {:line_clear,
               %{
                 player: player_id,
                 lines: cleared,
                 tspin: tspin_kind,
                 combo: new_combo,
                 b2b: new_b2b
               }}
            ]
        else
          base_broadcasts
        end

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

  # ============================================================================
  # T-spin detection
  # ============================================================================

  # T piece + 마지막 action 이 rotate + 4 corner 중 3+ 가 채워져 있으면 T-spin.
  # Mini T-spin 은 simplification 위해 무시.
  defp detect_tspin(
         %{current: %{type: :t, rotation: rot, origin: {row, col}}, last_was_rotate: true},
         board_after_lock
       ) do
    # T piece 의 4 corner = piece origin 기준 {0,0} {0,2} {2,0} {2,2}
    corners = [{row, col}, {row, col + 2}, {row + 2, col}, {row + 2, col + 2}]

    filled =
      Enum.count(corners, fn {r, c} ->
        Board.get(board_after_lock, r, c) not in [nil, :out_of_bounds]
      end)

    if filled >= 3 do
      front_corners =
        case rot do
          0 -> [{row, col}, {row, col + 2}]
          1 -> [{row, col + 2}, {row + 2, col + 2}]
          2 -> [{row + 2, col}, {row + 2, col + 2}]
          3 -> [{row, col}, {row + 2, col}]
        end

      front_filled =
        Enum.count(front_corners, fn {r, c} ->
          Board.get(board_after_lock, r, c) not in [nil, :out_of_bounds]
        end)

      if front_filled == 2, do: :tspin, else: :tspin_mini
    else
      :none
    end
  end

  defp detect_tspin(_, _), do: :none

  # ============================================================================
  # Score / Garbage tables
  # ============================================================================

  defp score_for_clear(0, :tspin, level), do: 400 * level
  defp score_for_clear(0, :tspin_mini, level), do: 100 * level
  defp score_for_clear(0, _, _), do: 0
  defp score_for_clear(1, :tspin, level), do: 800 * level
  defp score_for_clear(2, :tspin, level), do: 1200 * level
  defp score_for_clear(3, :tspin, level), do: 1600 * level
  defp score_for_clear(1, :tspin_mini, level), do: 200 * level
  defp score_for_clear(1, _, level), do: 100 * level
  defp score_for_clear(2, _, level), do: 300 * level
  defp score_for_clear(3, _, level), do: 500 * level
  defp score_for_clear(4, _, level), do: 800 * level

  defp garbage_for_clear(1, :none), do: 0
  defp garbage_for_clear(2, :none), do: 1
  defp garbage_for_clear(3, :none), do: 2
  defp garbage_for_clear(4, _), do: 4
  defp garbage_for_clear(1, :tspin), do: 2
  defp garbage_for_clear(2, :tspin), do: 4
  defp garbage_for_clear(3, :tspin), do: 6
  defp garbage_for_clear(_, _), do: 0

  defp apply_b2b_bonus(garbage, true) when garbage > 0, do: garbage + 1
  defp apply_b2b_bonus(garbage, _), do: garbage

  defp apply_combo_bonus(garbage, combo) when combo >= 1 do
    bonus =
      cond do
        combo <= 1 -> 0
        combo <= 2 -> 1
        combo <= 4 -> 2
        combo <= 6 -> 3
        combo <= 9 -> 4
        true -> 5
      end

    garbage + bonus
  end

  defp apply_combo_bonus(garbage, _), do: garbage

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
        {id,
         %{
           score: p.score,
           lines: p.lines,
           level: p.level,
           top_out: p.top_out,
           combo: p.combo,
           b2b: p.b2b
         }}
      end)

    {:yes, %{winner: w, players: public_players}}
  end

  def game_over?(_), do: :no

  @impl true
  def terminate(_, _), do: :ok

  # ============================================================================
  # Public player view
  # ============================================================================

  @doc false
  def public_player(p) do
    %{
      board: p.board,
      current: p.current,
      next: p.next,
      hold: p.hold,
      hold_used: p.hold_used,
      score: p.score,
      lines: p.lines,
      level: p.level,
      pending_garbage: p.pending_garbage,
      combo: p.combo,
      b2b: p.b2b,
      top_out: p.top_out
    }
  end

  # ============================================================================
  # Player init + 7-bag
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
      hold: nil,
      hold_used: false,
      score: 0,
      lines: 0,
      level: 1,
      gravity_counter: 0,
      pending_garbage: 0,
      combo: -1,
      b2b: false,
      last_was_rotate: false,
      top_out: false
    }
  end

  defp new_bag, do: Enum.shuffle(Piece.types())

  defp take_from_bag([]), do: take_from_bag(new_bag())
  defp take_from_bag([first | rest]), do: {first, if(rest == [], do: new_bag(), else: rest)}
end
