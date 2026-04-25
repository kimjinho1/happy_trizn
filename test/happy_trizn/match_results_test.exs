defmodule HappyTrizn.MatchResultsTest do
  use HappyTrizn.DataCase, async: true

  alias HappyTrizn.MatchResults
  alias HappyTrizn.MatchResults.MatchResult

  defp user_fixture(s \\ nil) do
    s = s || System.unique_integer([:positive])

    {:ok, u} =
      HappyTrizn.Accounts.register_user(%{
        email: "mr#{s}@trizn.kr",
        nickname: "mr#{s}",
        password: "hello12345"
      })

    u
  end

  describe "record/1" do
    test "유효한 attrs 로 row 저장" do
      assert {:ok, %MatchResult{} = r} =
               MatchResults.record(%{
                 game_type: "tetris",
                 room_id: nil,
                 winner_id: nil,
                 duration_ms: 12_345,
                 stats: %{"foo" => "bar"}
               })

      assert r.game_type == "tetris"
      assert r.duration_ms == 12_345
      assert r.stats == %{"foo" => "bar"}
      assert r.finished_at
    end

    test "winner_id 사용자 매칭" do
      u = user_fixture()

      assert {:ok, r} =
               MatchResults.record(%{
                 game_type: "tetris",
                 room_id: nil,
                 winner_id: u.id,
                 duration_ms: 1000,
                 stats: %{}
               })

      assert r.winner_id == u.id
    end

    test "필수 필드 빠지면 error" do
      assert {:error, %Ecto.Changeset{} = cs} =
               MatchResults.record(%{
                 room_id: nil,
                 winner_id: nil,
                 stats: %{}
               })

      assert errors_on(cs)[:game_type]
    end

    test "duration_ms 음수 거부" do
      assert {:error, cs} =
               MatchResults.record(%{
                 game_type: "tetris",
                 duration_ms: -10,
                 stats: %{}
               })

      assert errors_on(cs)[:duration_ms]
    end
  end

  describe "for_user/1" do
    test "winner_id 매칭만 반환" do
      u1 = user_fixture()
      u2 = user_fixture()

      {:ok, _} =
        MatchResults.record(%{game_type: "tetris", duration_ms: 1, stats: %{}, winner_id: u1.id})

      {:ok, _} =
        MatchResults.record(%{game_type: "tetris", duration_ms: 2, stats: %{}, winner_id: u2.id})

      {:ok, _} =
        MatchResults.record(%{game_type: "tetris", duration_ms: 3, stats: %{}, winner_id: nil})

      assert [r1] = MatchResults.for_user(u1)
      assert r1.winner_id == u1.id

      assert MatchResults.for_user(nil) == []
    end
  end

  describe "recent/2" do
    test "최근 N개, game_type 필터" do
      {:ok, _} = MatchResults.record(%{game_type: "tetris", duration_ms: 1, stats: %{}})
      {:ok, _} = MatchResults.record(%{game_type: "bomberman", duration_ms: 2, stats: %{}})

      tetris = MatchResults.recent("tetris", 50)
      assert length(tetris) == 1
      assert hd(tetris).game_type == "tetris"

      assert length(MatchResults.recent(nil, 50)) == 2
    end
  end
end
