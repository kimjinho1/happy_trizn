defmodule HappyTrizn.Games.SudokuTest do
  use ExUnit.Case, async: true

  alias HappyTrizn.Games.Sudoku

  describe "meta + init" do
    test "single 1인 + slug sudoku" do
      m = Sudoku.meta()
      assert m.slug == "sudoku"
      assert m.name == "스도쿠"
      assert m.mode == :single
      assert m.max_players == 1
    end

    test "init default → easy 난이도 + clue 40" do
      {:ok, state} = Sudoku.init(%{})
      assert state.difficulty == "easy"
      assert state.clues == 40
    end

    test "init custom 난이도" do
      for {d, c} <- [{"easy", 40}, {"medium", 32}, {"hard", 26}] do
        {:ok, state} = Sudoku.init(%{"difficulty" => d})
        assert state.difficulty == d
        assert state.clues == c
      end
    end

    test "잘못된 난이도 → easy fallback" do
      {:ok, state} = Sudoku.init(%{"difficulty" => "expert"})
      assert state.difficulty == "easy"
    end
  end

  describe "Generation — 항상 valid solution" do
    test "random_solution/0 100번 모두 valid (rows/cols/boxes 1..9)" do
      for _ <- 1..100 do
        sol = Sudoku.random_solution()
        assert Sudoku.valid_solution?(sol),
               "invalid solution generated: #{inspect(sol)}"
      end
    end

    test "init 한 puzzle.solution 도 valid" do
      for _ <- 1..30 do
        {:ok, state} = Sudoku.init(%{"difficulty" => "medium"})
        assert Sudoku.valid_solution?(state.solution)
      end
    end

    test "puzzle 의 fixed cell 들 = solution 동일" do
      {:ok, state} = Sudoku.init(%{"difficulty" => "easy"})

      for {{r, c}, _} <- state.fixed do
        puzzle_v = Enum.at(Enum.at(state.puzzle, r), c)
        sol_v = Enum.at(Enum.at(state.solution, r), c)
        assert puzzle_v == sol_v
      end
    end

    test "fixed cell 수 = clue_count" do
      {:ok, state} = Sudoku.init(%{"difficulty" => "easy"})
      assert map_size(state.fixed) == 40
    end

    test "puzzle nil cell 수 = 81 - clue_count" do
      {:ok, state} = Sudoku.init(%{"difficulty" => "hard"})

      nil_count =
        state.puzzle
        |> List.flatten()
        |> Enum.count(&is_nil/1)

      assert nil_count == 81 - 26
    end

    test "user state 초기 = puzzle (사용자 입력 전)" do
      {:ok, state} = Sudoku.init(%{"difficulty" => "easy"})
      assert state.user == state.puzzle
    end

    test "초기 cursor = (0, 0)" do
      {:ok, state} = Sudoku.init(%{})
      assert state.cursor == {0, 0}
    end
  end

  describe "handle_input cursor + enter" do
    test "set_cursor 직접 좌표 이동" do
      {:ok, state} = Sudoku.init(%{})

      {:ok, s, _} =
        Sudoku.handle_input("p1", %{"action" => "set_cursor", "r" => 4, "c" => 5}, state)

      assert s.cursor == {4, 5}
    end

    test "set_cursor — phx-value string r/c 강제 정수화" do
      {:ok, state} = Sudoku.init(%{})

      {:ok, s, _} =
        Sudoku.handle_input("p1", %{"action" => "set_cursor", "r" => "3", "c" => "7"}, state)

      assert s.cursor == {3, 7}
    end

    test "move_cursor + boundary clamp" do
      {:ok, init_state} = Sudoku.init(%{})
      state = %{init_state | cursor: {0, 0}}

      {:ok, s, _} = Sudoku.handle_input("p1", %{"action" => "move_cursor", "dir" => "up"}, state)
      assert s.cursor == {0, 0}

      {:ok, s, _} = Sudoku.handle_input("p1", %{"action" => "move_cursor", "dir" => "right"}, s)
      assert s.cursor == {0, 1}

      state8_8 = %{state | cursor: {8, 8}}

      {:ok, s, _} =
        Sudoku.handle_input("p1", %{"action" => "move_cursor", "dir" => "down"}, state8_8)

      assert s.cursor == {8, 8}
    end

    test "enter — fixed cell 변경 안 됨" do
      {:ok, state} = Sudoku.init(%{})
      [{r, c} | _] = Map.keys(state.fixed)
      original = Enum.at(Enum.at(state.user, r), c)
      state = %{state | cursor: {r, c}}

      {:ok, s, _} = Sudoku.handle_input("p1", %{"action" => "enter", "n" => 1}, state)

      assert Enum.at(Enum.at(s.user, r), c) == original
    end

    test "enter — non-fixed cell 에 1-9 설정" do
      {:ok, state} = Sudoku.init(%{})
      [{r, c} | _] = empty_positions(state)
      state = %{state | cursor: {r, c}}

      {:ok, s, _} = Sudoku.handle_input("p1", %{"action" => "enter", "n" => 5}, state)

      assert Enum.at(Enum.at(s.user, r), c) == 5
    end

    test "enter 0 → cell clear (nil)" do
      {:ok, state} = Sudoku.init(%{})
      [{r, c} | _] = empty_positions(state)
      state = %{state | cursor: {r, c}}

      {:ok, s, _} = Sudoku.handle_input("p1", %{"action" => "enter", "n" => 5}, state)
      assert Enum.at(Enum.at(s.user, r), c) == 5

      {:ok, s2, _} = Sudoku.handle_input("p1", %{"action" => "enter", "n" => 0}, s)
      assert is_nil(Enum.at(Enum.at(s2.user, r), c))
    end

    test "clear_cursor — non-fixed cell nil 로" do
      {:ok, state} = Sudoku.init(%{})
      [{r, c} | _] = empty_positions(state)
      state = %{state | cursor: {r, c}}

      {:ok, s, _} = Sudoku.handle_input("p1", %{"action" => "enter", "n" => 7}, state)
      assert Enum.at(Enum.at(s.user, r), c) == 7

      {:ok, s2, _} = Sudoku.handle_input("p1", %{"action" => "clear_cursor"}, s)
      assert is_nil(Enum.at(Enum.at(s2.user, r), c))
    end

    test "n 범위 밖 (10) → 무시" do
      {:ok, state} = Sudoku.init(%{})
      [{r, c} | _] = empty_positions(state)
      state = %{state | cursor: {r, c}}

      {:ok, s, _} = Sudoku.handle_input("p1", %{"action" => "enter", "n" => 10}, state)
      assert Enum.at(Enum.at(s.user, r), c) == nil
    end
  end

  describe "win 조건" do
    test "user == solution → over=:win + game_over? :yes" do
      {:ok, state} = Sudoku.init(%{})
      state = %{state | user: state.solution}

      # set_cell trigger 위해 cursor 빈 셀에 두고 0 입력 — user 그대로 (이미 solution).
      [{r, c} | _] = empty_positions(state)
      state = %{state | cursor: {r, c}, user: state.solution}

      # 빈 셀 하나만 비워두고 채우면 win 트리거.
      partial = put_in(state.user, [Access.at(r), Access.at(c)], nil)
      state = %{state | user: partial, cursor: {r, c}}

      target = Enum.at(Enum.at(state.solution, r), c)
      {:ok, s, _} = Sudoku.handle_input("p1", %{"action" => "enter", "n" => target}, state)

      assert s.over == :win
      assert {:yes, %{result: :win}} = Sudoku.game_over?(s)
    end

    test "win 후 enter 무시 (over)" do
      {:ok, state} = Sudoku.init(%{})
      state = %{state | over: :win}
      [{r, c} | _] = empty_positions(state)
      state = %{state | cursor: {r, c}}

      {:ok, s, _} = Sudoku.handle_input("p1", %{"action" => "enter", "n" => 5}, state)

      assert is_nil(Enum.at(Enum.at(s.user, r), c))
    end
  end

  describe "restart" do
    test "restart → 같은 difficulty 새 puzzle" do
      {:ok, state} = Sudoku.init(%{"difficulty" => "medium"})
      {:ok, fresh, _} = Sudoku.handle_input("p1", %{"action" => "restart"}, state)
      assert fresh.difficulty == "medium"
      assert fresh.clues == 32
      assert fresh.over == nil
    end
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp empty_positions(state) do
    for r <- 0..8, c <- 0..8, not Map.has_key?(state.fixed, {r, c}), do: {r, c}
  end
end
