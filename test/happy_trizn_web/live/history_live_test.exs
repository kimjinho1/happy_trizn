defmodule HappyTriznWeb.HistoryLiveTest do
  use HappyTriznWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias HappyTrizn.{MatchResults, PersonalRecords}

  describe "/history — 인증 가드" do
    test "비입장 → / 리다이렉트", %{conn: conn} do
      conn = Plug.Test.init_test_session(conn, %{})
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/history")
    end
  end

  describe "/history — index" do
    setup %{conn: conn} do
      user = user_fixture(nickname: "h_#{System.unique_integer([:positive])}")
      {:ok, conn: log_in_user(conn, user), user: user}
    end

    test "기록 없으면 빈 메시지", %{conn: conn} do
      {:ok, _, html} = live(conn, ~p"/history")
      assert html =~ "내 기록"
      assert html =~ "아직 기록 없음" or html =~ "아직 우승 기록"
    end

    test "PersonalRecord + MatchResult 표시", %{conn: conn, user: user} do
      {:ok, _} =
        PersonalRecords.apply_stats(user, "tetris", %{score: 999, lines: 8, won: true})

      {:ok, _} =
        MatchResults.record(%{
          game_type: "tetris",
          room_id: Ecto.UUID.generate(),
          winner_id: user.id,
          duration_ms: 60_000,
          stats: %{"players" => %{"p1" => %{"score" => 999}}}
        })

      {:ok, _, html} = live(conn, ~p"/history")
      assert html =~ "999"
      assert html =~ "tetris"
      # 우승 row
      assert html =~ "1:00"
    end
  end

  describe "/history/leaderboard/:game_type" do
    setup %{conn: conn} do
      user = user_fixture(nickname: "lb_#{System.unique_integer([:positive])}")
      {:ok, conn: log_in_user(conn, user), user: user}
    end

    test "leaderboard 마운트 + 닉네임 + 점수 표시", %{conn: conn, user: user} do
      other = user_fixture(nickname: "lb_other_#{System.unique_integer([:positive])}")
      {:ok, _} = PersonalRecords.apply_stats(user, "tetris", %{score: 500})
      {:ok, _} = PersonalRecords.apply_stats(other, "tetris", %{score: 1500})

      {:ok, _, html} = live(conn, ~p"/history/leaderboard/tetris")
      assert html =~ "Tetris 리더보드"
      assert html =~ user.nickname
      assert html =~ other.nickname
      assert html =~ "1500"
    end

    test "없는 game_type → /history redirect", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/history"}}} =
               live(conn, ~p"/history/leaderboard/nope")
    end
  end
end
