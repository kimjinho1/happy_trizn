defmodule HappyTrizn.Games.MinesweeperTest do
  use ExUnit.Case, async: true

  alias HappyTrizn.Games.Minesweeper

  describe "meta/0" do
    test "single, slug minesweeper" do
      meta = Minesweeper.meta()
      assert meta.slug == "minesweeper"
      assert meta.mode == :single
    end
  end

  describe "init/1" do
    test "10x10 grid, 모든 cell hidden, mines_placed false" do
      {:ok, state} = Minesweeper.init(%{})
      assert state.rows == 10
      assert state.cols == 10
      assert state.mine_count == 12
      assert map_size(state.cells) == 100

      assert Enum.all?(state.cells, fn {_, c} ->
               not c.revealed and not c.flagged and not c.mine
             end)

      refute state.mines_placed
      assert state.over == nil
    end

    test "difficulty easy → 9×9 / 10 mines" do
      {:ok, state} = Minesweeper.init(%{"difficulty" => "easy"})
      assert state.rows == 9
      assert state.cols == 9
      assert state.mine_count == 10
      assert state.difficulty == "easy"
      assert map_size(state.cells) == 81
    end

    test "difficulty medium → 16×16 / 40 mines" do
      {:ok, state} = Minesweeper.init(%{"difficulty" => "medium"})
      assert state.rows == 16
      assert state.cols == 16
      assert state.mine_count == 40
      assert state.difficulty == "medium"
    end

    test "difficulty hard → 16×30 / 99 mines" do
      {:ok, state} = Minesweeper.init(%{"difficulty" => "hard"})
      assert state.rows == 16
      assert state.cols == 30
      assert state.mine_count == 99
      assert state.difficulty == "hard"
    end

    test "difficulty custom → 사용자 지정 적용" do
      {:ok, state} =
        Minesweeper.init(%{
          "difficulty" => "custom",
          "custom_rows" => 12,
          "custom_cols" => 20,
          "custom_mines" => 30
        })

      assert state.rows == 12
      assert state.cols == 20
      assert state.mine_count == 30
      assert state.difficulty == "custom"
    end

    test "difficulty custom — out-of-range rows 는 기본으로 fallback" do
      {:ok, state} =
        Minesweeper.init(%{
          "difficulty" => "custom",
          "custom_rows" => 999,
          "custom_cols" => 8,
          "custom_mines" => 5
        })

      # rows out of [5..30] → 기본 10 으로 fallback
      assert state.rows == 10
      assert state.cols == 8
      assert state.mine_count == 5
    end

    test "difficulty custom — mines 가 셀 수 - 9 초과 시 캡" do
      {:ok, state} =
        Minesweeper.init(%{
          "difficulty" => "custom",
          "custom_rows" => 5,
          "custom_cols" => 5,
          "custom_mines" => 1000
        })

      # 25셀 - 9 safe = 최대 16 mine
      assert state.rows == 5
      assert state.cols == 5
      assert state.mine_count == 16
    end

    test "알 수 없는 difficulty → 기본 10×10/12" do
      {:ok, state} = Minesweeper.init(%{"difficulty" => "ultra"})
      assert state.rows == 10
      assert state.cols == 10
      assert state.mine_count == 12
    end
  end

  describe "first reveal" do
    test "첫 클릭 시 mines 생성됨 + 클릭 위치 안전" do
      {:ok, state} = Minesweeper.init(%{})

      {:ok, new_state, _} =
        Minesweeper.handle_input("p1", %{"action" => "reveal", "r" => 5, "c" => 5}, state)

      assert new_state.mines_placed
      cell = Map.fetch!(new_state.cells, {5, 5})
      assert cell.revealed
      refute cell.mine

      # 인접 8칸도 mine 없어야 (safe zone)
      for dr <- -1..1, dc <- -1..1 do
        nb = Map.get(new_state.cells, {5 + dr, 5 + dc})
        if nb, do: refute(nb.mine)
      end

      # 정확히 mine_count 만큼 mine 있음
      mines = new_state.cells |> Enum.count(fn {_, c} -> c.mine end)
      assert mines == 12
    end
  end

  describe "flag/2" do
    test "hidden cell 에 flag 토글" do
      {:ok, state} = Minesweeper.init(%{})

      {:ok, s1, _} =
        Minesweeper.handle_input("p1", %{"action" => "flag", "r" => 0, "c" => 0}, state)

      assert Map.fetch!(s1.cells, {0, 0}).flagged

      {:ok, s2, _} = Minesweeper.handle_input("p1", %{"action" => "flag", "r" => 0, "c" => 0}, s1)
      refute Map.fetch!(s2.cells, {0, 0}).flagged
    end

    test "이미 revealed 셀에는 flag 안 됨" do
      {:ok, state} = Minesweeper.init(%{})

      {:ok, s1, _} =
        Minesweeper.handle_input("p1", %{"action" => "reveal", "r" => 5, "c" => 5}, state)

      # (5,5) 는 revealed
      cell = Map.fetch!(s1.cells, {5, 5})
      assert cell.revealed

      {:ok, s2, _} = Minesweeper.handle_input("p1", %{"action" => "flag", "r" => 5, "c" => 5}, s1)
      # 변화 없음
      refute Map.fetch!(s2.cells, {5, 5}).flagged
    end
  end

  describe "lose / win" do
    test "mine 클릭 → over=:lose" do
      {:ok, state} = Minesweeper.init(%{})
      # 첫 reveal 로 placement 강제
      {:ok, s1, _} =
        Minesweeper.handle_input("p1", %{"action" => "reveal", "r" => 0, "c" => 0}, state)

      # mine 위치 찾기
      {mr, mc} = s1.cells |> Enum.find(fn {_, c} -> c.mine end) |> elem(0)

      {:ok, s2, _} =
        Minesweeper.handle_input("p1", %{"action" => "reveal", "r" => mr, "c" => mc}, s1)

      assert s2.over == :lose
      # 모든 mine reveal 됨
      mines_revealed =
        s2.cells |> Enum.filter(fn {_, c} -> c.mine end) |> Enum.all?(fn {_, c} -> c.revealed end)

      assert mines_revealed
    end

    test "모든 안전 셀 reveal → over=:win" do
      {:ok, state} = Minesweeper.init(%{})

      {:ok, s1, _} =
        Minesweeper.handle_input("p1", %{"action" => "reveal", "r" => 0, "c" => 0}, state)

      # 모든 안전 셀 강제 reveal
      revealed_all_safe =
        s1.cells
        |> Enum.reject(fn {_, c} -> c.mine end)
        |> Enum.reduce(s1, fn {{r, c}, _}, acc ->
          {:ok, new, _} =
            Minesweeper.handle_input("p1", %{"action" => "reveal", "r" => r, "c" => c}, acc)

          new
        end)

      assert revealed_all_safe.over == :win
    end
  end

  describe "game_over?/1" do
    test "over=nil 이면 :no" do
      {:ok, state} = Minesweeper.init(%{})
      assert :no = Minesweeper.game_over?(state)
    end

    test "over=:win 이면 yes + result" do
      {:ok, state} = Minesweeper.init(%{})
      state = %{state | over: :win}
      assert {:yes, %{result: :win, elapsed_seconds: e}} = Minesweeper.game_over?(state)
      assert is_integer(e)
    end
  end

  describe "out of bounds" do
    test "잘못된 좌표는 무시" do
      {:ok, state} = Minesweeper.init(%{})

      {:ok, ^state, []} =
        Minesweeper.handle_input("p1", %{"action" => "reveal", "r" => -1, "c" => 0}, state)

      {:ok, ^state, []} =
        Minesweeper.handle_input("p1", %{"action" => "reveal", "r" => 100, "c" => 0}, state)
    end

    test "hard 난이도 grid 의 끝 좌표 (15,29) 는 in-bounds" do
      {:ok, state} = Minesweeper.init(%{"difficulty" => "hard"})

      {:ok, new_state, _} =
        Minesweeper.handle_input("p1", %{"action" => "flag", "r" => 15, "c" => 29}, state)

      assert Map.fetch!(new_state.cells, {15, 29}).flagged
    end
  end

  describe "restart" do
    test "easy 게임 restart → 같은 dims 새 게임" do
      {:ok, state} = Minesweeper.init(%{"difficulty" => "easy"})

      {:ok, s1, _} =
        Minesweeper.handle_input("p1", %{"action" => "reveal", "r" => 0, "c" => 0}, state)

      assert s1.mines_placed

      {:ok, fresh, _} = Minesweeper.handle_input("p1", %{"action" => "restart"}, s1)
      assert fresh.rows == 9
      assert fresh.cols == 9
      assert fresh.mine_count == 10
      assert fresh.difficulty == "easy"
      refute fresh.mines_placed
      assert fresh.over == nil
    end
  end
end
