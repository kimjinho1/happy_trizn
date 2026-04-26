defmodule HappyTrizn.Games.Tetris.FinesseTest do
  @moduledoc """
  Sprint 3i — Tetris Finesse 측정.

  Spawn 위치 = (rot=0, col=3) 모든 piece 동일.
  Optimal = rot_inputs + abs(target_col - 3).
  """

  use ExUnit.Case, async: true

  alias HappyTrizn.Games.Tetris.Finesse

  describe "optimal_count/3" do
    test "rot=0, col=3 (spawn 위치 그대로 hard_drop) → 0 입력" do
      assert Finesse.optimal_count(:T, 0, 3) == 0
      assert Finesse.optimal_count(:I, 0, 3) == 0
      assert Finesse.optimal_count(:O, 0, 3) == 0
    end

    test "horizontal 만 — col 차이만큼" do
      assert Finesse.optimal_count(:T, 0, 0) == 3
      assert Finesse.optimal_count(:T, 0, 6) == 3
      assert Finesse.optimal_count(:L, 0, 5) == 2
    end

    test "rotation cw/ccw → +1" do
      assert Finesse.optimal_count(:T, 1, 3) == 1
      assert Finesse.optimal_count(:T, 3, 3) == 1
    end

    test "rotation 180 → +1 (180 키 사용 가정)" do
      assert Finesse.optimal_count(:T, 2, 3) == 1
    end

    test "rotation + 이동 합산" do
      assert Finesse.optimal_count(:S, 1, 0) == 1 + 3
      assert Finesse.optimal_count(:Z, 2, 7) == 1 + 4
    end

    test "O piece → rotation 무시 (회전 자체가 violation 유발)" do
      assert Finesse.optimal_count(:O, 1, 3) == 0
      assert Finesse.optimal_count(:O, 2, 3) == 0
      assert Finesse.optimal_count(:O, 3, 3) == 0
      assert Finesse.optimal_count(:O, 1, 5) == 2
    end
  end

  describe "evaluate/4" do
    test "actual <= optimal → :ok" do
      assert Finesse.evaluate(:T, 0, 3, 0) == :ok
      assert Finesse.evaluate(:T, 1, 5, 3) == :ok
      assert Finesse.evaluate(:I, 0, 0, 3) == :ok
    end

    test "actual > optimal → :violation" do
      # spawn 위치 그대로 lock 했는데 입력 1번 = 낭비.
      assert Finesse.evaluate(:T, 0, 3, 1) == :violation
      # col 5 까지 1번 이동, rot 1 → optimal=3, actual=5.
      assert Finesse.evaluate(:T, 1, 5, 5) == :violation
    end

    test "O 회전 입력 = violation (optimal 은 회전 무시)" do
      # col 3 그대로 lock + 회전 1번 → optimal=0, actual=1.
      assert Finesse.evaluate(:O, 1, 3, 1) == :violation
    end

    test "벽 끝 도달 — col 0/9 까지" do
      assert Finesse.evaluate(:I, 0, 0, 3) == :ok
      assert Finesse.evaluate(:I, 0, 0, 4) == :violation
      assert Finesse.evaluate(:L, 1, 9, 1 + 6) == :ok
      assert Finesse.evaluate(:L, 1, 9, 1 + 7) == :violation
    end
  end
end
