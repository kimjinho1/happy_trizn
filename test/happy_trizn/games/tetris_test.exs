defmodule HappyTrizn.Games.TetrisTest do
  use ExUnit.Case, async: true

  alias HappyTrizn.Games.Tetris
  alias HappyTrizn.Games.Tetris.{Board, Piece}

  # 2명 join + countdown 즉시 끝내서 :playing 상태로.
  # 신규 spec: 2번째 join 시 :countdown (3000ms) → tick 으로 0 까지 가야 :playing.
  defp join2 do
    {:ok, state} = Tetris.init(%{})
    {:ok, s1, _} = Tetris.handle_player_join("p1", %{}, state)
    {:ok, s2, _} = Tetris.handle_player_join("p2", %{}, s1)
    # status :countdown — 강제로 :playing 으로 진입 (tick 60번 없이).
    %{s2 | status: :playing, countdown_ms: 0}
  end

  # countdown 진행 중인 상태 그대로 (UI 테스트용).
  defp join2_countdown do
    {:ok, state} = Tetris.init(%{})
    {:ok, s1, _} = Tetris.handle_player_join("p1", %{}, state)
    {:ok, s2, _} = Tetris.handle_player_join("p2", %{}, s1)
    s2
  end

  # 특정 piece 를 player 의 current 로 강제 셋업 — 결정론적 테스트용.
  defp force_piece(state, player_id, piece_type, rotation, origin, opts \\ []) do
    update_in(state.players[player_id], fn p ->
      p
      |> Map.put(:current, %{type: piece_type, rotation: rotation, origin: origin})
      |> Map.merge(Map.new(opts))
    end)
  end

  defp force_board(state, player_id, board) do
    put_in(state.players[player_id].board, board)
  end

  # countdown 이 :playing 으로 진입할 때 player.started_at 갱신 시도 — fresh player state 필요.
  defp new_player_for_test do
    %{
      board: Board.new(),
      current: %{type: :i, rotation: 0, origin: {0, 3}},
      next: :o,
      bag: [:t, :s, :z, :l, :j],
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
      lock_delay_ms: nil,
      lock_resets: 0,
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

  describe "meta/0" do
    test "multi 최대 8명 + tick_interval_ms 50 (Sprint 3l-2 N-player)" do
      m = Tetris.meta()
      assert m.slug == "tetris"
      assert m.mode == :multi
      assert m.max_players == 8
      assert m.min_players == 2
      assert m.tick_interval_ms == 50
    end
  end

  describe "handle_player_join/3" do
    test "1번째 → waiting, 2번째 → countdown (3-2-1 → playing)" do
      {:ok, state} = Tetris.init(%{})
      {:ok, s1, _} = Tetris.handle_player_join("p1", %{}, state)
      assert s1.status == :waiting
      assert map_size(s1.players) == 1

      {:ok, s2, broadcasts} = Tetris.handle_player_join("p2", %{}, s1)
      assert s2.status == :countdown
      assert s2.countdown_ms == 3000
      assert {:countdown_start, 3000} in broadcasts
      assert map_size(s2.players) == 2

      Enum.each(s2.players, fn {_id, p} ->
        assert p.score == 0
        assert p.lines == 0
        assert p.level == 1
        assert p.combo == -1
        refute p.b2b
        refute p.hold_used
        assert is_nil(p.hold)
        refute p.last_was_rotate
        refute p.top_out
        assert p.current.type in [:i, :o, :t, :s, :z, :l, :j]
        assert p.next in [:i, :o, :t, :s, :z, :l, :j]
        assert length(p.board) == 22
      end)
    end

    test "3번째도 in-progress 합류 (cap 8) — 카운트다운 안 다시 시작, 합류만" do
      state = join2()
      # join2 후 status :countdown. 3번째 join → status 유지, players 3.
      {:ok, s3, broadcasts} = Tetris.handle_player_join("p3", %{}, state)
      assert map_size(s3.players) == 3
      assert {:player_joined, "p3"} in broadcasts
      # countdown 재시작 안 함.
      refute Enum.any?(broadcasts, &match?({:countdown_start, _}, &1))
    end

    test "9번째 거부 :full (max_players 8)" do
      state =
        Enum.reduce(1..8, elem(Tetris.init(%{}), 1), fn i, acc ->
          {:ok, new, _} = Tetris.handle_player_join("p#{i}", %{}, acc)
          new
        end)

      assert map_size(state.players) == 8
      assert {:reject, :full} = Tetris.handle_player_join("p9", %{}, state)
    end

    test "재 join 은 noop" do
      state = join2()
      assert {:ok, ^state, []} = Tetris.handle_player_join("p1", %{}, state)
    end
  end

  describe "handle_input — left / right / rotate (legacy)" do
    setup do: {:ok, state: join2()}

    test "rotate (cw alias) 시 rotation 0..3", %{state: state} do
      r = state.players["p1"].current.rotation
      {:ok, ns, _} = Tetris.handle_input("p1", %{"action" => "rotate"}, state)
      new_r = ns.players["p1"].current.rotation
      assert new_r in [r, rem(r + 1, 4)]
    end

    test "alien action 무시", %{state: state} do
      assert {:ok, ^state, []} = Tetris.handle_input("p1", %{"action" => "magic"}, state)
    end

    test "없는 player 무시", %{state: state} do
      assert {:ok, ^state, []} = Tetris.handle_input("ghost", %{"action" => "left"}, state)
    end
  end

  describe "handle_input — SRS rotate_cw / rotate_ccw / rotate_180" do
    setup do: {:ok, state: join2()}

    test "rotate_cw → next rotation = (r+1) mod 4 if placement allows", %{state: state} do
      r = state.players["p1"].current.rotation
      {:ok, ns, _} = Tetris.handle_input("p1", %{"action" => "rotate_cw"}, state)
      new_r = ns.players["p1"].current.rotation
      assert new_r in [r, rem(r + 1, 4)]
      assert ns.players["p1"].last_was_rotate or new_r == r
    end

    test "rotate_ccw → (r+3) mod 4 if placement allows", %{state: state} do
      r = state.players["p1"].current.rotation
      {:ok, ns, _} = Tetris.handle_input("p1", %{"action" => "rotate_ccw"}, state)
      new_r = ns.players["p1"].current.rotation
      assert new_r in [r, rem(r + 3, 4)]
    end

    test "rotate_180 → (r+2) mod 4 if placement allows", %{state: state} do
      r = state.players["p1"].current.rotation

      # T piece 강제 (180 회전 가능 여부는 piece 마다 다름 — 빈 board 에서 T 는 가능)
      state = force_piece(state, "p1", :t, 0, {0, 4})
      {:ok, ns, _} = Tetris.handle_input("p1", %{"action" => "rotate_180"}, state)
      new_r = ns.players["p1"].current.rotation
      _ = r
      assert new_r in [0, 2]
    end

    test "회전 후 last_was_rotate = true (T-spin detection 용)", %{state: state} do
      state = force_piece(state, "p1", :t, 0, {0, 4})
      {:ok, ns, _} = Tetris.handle_input("p1", %{"action" => "rotate_cw"}, state)
      assert ns.players["p1"].last_was_rotate
    end

    test "이동 후 last_was_rotate = false", %{state: state} do
      state =
        force_piece(state, "p1", :t, 0, {0, 4}, last_was_rotate: true)

      {:ok, ns, _} = Tetris.handle_input("p1", %{"action" => "left"}, state)
      refute ns.players["p1"].last_was_rotate
    end

    test "벽에 붙은 J piece rotate_cw — wall kick 동작", %{state: state} do
      # J at col -... 실제로는 SRS kick table 작동 검증.
      # J 0 회전 cells = {0,0}{1,0}{1,1}{1,2} → col 0 에서 회전 시 충돌, kick 으로 이동.
      state = force_piece(state, "p1", :j, 0, {0, 0})
      {:ok, ns, _} = Tetris.handle_input("p1", %{"action" => "rotate_cw"}, state)
      # 회전 성공 시 rotation 1, 실패 시 0. 빈 board → 성공해야.
      assert ns.players["p1"].current.rotation == 1
    end
  end

  describe "handle_input — soft_drop" do
    test "정상 drop = origin row + 1, score +1" do
      state = join2()
      {row, _} = state.players["p1"].current.origin

      {:ok, ns, _} = Tetris.handle_input("p1", %{"action" => "soft_drop"}, state)
      {new_row, _} = ns.players["p1"].current.origin
      assert new_row == row + 1
      assert ns.players["p1"].score == 1
    end
  end

  describe "handle_input — hard_drop" do
    test "즉시 lock + 새 piece spawn (current.type 갱신)" do
      state = join2()
      orig_next = state.players["p1"].next

      {:ok, ns, _broadcasts} = Tetris.handle_input("p1", %{"action" => "hard_drop"}, state)

      {new_row, _} = ns.players["p1"].current.origin
      assert new_row == 0
      assert ns.players["p1"].current.type == orig_next
      assert ns.players["p1"].score > 0
      # hard drop 후 hold_used 초기화 (lock_and_advance 가 reset)
      refute ns.players["p1"].hold_used
    end
  end

  describe "handle_input — hold" do
    test "첫 hold → 현재 piece 가 hold 로, next 가 current 로" do
      state = join2()
      orig_current_type = state.players["p1"].current.type
      orig_next = state.players["p1"].next

      {:ok, ns, _} = Tetris.handle_input("p1", %{"action" => "hold"}, state)
      p = ns.players["p1"]

      assert p.hold == orig_current_type
      assert p.current.type == orig_next
      assert p.hold_used
    end

    test "이미 hold_used 면 noop (current/hold 변동 없음, keys_pressed 만 증가)" do
      state = join2()
      {:ok, s1, _} = Tetris.handle_input("p1", %{"action" => "hold"}, state)
      hold_before = s1.players["p1"].hold
      cur_before = s1.players["p1"].current
      keys_before = s1.players["p1"].keys_pressed

      assert {:ok, s2, []} = Tetris.handle_input("p1", %{"action" => "hold"}, s1)
      assert s2.players["p1"].hold == hold_before
      assert s2.players["p1"].current == cur_before
      # hold 시도 = key press 1회 카운트
      assert s2.players["p1"].keys_pressed == keys_before + 1
    end

    test "두 번째 hold (lock 후) → swap" do
      state = join2()
      first_type = state.players["p1"].current.type
      {:ok, s1, _} = Tetris.handle_input("p1", %{"action" => "hold"}, state)
      assert s1.players["p1"].hold == first_type

      # 강제로 hold_used 해제 (lock 시뮬)
      s2 = put_in(s1.players["p1"].hold_used, false)

      cur_before_swap = s2.players["p1"].current.type
      {:ok, s3, _} = Tetris.handle_input("p1", %{"action" => "hold"}, s2)

      # swap 후 hold = 직전 current, current = 직전 hold (first_type)
      assert s3.players["p1"].hold == cur_before_swap
      assert s3.players["p1"].current.type == first_type
      assert s3.players["p1"].hold_used
    end
  end

  describe "handle_input — score / combo / b2b 누적" do
    test "Tetris (4-line clear) → score +800*level + B2B flag set" do
      state = join2()

      # 빈 board + 한 라인 clear 직전 board 만들기:
      # row 18~21 모두 채워진 상태 (col 0~5 만), col 6~9 비어있게.
      # I piece 세로로 떨어뜨려 4-line clear.
      # 단순하게: row 18~21, col 0~9 에서 col 4 만 비어있게 채움 → I 세로 떨어뜨려 4 라인 clear.
      base_row = fn -> List.duplicate(:garbage, 10) |> List.replace_at(4, nil) end
      board = Board.new()

      board =
        Enum.reduce(18..21, board, fn r, acc ->
          List.replace_at(acc, r, base_row.())
        end)

      # I 세로 (rotation 1 = col 2 column). origin {18, 2} → cells {18,4},{19,4},{20,4},{21,4} (rotation 1 offset col 2).
      # I rotation 1 cells = {0,2},{1,2},{2,2},{3,2} → origin {18, 2} 시 col 4 row 18..21.
      state = state |> force_board("p1", board)
      state = force_piece(state, "p1", :i, 1, {18, 2})

      {:ok, ns, broadcasts} = Tetris.handle_input("p1", %{"action" => "hard_drop"}, state)
      p = ns.players["p1"]

      assert p.lines == 4
      # tetris score = 800 * level (1) = 800. 추가로 hard drop bonus 가 있을 수 있음.
      assert p.score >= 800
      assert p.b2b
      assert p.combo == 0

      # garbage broadcast → tetris = 4 라인 send
      garbage_evt =
        Enum.find(broadcasts, fn
          {:garbage_sent, _} -> true
          _ -> false
        end)

      assert garbage_evt
      {:garbage_sent, %{lines: g_lines}} = garbage_evt
      assert g_lines == 4
    end

    test "single 클리어 → b2b false, combo 0" do
      state = join2()

      # base_row: col 4, 5 만 비어있고 나머지는 garbage. O piece 가 col 4-5 떨어지면 1 line clear.
      base_row =
        fn ->
          List.duplicate(:garbage, 10) |> List.replace_at(4, nil) |> List.replace_at(5, nil)
        end

      board = List.replace_at(Board.new(), 21, base_row.())

      # O piece cells (any rotation) = {0,1}{0,2}{1,1}{1,2}. origin {20, 3} → row 20-21, col 4-5. row 20 은 비어있어야 OK.
      state = state |> force_board("p1", board)
      state = force_piece(state, "p1", :o, 0, {20, 3})

      {:ok, ns, _} = Tetris.handle_input("p1", %{"action" => "hard_drop"}, state)
      p = ns.players["p1"]

      assert p.lines == 1
      refute p.b2b
      assert p.combo == 0
    end

    test "no clear → combo reset to -1" do
      state = join2()
      # 빈 board 에 piece 떨어뜨리면 0 line clear → combo 리셋
      state = put_in(state.players["p1"].combo, 5)

      {:ok, ns, _} = Tetris.handle_input("p1", %{"action" => "hard_drop"}, state)
      assert ns.players["p1"].combo == -1
    end
  end

  describe "countdown tick throttle (broadcast 빈도)" do
    test "1초 boundary 마다만 broadcast (50ms 마다 안 함)" do
      state = %{
        status: :countdown,
        countdown_ms: 2999,
        players: %{},
        winner: nil,
        winners_history: []
      }

      # 2999 - 50 = 2949 — div 2 → 2 (같음) → broadcast 없음.
      {:ok, ns1, broadcasts1} = Tetris.tick(state)
      assert ns1.countdown_ms == 2949
      assert broadcasts1 == []

      # 2050 - 50 = 2000 — div 2 → 2 (같음) → broadcast 없음.
      s = %{state | countdown_ms: 2050}
      {:ok, _, b} = Tetris.tick(s)
      assert b == []

      # 2000 - 50 = 1950 — div 2 → 1 (다름) → boundary 통과, broadcast.
      s = %{state | countdown_ms: 2000}
      {:ok, _, b2} = Tetris.tick(s)
      assert b2 == [{:countdown_tick, 1950}]
    end

    test "countdown_ms nil 이어도 안 멈춤 — :playing 즉시 진입" do
      state = %{
        status: :countdown,
        countdown_ms: nil,
        players: %{"p1" => new_player_for_test()},
        winner: nil,
        winners_history: []
      }

      {:ok, ns, broadcasts} = Tetris.tick(state)
      assert ns.status == :playing
      assert {:game_start, %{}} in broadcasts
    end
  end

  describe "top_out via garbage — board 에 가비지 적용된 상태" do
    test "many pending → hard_drop → top_out_garbage + board 에 가비지" do
      state = join2()
      # p1 에게 25 lines pending 강제 — 적용 시 top_out.
      state = put_in(state.players["p1"].pending_garbage, 25)

      # no clear lock → garbage 적용 시도 → top_out (visible 다 garbage).
      # 빈 board 위에 hard_drop → 0 line clear → garbage 25 적용 → top_out.
      {:ok, ns, _} = Tetris.handle_input("p1", %{"action" => "hard_drop"}, state)
      p = ns.players["p1"]

      assert p.top_out

      # board 에 가비지 셀이 가득 — visible 행에 garbage atom 다수.
      garbage_cells =
        p.board
        |> Enum.drop(2)
        |> Enum.flat_map(& &1)
        |> Enum.count(&(&1 == :garbage))

      assert garbage_cells > 100
    end
  end

  describe "practice 모드 + countdown" do
    test "1명 join + start_practice → status :practice" do
      {:ok, state} = Tetris.init(%{})
      {:ok, s1, _} = Tetris.handle_player_join("p1", %{}, state)
      assert s1.status == :waiting

      {:ok, s2, broadcasts} = Tetris.handle_input("p1", %{"action" => "start_practice"}, s1)
      assert s2.status == :practice
      assert {:practice_started, "p1"} in broadcasts
    end

    test ":waiting 2명 아닐 때 start_practice 무시" do
      {:ok, state} = Tetris.init(%{})

      assert {:ok, ^state, []} =
               Tetris.handle_input("ghost", %{"action" => "start_practice"}, state)
    end

    test ":practice 중 input (예: hard_drop) 동작" do
      {:ok, state} = Tetris.init(%{})
      {:ok, s1, _} = Tetris.handle_player_join("p1", %{}, state)
      {:ok, s2, _} = Tetris.handle_input("p1", %{"action" => "start_practice"}, s1)

      orig_score = s2.players["p1"].score
      {:ok, s3, _} = Tetris.handle_input("p1", %{"action" => "hard_drop"}, s2)
      assert s3.players["p1"].score > orig_score
    end

    test ":practice 중 2명째 join → 양쪽 reset + :countdown" do
      {:ok, state} = Tetris.init(%{})
      {:ok, s1, _} = Tetris.handle_player_join("p1", %{}, state)
      {:ok, s2, _} = Tetris.handle_input("p1", %{"action" => "start_practice"}, s1)

      # p1 점수 쌓기
      {:ok, s2b, _} = Tetris.handle_input("p1", %{"action" => "hard_drop"}, s2)
      assert s2b.players["p1"].score > 0

      {:ok, s3, broadcasts} = Tetris.handle_player_join("p2", %{}, s2b)
      assert s3.status == :countdown
      # 양쪽 모두 fresh state (점수 0)
      assert s3.players["p1"].score == 0
      assert s3.players["p2"].score == 0
      assert {:countdown_start, 3000} in broadcasts
    end

    test "tick 으로 countdown_ms 감소 → 0 도달 시 :playing" do
      state = join2_countdown()
      assert state.status == :countdown
      assert state.countdown_ms == 3000

      # tick 한 번 → 50ms 감소
      {:ok, s1, _} = Tetris.tick(state)
      assert s1.countdown_ms == 2950

      # 강제로 ms 50 으로 만들고 한 번 더 → :playing
      s_almost = %{state | countdown_ms: 50}
      {:ok, s_done, broadcasts} = Tetris.tick(s_almost)
      assert s_done.status == :playing
      assert s_done.countdown_ms == 0
      assert {:game_start, %{}} in broadcasts
    end

    test "countdown 중 한 명 leave → 남은 사람 :practice 자동 전환" do
      state = join2_countdown()
      assert state.status == :countdown

      {:ok, s, broadcasts} = Tetris.handle_player_leave("p2", :disconnect, state)
      assert s.status == :practice
      assert s.countdown_ms == nil
      assert map_size(s.players) == 1
      assert Enum.any?(broadcasts, fn {tag, _} -> tag == :practice_started end)
    end

    test ":countdown 중 input 무시 (status not in [:playing, :practice])" do
      state = join2_countdown()
      assert {:ok, ^state, []} = Tetris.handle_input("p1", %{"action" => "left"}, state)
    end
  end

  describe "restart + winners_history" do
    test "1v1 게임 끝 → restart → :countdown 재진입 + winners_history 보존" do
      state = join2()
      # 강제로 :over (winner=p1) 상태 만들기
      state = put_in(state.players["p2"].top_out, true)
      state = %{state | status: :playing}
      # 강제로 finish_round 호출 (handle_player_leave 등 거치지 않고 직접)
      {:ok, finished_state, _} =
        Tetris.handle_player_leave("ghost_unknown", :disconnect, state)

      # finished_state 는 winner=p1 + status :over (handle_player_leave 처리 안 됨 → 직접)
      _ = finished_state

      forced =
        state
        |> Map.put(:status, :over)
        |> Map.put(:winner, "p1")
        |> Map.put(:winners_history, [%{winner_id: "p1", at: DateTime.utc_now(), score: 100}])

      {:ok, ns, broadcasts} = Tetris.handle_input("p1", %{"action" => "restart"}, forced)

      assert ns.status == :countdown
      assert ns.countdown_ms == 3000
      assert ns.winner == nil
      # 양쪽 player score 0 (fresh)
      Enum.each(ns.players, fn {_, p} -> assert p.score == 0 end)
      # history 보존 (restart 가 history clear 안 함)
      assert length(ns.winners_history) == 1
      assert {:countdown_start, 3000} in broadcasts
    end

    test "1명 (solo) 게임 끝 → restart → :practice 재진입" do
      {:ok, state} = Tetris.init(%{})
      {:ok, s1, _} = Tetris.handle_player_join("p1", %{}, state)

      # 솔로 :over 상태 강제
      forced = %{s1 | status: :over, winner: nil}

      {:ok, ns, broadcasts} = Tetris.handle_input("p1", %{"action" => "restart"}, forced)
      assert ns.status == :practice
      assert ns.players["p1"].score == 0
      assert {:practice_started, "p1"} in broadcasts
    end

    test "status != :over 일 때 restart 무시" do
      state = join2()
      assert {:ok, ^state, []} = Tetris.handle_input("p1", %{"action" => "restart"}, state)
    end

    test "참가자 아닌 사람 restart 시도 → 무시" do
      state = join2() |> Map.put(:status, :over) |> Map.put(:winner, "p1")
      assert {:ok, ^state, []} = Tetris.handle_input("ghost", %{"action" => "restart"}, state)
    end

    test "1v1 게임 중 한 명 leave → 남은 사람 :practice 자동 전환 (winner 결정 X, 게임 영향 X)" do
      state = join2()
      {:ok, ns, broadcasts} = Tetris.handle_player_leave("p2", :disconnect, state)
      # winner 안 정해짐 — 그냥 솔로 연습 모드.
      assert ns.status == :practice
      assert ns.winner == nil
      assert map_size(ns.players) == 1
      assert Map.has_key?(ns.players, "p1")
      assert Enum.any?(broadcasts, fn {tag, _} -> tag == :practice_started end)
    end
  end

  describe "leave 후 솔로 전환" do
  end

  describe "lock delay" do
    test "soft_drop landed → 즉시 lock 안 함, lock_delay_ms 시작" do
      state = join2()

      # 빈 board 에 piece 가 max 까지 떨어진 상태 시뮬: O at row=20 col=4 → soft drop landed.
      state = force_piece(state, "p1", :o, 0, {20, 4})

      {:ok, ns, _} = Tetris.handle_input("p1", %{"action" => "soft_drop"}, state)
      p = ns.players["p1"]

      # 새 piece spawn 안 됐어야 (lock 미발생)
      assert p.current.type == :o
      assert p.current.origin == {20, 4}
      assert p.lock_delay_ms == 500
      assert p.lock_resets == 0
    end

    test "lock delay 중 회전 시 timer reset, lock_resets +1" do
      state = join2()
      state = force_piece(state, "p1", :t, 0, {20, 4})

      {:ok, s1, _} = Tetris.handle_input("p1", %{"action" => "soft_drop"}, state)
      assert s1.players["p1"].lock_delay_ms == 500

      # 인공으로 시간 경과 시뮬 — lock_delay_ms 100 으로
      s1 = put_in(s1.players["p1"].lock_delay_ms, 100)

      {:ok, s2, _} = Tetris.handle_input("p1", %{"action" => "rotate_cw"}, s1)
      assert s2.players["p1"].lock_delay_ms == 500
      assert s2.players["p1"].lock_resets == 1
    end

    test "max_lock_resets 도달 시 timer reset 안 함" do
      state = join2()
      state = force_piece(state, "p1", :o, 0, {20, 4})

      {:ok, s1, _} = Tetris.handle_input("p1", %{"action" => "soft_drop"}, state)

      # lock_resets 를 max 로 강제 + delay 100
      s1 =
        s1
        |> put_in([Access.key!(:players), "p1", Access.key!(:lock_resets)], 15)
        |> put_in([Access.key!(:players), "p1", Access.key!(:lock_delay_ms)], 100)

      {:ok, s2, _} = Tetris.handle_input("p1", %{"action" => "left"}, s1)
      # delay 그대로 (reset 안 됨)
      assert s2.players["p1"].lock_delay_ms == 100
      assert s2.players["p1"].lock_resets == 15
    end

    test "tick 으로 lock_delay 시간 경과 후 0 되면 lock_and_advance" do
      state = join2()
      state = force_piece(state, "p1", :o, 0, {20, 4})

      {:ok, s1, _} = Tetris.handle_input("p1", %{"action" => "soft_drop"}, state)
      orig_next = s1.players["p1"].next

      # delay 50 으로 → 한 tick 으로 lock
      s1 = put_in(s1.players["p1"].lock_delay_ms, 50)

      {:ok, s2, _} = Tetris.tick(s1)
      p = s2.players["p1"]

      # 새 piece spawn (lock 후)
      assert p.current.type == orig_next
      assert p.lock_delay_ms == nil
      assert p.lock_resets == 0
      assert p.pieces_placed == 1
    end

    test "lock delay 중 더 이상 landed 아니게 되면 lock_delay_ms 클리어" do
      state = join2()
      state = force_piece(state, "p1", :o, 0, {20, 4}, lock_delay_ms: 200)

      # left 이동 시 같은 row 더 갈 수 있나? 그냥 horizontal — landed 여부 변함 없을 수 있음.
      # 더 확실: piece 를 위로 옮긴 상태에서 horizontal → not landed → clear.
      state = force_piece(state, "p1", :o, 0, {5, 4}, lock_delay_ms: 200)
      {:ok, ns, _} = Tetris.handle_input("p1", %{"action" => "left"}, state)
      assert ns.players["p1"].lock_delay_ms == nil
    end
  end

  describe "next 큐 (upcoming)" do
    test "public_player.nexts 5개 piece" do
      state = join2()
      pp = Tetris.public_player(state.players["p1"])
      assert is_list(pp.nexts)
      assert length(pp.nexts) == 5
      Enum.each(pp.nexts, fn t -> assert t in [:i, :o, :t, :s, :z, :l, :j] end)
    end

    test "upcoming/2 ordering — head = next, 그 다음 bag 순서" do
      state = join2()
      p = state.players["p1"]
      assert Tetris.upcoming(p, 5) == [p.next | p.bag] |> Enum.take(5)
    end
  end

  describe "stats / public_stats" do
    test "public_stats 에 pps/kpp/apm + 카운터들 포함" do
      state = join2()
      stats = Tetris.public_stats(state.players["p1"])

      keys = [
        :score,
        :lines,
        :level,
        :top_out,
        :combo,
        :b2b,
        :pieces_placed,
        :keys_pressed,
        :garbage_sent,
        :garbage_received,
        :garbage_wasted,
        :hold_count,
        :finesse_violations,
        :duration_ms,
        :pps,
        :kpp,
        :apm
      ]

      Enum.each(keys, fn k -> assert Map.has_key?(stats, k), "missing #{k}" end)
    end

    test "lock 후 pieces_placed +1, hold 후 hold_count +1" do
      state = join2()

      {:ok, s1, _} = Tetris.handle_input("p1", %{"action" => "hard_drop"}, state)
      assert s1.players["p1"].pieces_placed == 1

      {:ok, s2, _} = Tetris.handle_input("p1", %{"action" => "hold"}, s1)
      assert s2.players["p1"].hold_count == 1
    end

    test "input 마다 keys_pressed +1 (인식된 action 만)" do
      state = join2()
      {:ok, s1, _} = Tetris.handle_input("p1", %{"action" => "left"}, state)
      assert s1.players["p1"].keys_pressed == 1

      {:ok, s2, _} = Tetris.handle_input("p1", %{"action" => "magic"}, s1)
      # 인식 안 된 action 은 카운트 X
      assert s2.players["p1"].keys_pressed == 1
    end
  end

  describe "garbage cancel — line clear 시 pending 차감 + 상대 send 차감" do
    test "single clear (send 0, pending 5) → cancel 0, pending 그대로 5" do
      state = join2()
      state = put_in(state.players["p1"].pending_garbage, 5)

      # single line clear setup (board row 21 col 0..4, 6..9 garbage; col 5 만 비움)
      base_row = List.duplicate(:garbage, 10) |> List.replace_at(5, nil)
      board = List.replace_at(Board.new(), 21, base_row)
      state = state |> force_board("p1", board)
      state = force_piece(state, "p1", :i, 1, {18, 3})

      {:ok, ns, _} = Tetris.handle_input("p1", %{"action" => "hard_drop"}, state)
      p = ns.players["p1"]
      assert p.lines == 1
      # send 0 (single 보냄 0), cancel 0 → pending 5 유지
      assert p.pending_garbage == 5
    end

    test "tetris (send 4, pending 5) → cancel 4, pending = 1" do
      state = join2()
      state = put_in(state.players["p1"].pending_garbage, 5)

      # 4 lines clear setup (row 18..21, col 4 빈칸. I 세로 떨어뜨려 4-line clear)
      base_row = fn -> List.duplicate(:garbage, 10) |> List.replace_at(4, nil) end
      board = Board.new()
      board = Enum.reduce(18..21, board, fn r, acc -> List.replace_at(acc, r, base_row.()) end)
      state = state |> force_board("p1", board)
      state = force_piece(state, "p1", :i, 1, {18, 2})

      {:ok, ns, _} = Tetris.handle_input("p1", %{"action" => "hard_drop"}, state)
      p = ns.players["p1"]
      assert p.lines == 4
      # tetris send = 4, cancel min(4, 5) = 4, pending 5 - 4 = 1
      assert p.pending_garbage == 1
    end

    test "no clear → pending 모두 board 로 굳음 (잔여 0)" do
      state = join2()
      state = put_in(state.players["p1"].pending_garbage, 3)

      # 빈 board, hard_drop → no clear → garbage 3 적용 + pending 0
      {:ok, ns, _} = Tetris.handle_input("p1", %{"action" => "hard_drop"}, state)
      p = ns.players["p1"]
      assert p.pending_garbage == 0
      assert p.garbage_received == 3
      assert p.garbage_wasted == 3
    end

    test "no clear + pending 0 → board 그대로" do
      state = join2()
      assert state.players["p1"].pending_garbage == 0

      {:ok, ns, _} = Tetris.handle_input("p1", %{"action" => "hard_drop"}, state)
      p = ns.players["p1"]
      assert p.pending_garbage == 0
      assert p.garbage_received == 0
    end
  end

  describe "T-spin detection" do
    test "T piece 회전 후 lock + 3-corner filled → score for T-spin (no line)" do
      state = join2()
      level = state.players["p1"].level

      # T-spin slot 만들기: T piece 가 lock 될 위치 기준 4 corner 중 3개 채움.
      # T at rotation 1 origin {row, col} → cells = {0,1}{1,1}{1,2}{2,1}.
      # 4 corners = {row,col} {row,col+2} {row+2,col} {row+2,col+2}.
      #
      # 결정론적: row=18, col=0. piece cells {18,1}{19,1}{19,2}{20,1}.
      # corners {18,0} {18,2} {20,0} {20,2} 중 3개 채움 (e.g. {18,0} {20,0} {20,2}).
      # rot 1 corners = {18,0} {18,2} {20,0} {20,2}. front corners (rot 1) = {18,2} {20,2}.
      # full T-spin 위해 양 front corner + 최소 1개 back corner 채움.
      board = Board.new()
      board = Board.put(board, 18, 0, :garbage)
      board = Board.put(board, 18, 2, :garbage)
      board = Board.put(board, 20, 2, :garbage)
      # row 21 비워둠 → line clear 없음.

      state = state |> force_board("p1", board)

      state =
        force_piece(state, "p1", :t, 1, {18, 0}, last_was_rotate: true)

      {:ok, ns, _} = Tetris.handle_input("p1", %{"action" => "hard_drop"}, state)
      p = ns.players["p1"]

      # T-spin no clear 점수 = 400 * level. hard drop bonus 도 있음 → 최소 400.
      assert p.score >= 400 * level
    end
  end

  describe "handle_player_leave" do
    test "playing 중 1명 떠나면 남은 사람 :practice 자동 (winner X, 게임 영향 X)" do
      {:ok, ns, broadcasts} = Tetris.handle_player_leave("p1", :disconnect, join2())
      assert ns.status == :practice
      assert ns.winner == nil
      assert map_size(ns.players) == 1
      assert Enum.any?(broadcasts, fn {tag, _} -> tag == :practice_started end)
    end

    test "waiting 중 떠나면 winner 안 결정" do
      {:ok, state} = Tetris.init(%{})
      {:ok, s1, _} = Tetris.handle_player_join("p1", %{}, state)
      {:ok, ns, _} = Tetris.handle_player_leave("p1", :quit, s1)
      assert map_size(ns.players) == 0
    end
  end

  describe "tick (gravity)" do
    test "playing 시 gravity_counter 증가하거나 piece drop" do
      {:ok, ns, _} = Tetris.tick(join2())

      Enum.each(ns.players, fn {_, p} ->
        assert p.gravity_counter >= 0
      end)
    end

    test "waiting 시 noop" do
      {:ok, state} = Tetris.init(%{})
      assert {:ok, ^state, []} = Tetris.tick(state)
    end
  end

  describe "game_over?/1" do
    test ":playing → :no" do
      assert :no = Tetris.game_over?(join2())
    end

    test ":over → yes + public players (board / bag 제외, hold/combo/b2b 포함)" do
      state = join2() |> Map.merge(%{status: :over, winner: "p1"})
      assert {:yes, %{winner: "p1", players: ps}} = Tetris.game_over?(state)

      Enum.each(ps, fn {_, p} ->
        assert Map.has_key?(p, :score)
        assert Map.has_key?(p, :lines)
        assert Map.has_key?(p, :level)
        assert Map.has_key?(p, :top_out)
        assert Map.has_key?(p, :combo)
        assert Map.has_key?(p, :b2b)
        refute Map.has_key?(p, :board)
        refute Map.has_key?(p, :bag)
      end)
    end
  end

  describe "Board" do
    test "new/0: 22x10 nil grid" do
      b = Board.new()
      assert length(b) == 22
      assert Enum.all?(b, &(length(&1) == 10))
      assert Enum.all?(b, fn row -> Enum.all?(row, &is_nil/1) end)
    end

    test "valid_placement? — 안 / 밖" do
      b = Board.new()
      assert Board.valid_placement?(b, :o, 0, {0, 4})
      refute Board.valid_placement?(b, :o, 0, {0, 9})
      refute Board.valid_placement?(b, :o, 0, {21, 4})
    end

    test "lock_piece + clear_lines (full row 제거)" do
      b = Board.new()
      b = Board.lock_piece(b, :i, 0, {20, 0})

      filled_21 =
        Enum.at(b, 21)
        |> List.replace_at(4, :o)
        |> List.replace_at(5, :o)
        |> List.replace_at(6, :o)
        |> List.replace_at(7, :o)
        |> List.replace_at(8, :o)
        |> List.replace_at(9, :o)

      b_full = List.replace_at(b, 21, filled_21)

      {cleared, n} = Board.clear_lines(b_full)
      assert n == 1
      assert length(cleared) == 22
    end

    test "add_garbage 적용 (각 row 1 hole)" do
      assert {:ok, b} = Board.add_garbage(Board.new(), 2)
      assert length(b) == 22

      Enum.take(b, -2)
      |> Enum.each(fn row ->
        assert Enum.count(row, &is_nil/1) == 1
      end)
    end

    test "garbage 가 board height 초과해도 board 길이 22 유지 (overflow 방지)" do
      # 빈 board 에 25 lines garbage — visible 모두 채움 = top_out.
      assert {:top_out, b} = Board.add_garbage(Board.new(), 25)
      assert length(b) == 22

      # visible_height (20) 도 top_out 트리거.
      assert {:top_out, b2} = Board.add_garbage(Board.new(), 20)
      assert length(b2) == 22
    end

    test "garbage <= visible_height-1 이면 정상 적용, 길이 22 유지" do
      assert {:ok, b} = Board.add_garbage(Board.new(), 19)
      assert length(b) == 22
    end

    test "top_out 시 board 에 가비지 적용된 상태로 반환 (UI 시각적 피드백)" do
      assert {:top_out, b} = Board.add_garbage(Board.new(), 21)
      # 하단부 가비지 다수 적용
      visible_garbage =
        b
        |> Enum.drop(2)
        |> Enum.flat_map(& &1)
        |> Enum.count(&(&1 == :garbage))

      # 21 lines × 9 garbage cells (1 hole each) = 최소 180+ 가비지 셀
      assert visible_garbage > 100
    end

    test "hard_drop_position — 빈 board 에서 가장 아래까지" do
      b = Board.new()
      origin = {0, 4}
      landing = Board.hard_drop_position(b, :o, 0, origin)
      {row, _} = landing
      assert row == 20
    end
  end

  describe "Piece — SRS" do
    test "7 types" do
      assert Piece.types() == [:i, :o, :t, :s, :z, :l, :j]
    end

    test "각 type rotation 0..3 모두 4 cell" do
      for type <- Piece.types(), r <- 0..3 do
        assert length(Piece.cells(type, r)) == 4
      end
    end

    test "absolute_cells offset" do
      cells = Piece.absolute_cells(:o, 0, {5, 5})
      assert {6, 6} in cells
      assert {6, 7} in cells
      assert {5, 6} in cells
      assert {5, 7} in cells
    end

    test "next_rotation cw/ccw/180" do
      assert Piece.next_rotation(0, :cw) == 1
      assert Piece.next_rotation(3, :cw) == 0
      assert Piece.next_rotation(0, :ccw) == 3
      assert Piece.next_rotation(1, :ccw) == 0
      assert Piece.next_rotation(0, :rotate_180) == 2
      assert Piece.next_rotation(2, :rotate_180) == 0
    end

    test "wall_kicks O piece — 항상 [{0,0}]" do
      assert Piece.wall_kicks(:o, 0, 1, :cw) == [{0, 0}]
      assert Piece.wall_kicks(:o, 1, 2, :ccw) == [{0, 0}]
    end

    test "wall_kicks JLSTZ cw 0→1 5-test" do
      kicks = Piece.wall_kicks(:t, 0, 1, :cw)
      assert length(kicks) == 5
      assert hd(kicks) == {0, 0}
    end

    test "wall_kicks I cw 0→1 5-test (다른 table)" do
      kicks = Piece.wall_kicks(:i, 0, 1, :cw)
      assert length(kicks) == 5
      assert hd(kicks) == {0, 0}
      # I table 는 JLSTZ 와 다르다.
      refute kicks == Piece.wall_kicks(:t, 0, 1, :cw)
    end
  end

  describe "Finesse 통합 (Sprint 3i)" do
    setup do: {:ok, state: join2()}

    test "spawn 그대로 hard_drop → violations 0", %{state: state} do
      # 입력 없이 바로 hard_drop = optimal=0, actual=0 → :ok.
      {:ok, s, _} = Tetris.handle_input("p1", %{"action" => "hard_drop"}, state)
      assert s.players["p1"].finesse_violations == 0
      # spawn 직후 piece_inputs 리셋.
      assert s.players["p1"].piece_inputs == 0
    end

    test "left 1번 + hard_drop → optimal=1, actual=1 → violations 0", %{state: state} do
      {:ok, s, _} = Tetris.handle_input("p1", %{"action" => "left"}, state)
      assert s.players["p1"].piece_inputs == 1
      {:ok, s2, _} = Tetris.handle_input("p1", %{"action" => "hard_drop"}, s)
      assert s2.players["p1"].finesse_violations == 0
    end

    test "left + right (제자리) + hard_drop → actual=2 > optimal=0 → violation", %{state: state} do
      {:ok, s1, _} = Tetris.handle_input("p1", %{"action" => "left"}, state)
      {:ok, s2, _} = Tetris.handle_input("p1", %{"action" => "right"}, s1)
      {:ok, s3, _} = Tetris.handle_input("p1", %{"action" => "hard_drop"}, s2)
      assert s3.players["p1"].finesse_violations == 1
    end

    test "soft_drop / hard_drop / hold 는 finesse 입력 안 침", %{state: state} do
      {:ok, s, _} = Tetris.handle_input("p1", %{"action" => "soft_drop"}, state)
      assert s.players["p1"].piece_inputs == 0
      {:ok, s2, _} = Tetris.handle_input("p1", %{"action" => "hold"}, s)
      assert s2.players["p1"].piece_inputs == 0
    end

    test "hold → 새 piece 의 piece_inputs 0 으로 리셋", %{state: state} do
      {:ok, s, _} = Tetris.handle_input("p1", %{"action" => "left"}, state)
      assert s.players["p1"].piece_inputs == 1
      {:ok, s2, _} = Tetris.handle_input("p1", %{"action" => "hold"}, s)
      assert s2.players["p1"].piece_inputs == 0
    end
  end

  describe "Live HUD stats (Sprint 3l-4) — public_player 에 pps/apm/vs/kpp 포함" do
    test "신규 player public_player → pps/apm/vs/kpp 0.0 (조각 0)" do
      state = elem(Tetris.init(%{}), 1)
      {:ok, state, _} = Tetris.handle_player_join("p1", %{nickname: "alice"}, state)
      pub = Tetris.public_player(state.players["p1"])

      assert pub.pps == 0.0
      assert pub.apm == 0.0
      assert pub.vs == 0.0
      assert pub.kpp == 0.0
      assert pub.pieces_placed == 0
      assert pub.garbage_sent == 0
    end

    test "pieces / keys 쌓이면 pps / kpp / vs 증가" do
      state = elem(Tetris.init(%{}), 1)
      {:ok, state, _} = Tetris.handle_player_join("p1", %{nickname: "p1"}, state)

      # 조작 + 락 시뮬 — pieces_placed/keys_pressed 강제 셋업.
      # started_at 1초 전 으로 강제 → duration 약 1s.
      one_sec_ago = System.monotonic_time(:millisecond) - 1000

      state =
        state
        |> Map.put(:status, :playing)
        |> put_in([:players, "p1", :started_at], one_sec_ago)
        |> put_in([:players, "p1", :pieces_placed], 3)
        |> put_in([:players, "p1", :keys_pressed], 12)
        |> put_in([:players, "p1", :garbage_sent], 5)

      pub = Tetris.public_player(state.players["p1"])

      # pps ≈ 3 / 1s = 3.0 (약간의 오차 허용).
      assert pub.pps >= 2.5 and pub.pps <= 3.5
      # kpp = 12 / 3 = 4.0
      assert pub.kpp == 4.0
      # apm = 5 / (1/60) = 300.0
      assert pub.apm >= 250.0 and pub.apm <= 350.0
      # vs = apm + pps*100 ≈ 300 + 300 = 600
      assert pub.vs >= 550.0 and pub.vs <= 650.0
    end
  end

  describe "N-player ranking (Sprint 3l-3)" do
    test "winner 1등 + 나머지 top_out_at 늦은 순 (오래 살아남은 사람이 위)" do
      # 4명 셋업, 모두 top_out (winner = 마지막 살아남은 1명).
      state = elem(Tetris.init(%{}), 1)

      state =
        Enum.reduce(1..4, state, fn i, acc ->
          {:ok, new, _} = Tetris.handle_player_join("p#{i}", %{nickname: "p#{i}"}, acc)
          new
        end)
        |> Map.put(:status, :over)
        |> Map.put(:winner, "p3")

      # top_out_at 시간 강제 셋업: p1 가장 일찍, p2 그다음, p4 그다음. p3 은 winner (top_out=false).
      state =
        state
        |> put_in([:players, "p1", :top_out], true)
        |> put_in([:players, "p1", :top_out_at], 100)
        |> put_in([:players, "p2", :top_out], true)
        |> put_in([:players, "p2", :top_out_at], 200)
        |> put_in([:players, "p4", :top_out], true)
        |> put_in([:players, "p4", :top_out_at], 300)

      {:yes, result} = Tetris.game_over?(state)
      ranks = result.ranking

      assert length(ranks) == 4
      assert Enum.at(ranks, 0).player_id == "p3"
      assert Enum.at(ranks, 0).rank == 1
      assert Enum.at(ranks, 0).is_winner
      # p4 늦게 죽음 → 2위
      assert Enum.at(ranks, 1).player_id == "p4"
      assert Enum.at(ranks, 1).rank == 2
      # p2 → 3위
      assert Enum.at(ranks, 2).player_id == "p2"
      assert Enum.at(ranks, 2).rank == 3
      # p1 가장 먼저 죽음 → 4위
      assert Enum.at(ranks, 3).player_id == "p1"
      assert Enum.at(ranks, 3).rank == 4
    end

    test "winner nil (모두 top_out) — top_out_at 늦은 순으로 ranking" do
      state = elem(Tetris.init(%{}), 1)

      state =
        Enum.reduce(1..2, state, fn i, acc ->
          {:ok, new, _} = Tetris.handle_player_join("p#{i}", %{nickname: "p#{i}"}, acc)
          new
        end)
        |> Map.put(:status, :over)
        |> Map.put(:winner, nil)

      state =
        state
        |> put_in([:players, "p1", :top_out], true)
        |> put_in([:players, "p1", :top_out_at], 500)
        |> put_in([:players, "p2", :top_out], true)
        |> put_in([:players, "p2", :top_out_at], 100)

      {:yes, result} = Tetris.game_over?(state)
      ranks = result.ranking
      # p1 늦게 죽음 → 1위.
      assert Enum.at(ranks, 0).player_id == "p1"
      assert Enum.at(ranks, 1).player_id == "p2"
      refute Enum.at(ranks, 0).is_winner
    end

    test "ranking entry — nickname / score / lines / rank 포함" do
      state = elem(Tetris.init(%{}), 1)
      {:ok, state, _} = Tetris.handle_player_join("p1", %{nickname: "alice"}, state)
      {:ok, state, _} = Tetris.handle_player_join("p2", %{nickname: "bob"}, state)

      state =
        state
        |> Map.put(:status, :over)
        |> Map.put(:winner, "p1")
        |> put_in([:players, "p2", :top_out], true)
        |> put_in([:players, "p2", :top_out_at], 100)
        |> put_in([:players, "p1", :score], 9999)
        |> put_in([:players, "p1", :lines], 42)

      {:yes, result} = Tetris.game_over?(state)
      [first | _] = result.ranking

      assert first.nickname == "alice"
      assert first.score == 9999
      assert first.lines == 42
      assert first.rank == 1
      assert first.is_winner
    end
  end

  describe "N-player garbage targeting (Sprint 3l-2)" do
    # 4명 join 시 — 가비지 타겟이 살아있는 다른 player 중 random 1명.
    # 죽은 (top_out) player 는 제외.
    defp join_n(n) do
      Enum.reduce(1..n, elem(Tetris.init(%{}), 1), fn i, acc ->
        {:ok, new, _} = Tetris.handle_player_join("p#{i}", %{nickname: "p#{i}"}, acc)
        new
      end)
      |> Map.put(:status, :playing)
      |> Map.put(:countdown_ms, 0)
    end

    # I rotation 1 cells {0,2},{1,2},{2,2},{3,2} → origin {top, 2} 면 col 4.
    defp tetris_clear_setup(state, player_id) do
      board =
        Board.new()
        |> List.replace_at(20, for(c <- 0..9, do: if(c == 4, do: nil, else: :garbage)))
        |> List.replace_at(19, for(c <- 0..9, do: if(c == 4, do: nil, else: :garbage)))
        |> List.replace_at(18, for(c <- 0..9, do: if(c == 4, do: nil, else: :garbage)))
        |> List.replace_at(17, for(c <- 0..9, do: if(c == 4, do: nil, else: :garbage)))

      state = put_in(state.players[player_id].board, board)
      put_in(state.players[player_id].current, %{type: :i, rotation: 1, origin: {0, 2}})
    end

    test "4명 + p1 가비지 발생 → target ∈ p2/p3/p4 (자기 자신 X)" do
      state = join_n(4) |> tetris_clear_setup("p1")

      {:ok, _new_state, broadcasts} =
        Tetris.handle_input("p1", %{"action" => "hard_drop"}, state)

      {:garbage_sent, %{from: from, to: to, lines: lines}} =
        Enum.find(broadcasts, &match?({:garbage_sent, _}, &1))

      assert from == "p1"
      assert to in ["p2", "p3", "p4"]
      assert lines > 0
    end

    test "p2/p3 top_out → p1 가비지 target = p4 (살아있는 1명)" do
      state =
        join_n(4)
        |> put_in([:players, "p2", :top_out], true)
        |> put_in([:players, "p3", :top_out], true)
        |> tetris_clear_setup("p1")

      {:ok, _new, broadcasts} =
        Tetris.handle_input("p1", %{"action" => "hard_drop"}, state)

      {:garbage_sent, %{to: to}} = Enum.find(broadcasts, &match?({:garbage_sent, _}, &1))
      assert to == "p4"
    end

    test "다른 모두 top_out — 가비지 target nil (broadcast 안 발생)" do
      state =
        join_n(2)
        |> put_in([:players, "p2", :top_out], true)
        |> tetris_clear_setup("p1")

      {:ok, _new, broadcasts} =
        Tetris.handle_input("p1", %{"action" => "hard_drop"}, state)

      refute Enum.any?(broadcasts, &match?({:garbage_sent, _}, &1))
    end
  end
end
