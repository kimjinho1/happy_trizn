defmodule HappyTrizn.PersonalRecordsTest do
  use HappyTrizn.DataCase, async: true

  alias HappyTrizn.PersonalRecords
  alias HappyTrizn.PersonalRecords.Record

  defp user_fixture(s \\ nil) do
    s = s || System.unique_integer([:positive])

    {:ok, u} =
      HappyTrizn.Accounts.register_user(%{
        email: "pr#{s}@trizn.kr",
        nickname: "pr#{s}",
        password: "hello12345"
      })

    u
  end

  describe "apply_stats/3" do
    test "신규 row — 점수/라인 + won 카운트" do
      user = user_fixture()

      assert {:ok, %Record{} = r} =
               PersonalRecords.apply_stats(user, "tetris", %{
                 score: 1000,
                 lines: 10,
                 won: true
               })

      assert r.max_score == 1000
      assert r.max_lines == 10
      assert r.total_wins == 1
    end

    test "기존 row — 더 높은 점수면 갱신, 낮으면 유지" do
      user = user_fixture()
      {:ok, _} = PersonalRecords.apply_stats(user, "tetris", %{score: 500, lines: 5, won: true})

      # 더 낮은 점수 — max 유지, total_wins +1
      {:ok, r} = PersonalRecords.apply_stats(user, "tetris", %{score: 300, lines: 3, won: true})
      assert r.max_score == 500
      assert r.max_lines == 5
      assert r.total_wins == 2

      # 더 높은 점수 — 갱신
      {:ok, r} = PersonalRecords.apply_stats(user, "tetris", %{score: 999, lines: 12, won: false})
      assert r.max_score == 999
      assert r.max_lines == 12
      assert r.total_wins == 2
    end

    test "metadata numeric — max 비교 merge" do
      user = user_fixture()
      {:ok, _} = PersonalRecords.apply_stats(user, "tetris", %{metadata: %{"max_pps" => 1.5}})
      {:ok, r} = PersonalRecords.apply_stats(user, "tetris", %{metadata: %{"max_pps" => 0.9}})
      assert r.metadata["max_pps"] == 1.5

      {:ok, r} = PersonalRecords.apply_stats(user, "tetris", %{metadata: %{"max_pps" => 2.1}})
      assert r.metadata["max_pps"] == 2.1
    end

    test "게스트 → :guest" do
      assert {:error, :guest} = PersonalRecords.apply_stats(nil, "tetris", %{})
    end

    test "잘못된 game_type 거부" do
      user = user_fixture()

      assert {:error, %Ecto.Changeset{} = cs} =
               PersonalRecords.apply_stats(user, "haxxor", %{score: 1})

      assert "is invalid" in errors_on(cs).game_type
    end
  end

  describe "get_for/2 + list_for_user/1" do
    test "user 의 기록 반환" do
      user = user_fixture()
      {:ok, _} = PersonalRecords.apply_stats(user, "tetris", %{score: 100})

      r = PersonalRecords.get_for(user, "tetris")
      assert r.max_score == 100

      assert PersonalRecords.get_for(user, "snake_io") == nil
      assert length(PersonalRecords.list_for_user(user)) == 1
    end

    test "nil 사용자 → nil / []" do
      assert PersonalRecords.get_for(nil, "tetris") == nil
      assert PersonalRecords.list_for_user(nil) == []
    end
  end

  describe "leaderboard/2" do
    test "max_score desc 정렬, max_score=0 제외" do
      a = user_fixture()
      b = user_fixture()
      c = user_fixture()
      {:ok, _} = PersonalRecords.apply_stats(a, "tetris", %{score: 500})
      {:ok, _} = PersonalRecords.apply_stats(b, "tetris", %{score: 1500})
      {:ok, _} = PersonalRecords.apply_stats(c, "tetris", %{score: 0})

      rows = PersonalRecords.leaderboard("tetris", 10)
      assert length(rows) == 2
      [first, second] = rows
      assert first.user.id == b.id
      assert first.max_score == 1500
      assert second.user.id == a.id
    end
  end
end
