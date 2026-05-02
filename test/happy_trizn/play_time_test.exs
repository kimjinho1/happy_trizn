defmodule HappyTrizn.PlayTimeTest do
  use HappyTrizn.DataCase, async: false

  alias HappyTrizn.PlayTime

  defp register!(suffix) do
    {:ok, u} =
      HappyTrizn.Accounts.register_user(%{
        email: "pt#{suffix}@trizn.kr",
        nickname: "pt#{suffix}",
        password: "hello12345"
      })

    u
  end

  defp now, do: DateTime.utc_now()

  describe "record/5" do
    test "정상 record — duration > 0", %{} do
      u = register!(System.unique_integer([:positive]))
      started = now() |> DateTime.add(-120, :second)
      assert {:ok, log} = PlayTime.record(u.id, "tetris", started, now())
      assert log.user_id == u.id
      assert log.game_type == "tetris"
      assert log.duration_seconds >= 119
      assert log.duration_seconds <= 121
    end

    test "duration 0 → skip", %{} do
      u = register!(System.unique_integer([:positive]))
      t = now()
      assert {:ok, :skipped_zero_duration} = PlayTime.record(u.id, "tetris", t, t)
    end

    test "user_id nil (게스트) 도 저장", %{} do
      started = now() |> DateTime.add(-30, :second)
      assert {:ok, log} = PlayTime.record(nil, "snake_io", started, now())
      assert log.user_id == nil
      assert log.duration_seconds >= 29
    end

    test "room_id 저장 (멀티) / nil (싱글)", %{} do
      u = register!(System.unique_integer([:positive]))
      started = now() |> DateTime.add(-10, :second)
      room_id = Ecto.UUID.generate()

      {:ok, multi} = PlayTime.record(u.id, "bomberman", started, now(), room_id)
      {:ok, single} = PlayTime.record(u.id, "sudoku", started, now(), nil)

      assert multi.room_id == room_id
      assert single.room_id == nil
    end
  end

  describe "사용자 조회" do
    setup do
      u = register!(System.unique_integer([:positive]))
      base = DateTime.utc_now()

      # 3 different games, different durations.
      {:ok, _} = PlayTime.record(u.id, "tetris", DateTime.add(base, -100, :second), base)
      {:ok, _} = PlayTime.record(u.id, "tetris", DateTime.add(base, -50, :second), base)
      {:ok, _} = PlayTime.record(u.id, "bomberman", DateTime.add(base, -30, :second), base)
      {:ok, _} = PlayTime.record(u.id, "snake_io", DateTime.add(base, -10, :second), base)

      {:ok, user: u}
    end

    test "total_seconds_for_user — 전체 합", %{user: u} do
      total = PlayTime.total_seconds_for_user(u.id)
      # 100 + 50 + 30 + 10 = 190 (±몇 초)
      assert total >= 188 and total <= 192
    end

    test "total_seconds_for_user — game_type 필터", %{user: u} do
      tetris = PlayTime.total_seconds_for_user(u.id, game_type: "tetris")
      assert tetris >= 148 and tetris <= 152
    end

    test "by_game_for_user — 게임별 정렬 (desc)", %{user: u} do
      results = PlayTime.by_game_for_user(u.id)
      assert [{"tetris", _}, {"bomberman", _}, {"snake_io", _}] = results
    end
  end

  describe "기간 filter" do
    test "period_cutoff/1 — :day 는 오늘 0시", %{} do
      cutoff = PlayTime.period_cutoff(:day)
      today = Date.utc_today()
      assert DateTime.to_date(cutoff) == today
      assert cutoff.hour == 0
    end

    test "period_cutoff/1 — :week 는 7일 전", %{} do
      cutoff = PlayTime.period_cutoff(:week)
      diff = DateTime.diff(DateTime.utc_now(), cutoff, :second)
      assert diff >= 7 * 86400 - 5 and diff <= 7 * 86400 + 5
    end

    test "기간 필터 — 30일 전 데이터는 :week filter 시 제외", %{} do
      u = register!(System.unique_integer([:positive]))
      old = DateTime.utc_now() |> DateTime.add(-30 * 86400, :second)

      {:ok, _} =
        PlayTime.record(u.id, "tetris", old, DateTime.add(old, 60, :second))

      assert PlayTime.total_seconds_for_user(u.id, period: :week) == 0
      assert PlayTime.total_seconds_for_user(u.id, period: :all) >= 60
    end
  end

  describe "Admin 조회" do
    test "by_game_admin — 모든 사용자 게임별 합", %{} do
      u1 = register!(System.unique_integer([:positive]))
      u2 = register!(System.unique_integer([:positive]))
      base = DateTime.utc_now()

      {:ok, _} = PlayTime.record(u1.id, "tetris", DateTime.add(base, -100, :second), base)
      {:ok, _} = PlayTime.record(u2.id, "tetris", DateTime.add(base, -50, :second), base)
      {:ok, _} = PlayTime.record(u1.id, "bomberman", DateTime.add(base, -30, :second), base)

      results = PlayTime.by_game_admin(:all) |> Enum.into(%{})
      assert Map.get(results, "tetris") >= 148
      assert Map.get(results, "bomberman") >= 28
    end

    test "top_users — 사용자별 누적 desc", %{} do
      u1 = register!(System.unique_integer([:positive]))
      u2 = register!(System.unique_integer([:positive]))
      base = DateTime.utc_now()

      {:ok, _} = PlayTime.record(u1.id, "tetris", DateTime.add(base, -200, :second), base)
      {:ok, _} = PlayTime.record(u2.id, "tetris", DateTime.add(base, -50, :second), base)

      [first | _] = PlayTime.top_users(:all)
      # u1 이 더 오래 → 1등
      assert first.user_id == u1.id
    end

    test "총 누적 = 모든 row 합", %{} do
      u = register!(System.unique_integer([:positive]))
      base = DateTime.utc_now()

      {:ok, _} = PlayTime.record(u.id, "tetris", DateTime.add(base, -10, :second), base)
      {:ok, _} = PlayTime.record(nil, "snake_io", DateTime.add(base, -20, :second), base)

      total = PlayTime.total_seconds_admin(:all)
      assert total >= 28 and total <= 32
    end
  end

  describe "format_duration/1" do
    test "3661s → '1h 1m'" do
      assert PlayTime.format_duration(3661) == "1h 1m"
    end

    test "125s → '2m 5s'" do
      assert PlayTime.format_duration(125) == "2m 5s"
    end

    test "45s → '45s'" do
      assert PlayTime.format_duration(45) == "45s"
    end

    test "0 / nil → '0s'" do
      assert PlayTime.format_duration(0) == "0s"
      assert PlayTime.format_duration(nil) == "0s"
    end
  end
end
