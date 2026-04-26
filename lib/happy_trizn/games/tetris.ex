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
  @lock_delay_ms 500
  @max_lock_resets 15
  @countdown_ms 3000

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
    {:ok,
     %{
       status: :waiting,
       winner: nil,
       players: %{},
       countdown_ms: nil,
       # 방 단위 1등 기록 — 게임 끝날 때마다 누적 (최신이 head, 최대 10개).
       winners_history: []
     }}
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

        # 2번째 player join → 양쪽 모두 fresh state 로 reset + 3-2-1 countdown 시작.
        # 1번째는 :waiting (혼자 대기). solo 연습은 "start_practice" action 으로 진입.
        if map_size(new_players) == 2 do
          reset_players = Map.new(new_players, fn {pid, _} -> {pid, new_player_state()} end)

          new_state = %{
            state
            | players: reset_players,
              status: :countdown,
              countdown_ms: @countdown_ms,
              winner: nil
          }

          {:ok, new_state, [{:player_joined, player_id}, {:countdown_start, @countdown_ms}]}
        else
          {:ok, %{state | players: new_players, status: :waiting}, [{:player_joined, player_id}]}
        end
    end
  end

  @impl true
  def handle_player_leave(player_id, _reason, state) do
    new_players = Map.delete(state.players, player_id)
    alive = new_players |> Enum.reject(fn {_, p} -> p.top_out end)

    cond do
      state.status == :playing and length(alive) == 1 ->
        winner = alive |> List.first() |> elem(0)
        new_state = finish_round(state, new_players, winner)
        {:ok, new_state, [{:winner, winner}]}

      # countdown 중에 한 명 떠나면 cancel — 남은 player 는 대기 상태로 복귀.
      state.status == :countdown and length(alive) == 1 ->
        {remaining_id, _} = alive |> List.first()
        # 남은 player 상태 fresh 로 (어차피 countdown 시 reset 했었음).
        reset_player = new_player_state()
        reset_players = Map.put(%{}, remaining_id, reset_player)

        {:ok,
         %{
           state
           | players: reset_players,
             status: :waiting,
             countdown_ms: nil,
             winner: nil
         }, [{:player_left, player_id}, {:countdown_cancel, %{}}]}

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
  def handle_input(player_id, %{"action" => "start_practice"}, state) do
    cond do
      state.status == :waiting and map_size(state.players) == 1 and
          Map.has_key?(state.players, player_id) ->
        # 솔로 연습 모드 진입. 다른 사람 join 하면 자동으로 :countdown → :playing.
        {:ok, %{state | status: :practice}, [{:practice_started, player_id}]}

      true ->
        {:ok, state, []}
    end
  end

  # 재도전 — 게임 끝난 후 사용자가 다시 시작. winners_history 보존.
  # 1명: → :practice (즉시 솔로 시작), 2명: → :countdown 3-2-1 → :playing.
  def handle_input(player_id, %{"action" => "restart"}, state) do
    cond do
      state.status != :over ->
        {:ok, state, []}

      not Map.has_key?(state.players, player_id) ->
        {:ok, state, []}

      true ->
        reset_players = Map.new(state.players, fn {pid, _} -> {pid, new_player_state()} end)

        cond do
          map_size(reset_players) == 2 ->
            new_state = %{
              state
              | players: reset_players,
                status: :countdown,
                countdown_ms: @countdown_ms,
                winner: nil
            }

            {:ok, new_state, [{:restart, player_id}, {:countdown_start, @countdown_ms}]}

          map_size(reset_players) == 1 ->
            new_state = %{
              state
              | players: reset_players,
                status: :practice,
                countdown_ms: nil,
                winner: nil
            }

            {:ok, new_state, [{:restart, player_id}, {:practice_started, player_id}]}

          true ->
            {:ok, state, []}
        end
    end
  end

  def handle_input(player_id, %{"action" => action}, state) do
    with %{} = player <- Map.get(state.players, player_id),
         false <- player.top_out,
         status when status in [:playing, :practice] <- state.status do
      # 키 카운터 (KPP) — 인식된 action 만 카운트, hold 가 noop 이어도 카운트.
      if known_action?(action) do
        bumped = %{player | keys_pressed: player.keys_pressed + 1}
        bumped_state = put_in(state.players[player_id], bumped)
        do_action(player_id, action, bumped, bumped_state)
      else
        do_action(player_id, action, player, state)
      end
    else
      _ -> {:ok, state, []}
    end
  end

  def handle_input(_, _, state), do: {:ok, state, []}

  @known_actions ~w(left right rotate rotate_cw rotate_ccw rotate_180 soft_drop hard_drop hold)

  defp known_action?(a) when is_binary(a), do: a in @known_actions
  defp known_action?(_), do: false

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

        new_player =
          %{
            player
            | current: new_current,
              score: player.score + 1,
              last_was_rotate: false
          }
          |> post_action_lock_check()

        new_state = put_in(state.players[player_id], new_player)
        {:ok, new_state, [{:player_state, player_id, public_player(new_player)}]}

      :landed ->
        # 즉시 lock 안 함 — lock delay 시작/유지. 사용자 가만히 있어도 tick 에서 시간 경과 시 lock.
        new_player = post_action_lock_check(player)
        new_state = put_in(state.players[player_id], new_player)
        {:ok, new_state, [{:player_state, player_id, public_player(new_player)}]}
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

      new_player =
        %{player | current: new_current, last_was_rotate: false}
        |> post_action_lock_check()

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

        new_player =
          %{player | current: new_current, last_was_rotate: true}
          |> post_action_lock_check()

        new_state = put_in(state.players[player_id], new_player)

        {:ok, new_state,
         [{:rotated, player_id}, {:player_state, player_id, public_player(new_player)}]}
    end
  end

  # 액션 후 호출 — 현재 위치에서 try_drop = :landed 면 lock_delay 시작/리셋, 아니면 클리어.
  # max resets 도달 시 시간만 흐름 (reset 안 함).
  defp post_action_lock_check(player) do
    case Board.try_drop(
           player.board,
           player.current.type,
           player.current.rotation,
           player.current.origin
         ) do
      :landed ->
        cond do
          is_nil(player.lock_delay_ms) ->
            %{player | lock_delay_ms: @lock_delay_ms, lock_resets: 0}

          player.lock_resets < @max_lock_resets ->
            %{player | lock_delay_ms: @lock_delay_ms, lock_resets: player.lock_resets + 1}

          true ->
            player
        end

      {:ok, _} ->
        # 더 이상 landed 아님 — lock_delay 클리어.
        %{player | lock_delay_ms: nil}
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
              gravity_counter: 0,
              lock_delay_ms: nil,
              lock_resets: 0,
              hold_count: player.hold_count + 1
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
              gravity_counter: 0,
              lock_delay_ms: nil,
              lock_resets: 0,
              hold_count: player.hold_count + 1
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

    raw_send =
      garbage_for_clear(cleared, tspin_kind)
      |> apply_b2b_bonus(is_b2b_eligible and player.b2b and cleared > 0)
      |> apply_combo_bonus(new_combo)

    # Cancel — 라인 클리어 시 send 가 pending 부터 상쇄 (jstris 표준).
    # cancel = min(send, pending). 남은 send 만 상대에게 보냄. pending 도 그만큼 감소.
    {garbage_send, pending_after_cancel} =
      if cleared > 0 and player.pending_garbage > 0 do
        cancel = min(raw_send, player.pending_garbage)
        {raw_send - cancel, player.pending_garbage - cancel}
      else
        {raw_send, player.pending_garbage}
      end

    new_lines = player.lines + cleared
    new_level = div(new_lines, @lines_per_level) + 1

    # 라인 안 지운 lock 일 때만 board 에 pending 적용 — jstris 표준.
    # top_out 시에도 가비지 적용된 board 사용 — UI 에 "가비지로 졌다" 명확히 보임.
    {board_with_garbage, top_out_garbage, garbage_applied} =
      if cleared == 0 and pending_after_cancel > 0 do
        case Board.add_garbage(cleared_board, pending_after_cancel) do
          {:ok, b} -> {b, false, pending_after_cancel}
          {:top_out, b} -> {b, true, pending_after_cancel}
        end
      else
        {cleared_board, false, 0}
      end

    # 적용 후 pending 은 0 (no-clear 경로) / cancel 만 한 잔여 (clear 경로).
    pending_after = if cleared == 0, do: 0, else: pending_after_cancel
    # wasted = board 로 굳혀진 garbage (line clear 으로 cancel 못 한 양).
    wasted_inc = garbage_applied

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
          b2b: new_b2b,
          pieces_placed: player.pieces_placed + 1,
          garbage_sent: player.garbage_sent + garbage_send,
          garbage_received: player.garbage_received + garbage_applied,
          garbage_wasted: player.garbage_wasted + wasted_inc
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
          last_was_rotate: false,
          # Lock delay 리셋
          lock_delay_ms: nil,
          lock_resets: 0,
          # Stats
          pieces_placed: player.pieces_placed + 1,
          garbage_sent: player.garbage_sent + garbage_send,
          garbage_received: player.garbage_received + garbage_applied,
          garbage_wasted: player.garbage_wasted + wasted_inc
      }

      new_players = Map.put(state.players, player_id, new_player)

      base_broadcasts = [
        {:locked, player_id},
        {:player_state, player_id, public_player(new_player)}
      ]

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
        new_state = finish_round(state, new_players, winner)
        {:ok, new_state, extra_broadcasts ++ [{:winner, winner}]}

      length(alive) == 0 ->
        new_state = finish_round(state, new_players, nil)
        {:ok, new_state, extra_broadcasts}

      true ->
        {:ok, %{state | players: new_players}, extra_broadcasts}
    end
  end

  # 라운드 종료 공통 처리 — winner 기록 + 통계 캡처.
  # 솔로(:practice 에서 top out) 는 winner = nil 이지만 history 에는 기록 (점수 비교용).
  defp finish_round(state, new_players, winner) do
    history_entry = build_history_entry(new_players, winner, state)
    history = [history_entry | state.winners_history || []] |> Enum.take(10)

    %{
      state
      | players: new_players,
        status: :over,
        winner: winner,
        countdown_ms: nil,
        winners_history: history
    }
  end

  defp build_history_entry(players, winner, _state) do
    # solo 라면 유일한 player 가 결과 주체. multi 면 winner 가 주체 + loser stats 도 같이.
    {primary_id, primary_player} =
      cond do
        is_binary(winner) and Map.has_key?(players, winner) -> {winner, Map.get(players, winner)}
        true -> Enum.find(players, fn _ -> true end) || {nil, nil}
      end

    %{
      winner_id: winner,
      primary_id: primary_id,
      at: DateTime.utc_now() |> DateTime.truncate(:second),
      score: primary_player && primary_player.score,
      lines: primary_player && primary_player.lines,
      level: primary_player && primary_player.level,
      pieces_placed: primary_player && primary_player.pieces_placed
    }
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
  def tick(%{status: :countdown} = state) do
    # countdown_ms 가 비정상 (nil 등) 이면 0 으로 fallback — 즉시 :playing 진입.
    ms = if is_integer(state.countdown_ms), do: state.countdown_ms, else: 0
    new_ms = ms - @tick_ms

    cond do
      new_ms <= 0 ->
        now = System.monotonic_time(:millisecond)

        reset_players =
          Map.new(state.players, fn {pid, p} -> {pid, %{p | started_at: now}} end)

        new_state = %{state | status: :playing, countdown_ms: 0, players: reset_players}
        {:ok, new_state, [{:game_start, %{}}]}

      true ->
        # 매 50ms 마다 broadcast 하면 PubSub 폭주 (LiveView refresh_state 가 GenServer
        # call 매번 호출). 1초 boundary 마다만 broadcast → 사운드 / UI 충분.
        old_sec = div(ms, 1000)
        new_sec = div(new_ms, 1000)
        broadcasts = if old_sec != new_sec, do: [{:countdown_tick, new_ms}], else: []
        {:ok, %{state | countdown_ms: new_ms}, broadcasts}
    end
  end

  def tick(%{status: status} = state) when status in [:playing, :practice] do
    {new_state, broadcasts} =
      Enum.reduce(state.players, {state, []}, fn {pid, player}, {acc_state, acc_b} ->
        cond do
          player.top_out ->
            {acc_state, acc_b}

          # lock_delay active → 시간 경과 + 0 이하 면 force lock
          not is_nil(player.lock_delay_ms) ->
            new_remaining = player.lock_delay_ms - @tick_ms

            if new_remaining <= 0 do
              # 강제 lock — 단, 그 사이에 landed 해제됐을 수도 있어 다시 체크
              case Board.try_drop(
                     player.board,
                     player.current.type,
                     player.current.rotation,
                     player.current.origin
                   ) do
                :landed ->
                  case lock_and_advance(pid, player, acc_state) do
                    {:ok, ns, b} -> {ns, acc_b ++ b}
                  end

                {:ok, _} ->
                  # 더 이상 landed 아님 — lock_delay 클리어
                  cleared = %{player | lock_delay_ms: nil}
                  {put_in(acc_state.players[pid], cleared), acc_b}
              end
            else
              upd = %{player | lock_delay_ms: new_remaining}
              {put_in(acc_state.players[pid], upd), acc_b}
            end

          true ->
            interval = gravity_interval(player.level)
            new_counter = player.gravity_counter + @tick_ms

            if new_counter >= interval do
              # gravity 자동 drop — 사용자 키 입력 아님 (score / keys_pressed 영향 없음).
              case Board.try_drop(
                     player.board,
                     player.current.type,
                     player.current.rotation,
                     player.current.origin
                   ) do
                {:ok, new_origin} ->
                  new_current = %{player.current | origin: new_origin}

                  np =
                    %{
                      player
                      | current: new_current,
                        gravity_counter: 0,
                        last_was_rotate: false
                    }
                    |> post_action_lock_check()

                  {put_in(acc_state.players[pid], np),
                   acc_b ++ [{:player_state, pid, public_player(np)}]}

                :landed ->
                  np =
                    %{player | gravity_counter: 0}
                    |> post_action_lock_check()

                  {put_in(acc_state.players[pid], np),
                   acc_b ++ [{:player_state, pid, public_player(np)}]}
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
        {id, public_stats(p)}
      end)

    {:yes,
     %{
       winner: w,
       players: public_players,
       winners_history: state.winners_history || []
     }}
  end

  def game_over?(_), do: :no

  @doc """
  Player stats 결과 — game_over 시 + match_results 저장 시 사용.

  - duration_ms: 시작부터 현재 시점까지
  - pps: pieces per second
  - kpp: keys per piece
  - apm: garbage_sent per minute
  - vs: jstris VS score (=apm + pps × 100, 단순 근사)
  """
  def public_stats(p) do
    duration_ms = max(System.monotonic_time(:millisecond) - p.started_at, 1)
    duration_min = duration_ms / 60_000.0
    duration_sec = duration_ms / 1_000.0
    pieces = p.pieces_placed

    pps = if duration_sec > 0, do: Float.round(pieces / duration_sec, 2), else: 0.0
    kpp = if pieces > 0, do: Float.round(p.keys_pressed / pieces, 2), else: 0.0
    apm = if duration_min > 0, do: Float.round(p.garbage_sent / duration_min, 2), else: 0.0

    %{
      score: p.score,
      lines: p.lines,
      level: p.level,
      top_out: p.top_out,
      combo: p.combo,
      b2b: p.b2b,
      pieces_placed: pieces,
      keys_pressed: p.keys_pressed,
      garbage_sent: p.garbage_sent,
      garbage_received: p.garbage_received,
      garbage_wasted: p.garbage_wasted,
      hold_count: p.hold_count,
      finesse_violations: p.finesse_violations,
      duration_ms: duration_ms,
      pps: pps,
      kpp: kpp,
      apm: apm
    }
  end

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
      # 다음 5개 (현재 next + bag 의 앞부분) — UI 가 우측에 큐로 표시.
      nexts: upcoming(p, 5),
      hold: p.hold,
      hold_used: p.hold_used,
      score: p.score,
      lines: p.lines,
      level: p.level,
      pending_garbage: p.pending_garbage,
      combo: p.combo,
      b2b: p.b2b,
      top_out: p.top_out,
      lock_delay_ms: p.lock_delay_ms,
      pieces_placed: p.pieces_placed
    }
  end

  @doc "다음 N 조각 list — current 제외, 다음으로 나올 순서대로."
  def upcoming(%{next: next, bag: bag}, n) do
    [next | bag] |> Enum.take(n)
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
      top_out: false,
      # Lock delay (Jstris 표준 ~500ms, 회전/이동 reset 최대 15회).
      lock_delay_ms: nil,
      lock_resets: 0,
      # Stats — game_over 시 결과에 포함.
      pieces_placed: 0,
      keys_pressed: 0,
      garbage_sent: 0,
      garbage_received: 0,
      garbage_wasted: 0,
      hold_count: 0,
      finesse_violations: 0,
      started_at: System.monotonic_time(:millisecond)
    }
  end

  defp new_bag, do: Enum.shuffle(Piece.types())

  defp take_from_bag([]), do: take_from_bag(new_bag())
  defp take_from_bag([first | rest]), do: {first, if(rest == [], do: new_bag(), else: rest)}
end
