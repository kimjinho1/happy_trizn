defmodule HappyTrizn.GameSnapshotsTest do
  use HappyTrizn.DataCase, async: false

  alias HappyTrizn.GameSnapshots

  defp register!(suffix) do
    {:ok, u} =
      HappyTrizn.Accounts.register_user(%{
        email: "snap#{suffix}@trizn.kr",
        nickname: "snap#{suffix}",
        password: "hello12345"
      })

    u
  end

  setup do
    {:ok, user: register!(System.unique_integer([:positive]))}
  end

  describe "serializable?/1" do
    test "sudoku / 2048 / minesweeper → true" do
      assert GameSnapshots.serializable?("sudoku")
      assert GameSnapshots.serializable?("2048")
      assert GameSnapshots.serializable?("minesweeper")
    end

    test "tetris / bomberman / pacman / unknown → false" do
      refute GameSnapshots.serializable?("tetris")
      refute GameSnapshots.serializable?("bomberman")
      refute GameSnapshots.serializable?("pacman")
      refute GameSnapshots.serializable?("snake_io")
      refute GameSnapshots.serializable?("skribbl")
      refute GameSnapshots.serializable?("nonexistent")
      refute GameSnapshots.serializable?(nil)
    end
  end

  describe "upsert/4 + get/3 round-trip" do
    test "단순 map state 저장 후 복원", %{user: u} do
      state = %{score: 42, board: [[2, nil, 4], [nil, nil, nil]], size: 3}
      assert {:ok, _} = GameSnapshots.upsert(u.id, "2048", state)
      assert ^state = GameSnapshots.get(u.id, "2048")
    end

    test "tuple key 가진 map 보존 (Sudoku/Minesweeper 의 cursor / cells)", %{user: u} do
      state = %{
        cursor: {3, 5},
        fixed: %{{0, 0} => 5, {1, 1} => 9},
        board: [[1, nil], [nil, 2]]
      }

      assert {:ok, _} = GameSnapshots.upsert(u.id, "sudoku", state)
      restored = GameSnapshots.get(u.id, "sudoku")
      assert restored.cursor == {3, 5}
      assert restored.fixed == %{{0, 0} => 5, {1, 1} => 9}
    end

    test "atom 보존 (status :playing 등)", %{user: u} do
      state = %{status: :playing, over: nil, difficulty: :hard}
      assert {:ok, _} = GameSnapshots.upsert(u.id, "minesweeper", state)
      assert ^state = GameSnapshots.get(u.id, "minesweeper")
    end

    test "두 번 upsert → 새 값으로 덮어쓰기 (DB row 1개)", %{user: u} do
      assert {:ok, _} = GameSnapshots.upsert(u.id, "2048", %{v: 1})
      assert {:ok, _} = GameSnapshots.upsert(u.id, "2048", %{v: 2})
      assert %{v: 2} = GameSnapshots.get(u.id, "2048")

      n = HappyTrizn.Repo.aggregate(HappyTrizn.GameSnapshots.Snapshot, :count, :id)
      assert n == 1
    end

    test "다른 game_type 는 별도 row", %{user: u} do
      {:ok, _} = GameSnapshots.upsert(u.id, "sudoku", %{a: 1})
      {:ok, _} = GameSnapshots.upsert(u.id, "2048", %{b: 2})
      assert %{a: 1} = GameSnapshots.get(u.id, "sudoku")
      assert %{b: 2} = GameSnapshots.get(u.id, "2048")
    end

    test "다른 user 는 별도 row", %{user: u} do
      u2 = register!(System.unique_integer([:positive]))
      {:ok, _} = GameSnapshots.upsert(u.id, "2048", %{x: "u1"})
      {:ok, _} = GameSnapshots.upsert(u2.id, "2048", %{x: "u2"})
      assert %{x: "u1"} = GameSnapshots.get(u.id, "2048")
      assert %{x: "u2"} = GameSnapshots.get(u2.id, "2048")
    end

    test "schema_version 다르면 nil (옛 snapshot 폐기)", %{user: u} do
      {:ok, _} = GameSnapshots.upsert(u.id, "sudoku", %{v: 1}, 1)
      # 게임 모듈 v2 로 bump → 옛 v1 snapshot 안 가져옴.
      assert nil == GameSnapshots.get(u.id, "sudoku", 2)
      # 같은 v1 로 요청 시는 정상.
      assert %{v: 1} = GameSnapshots.get(u.id, "sudoku", 1)
    end

    test "없는 snapshot → nil", %{user: u} do
      assert nil == GameSnapshots.get(u.id, "sudoku")
    end
  end

  describe "delete/2" do
    test "snapshot 삭제 후 get → nil", %{user: u} do
      {:ok, _} = GameSnapshots.upsert(u.id, "2048", %{v: 1})
      assert :ok = GameSnapshots.delete(u.id, "2048")
      assert nil == GameSnapshots.get(u.id, "2048")
    end

    test "다른 game_type 는 영향 X", %{user: u} do
      {:ok, _} = GameSnapshots.upsert(u.id, "2048", %{v: 1})
      {:ok, _} = GameSnapshots.upsert(u.id, "sudoku", %{v: 2})
      :ok = GameSnapshots.delete(u.id, "2048")
      assert nil == GameSnapshots.get(u.id, "2048")
      assert %{v: 2} = GameSnapshots.get(u.id, "sudoku")
    end

    test "없는 snapshot 삭제 호출 안전 (no error)", %{user: u} do
      assert :ok = GameSnapshots.delete(u.id, "sudoku")
    end
  end

  describe "delete_all_for_user/1" do
    test "user 의 모든 snapshot 삭제", %{user: u} do
      {:ok, _} = GameSnapshots.upsert(u.id, "2048", %{v: 1})
      {:ok, _} = GameSnapshots.upsert(u.id, "sudoku", %{v: 2})
      {:ok, _} = GameSnapshots.upsert(u.id, "minesweeper", %{v: 3})

      :ok = GameSnapshots.delete_all_for_user(u.id)

      assert nil == GameSnapshots.get(u.id, "2048")
      assert nil == GameSnapshots.get(u.id, "sudoku")
      assert nil == GameSnapshots.get(u.id, "minesweeper")
    end
  end
end
