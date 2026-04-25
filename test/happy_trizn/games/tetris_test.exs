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

  describe "handle_input — left / right / rotate" do
    setup do: {:ok, state: join2()}

    test "rotate 시 rotation 0..3 사이", %{state: state} do
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

      # 새 piece spawn (origin row=0)
      {new_row, _} = ns.players["p1"].current.origin
      assert new_row == 0

      # next 가 current 로
      assert ns.players["p1"].current.type == orig_next

      # score 증가
      assert ns.players["p1"].score > 0
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

    test ":over → yes + public players (board / bag 제외)" do
      state = join2() |> Map.merge(%{status: :over, winner: "p1"})
      assert {:yes, %{winner: "p1", players: ps}} = Tetris.game_over?(state)

      Enum.each(ps, fn {_, p} ->
        assert Map.has_key?(p, :score)
        assert Map.has_key?(p, :lines)
        assert Map.has_key?(p, :level)
        assert Map.has_key?(p, :top_out)
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
      # I-piece 가로 (rotation 0) cells = [{1,0}, {1,1}, {1,2}, {1,3}]
      # origin {20, 0} 이면 board row 21 채워짐
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
      # O-piece cells 가 row 0,1 (offset). board height 22 → 가장 아래 row 20 까지 가능 (cells row 21 까지)
      assert row == 20
    end
  end

  describe "Piece" do
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
  end
end
