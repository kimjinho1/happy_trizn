defmodule HappyTrizn.Games.TetrisTest do
  use ExUnit.Case, async: true

  alias HappyTrizn.Games.Tetris
  alias HappyTrizn.Games.Tetris.{Board, Piece}

  defp join2 do
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

  describe "meta/0" do
    test "multi 1v1 + tick_interval_ms 50" do
      m = Tetris.meta()
      assert m.slug == "tetris"
      assert m.mode == :multi
      assert m.max_players == 2
      assert m.min_players == 2
      assert m.tick_interval_ms == 50
    end
  end

  describe "handle_player_join/3" do
    test "1번째 → waiting, 2번째 → playing" do
      {:ok, state} = Tetris.init(%{})
      {:ok, s1, _} = Tetris.handle_player_join("p1", %{}, state)
      assert s1.status == :waiting
      assert map_size(s1.players) == 1

      {:ok, s2, _} = Tetris.handle_player_join("p2", %{}, s1)
      assert s2.status == :playing
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

    test "3번째 거부 :full" do
      assert {:reject, :full} = Tetris.handle_player_join("p3", %{}, join2())
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

    test "이미 hold_used 면 noop" do
      state = join2()
      {:ok, s1, _} = Tetris.handle_input("p1", %{"action" => "hold"}, state)
      # 한 번 더 → noop
      assert {:ok, ^s1, []} = Tetris.handle_input("p1", %{"action" => "hold"}, s1)
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
    test "playing 중 1명 떠나면 남은 사람 winner" do
      {:ok, ns, broadcasts} = Tetris.handle_player_leave("p1", :disconnect, join2())
      assert ns.status == :over
      assert ns.winner == "p2"
      assert {:winner, "p2"} in broadcasts
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
end
