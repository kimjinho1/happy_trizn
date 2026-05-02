defmodule HappyTrizn.PlayTime do
  @moduledoc """
  실제 게임 플레이 시간 추적 + 집계 (Sprint 5b).

  - `record/5` — 한 playing 세션 끝났을 때 호출. user_id nil 이면 게스트.
  - `total_seconds_for_user/2` — 사용자 한 명의 누적 플레이 시간 (게임별 또는 전체).
  - `by_game_for_user/2` — 사용자 게임별 합 (사용자 페이지).
  - `by_period_for_user/3` — 사용자 기간별 (일/주/월/년).
  - `top_users/2` — admin: 사용자별 통합 (선택 기간).
  - `by_game_admin/1` — admin: 게임별 전체 합 (선택 기간).

  기간 (period) 은 atom: `:day` (오늘 0시~24시), `:week` (최근 7일), `:month` (최근 30일),
  `:year` (최근 365일), `:all` (전체).
  """

  import Ecto.Query

  alias HappyTrizn.PlayTime.Log
  alias HappyTrizn.Repo

  # ============================================================================
  # Insert
  # ============================================================================

  @doc """
  한 playing 세션 (status :playing 진입 → 벗어남) 종료 시 호출.

  duration_seconds 가 0 이하면 저장 X (의미 없음, ms 단위 짧은 transition 등).
  """
  def record(user_id, game_type, started_at, ended_at, room_id \\ nil)
      when is_binary(game_type) and not is_nil(started_at) and not is_nil(ended_at) do
    duration = DateTime.diff(ended_at, started_at, :second)

    if duration > 0 do
      attrs = %{
        user_id: user_id,
        game_type: game_type,
        duration_seconds: duration,
        started_at: DateTime.truncate(started_at, :second),
        ended_at: DateTime.truncate(ended_at, :second),
        room_id: room_id
      }

      %Log{}
      |> Log.changeset(attrs)
      |> Repo.insert()
    else
      {:ok, :skipped_zero_duration}
    end
  end

  # ============================================================================
  # Period helpers
  # ============================================================================

  @doc "기간 atom → {:gte, dt} cutoff. :all 은 nil."
  def period_cutoff(:day) do
    today_start =
      DateTime.utc_now()
      |> DateTime.to_date()
      |> DateTime.new!(~T[00:00:00], "Etc/UTC")

    today_start
  end

  def period_cutoff(:week), do: DateTime.utc_now() |> DateTime.add(-7 * 86400, :second)
  def period_cutoff(:month), do: DateTime.utc_now() |> DateTime.add(-30 * 86400, :second)
  def period_cutoff(:year), do: DateTime.utc_now() |> DateTime.add(-365 * 86400, :second)
  def period_cutoff(:all), do: nil

  defp filter_period(query, :all), do: query

  defp filter_period(query, period) do
    cutoff = period_cutoff(period)
    where(query, [l], l.started_at >= ^cutoff)
  end

  # ============================================================================
  # 사용자 본인 조회
  # ============================================================================

  @doc "사용자 한 명의 누적 플레이 시간 (game_type nil 이면 전체 합)."
  def total_seconds_for_user(user_id, opts \\ []) when is_binary(user_id) do
    period = Keyword.get(opts, :period, :all)
    game_type = Keyword.get(opts, :game_type)

    Log
    |> where([l], l.user_id == ^user_id)
    |> filter_game(game_type)
    |> filter_period(period)
    |> select([l], type(coalesce(sum(l.duration_seconds), 0), :integer))
    |> Repo.one()
  end

  @doc """
  사용자 게임별 합 (사용자 페이지). [{game_type, seconds}, ...] descending by seconds.
  """
  def by_game_for_user(user_id, period \\ :all) when is_binary(user_id) do
    Log
    |> where([l], l.user_id == ^user_id)
    |> filter_period(period)
    |> group_by([l], l.game_type)
    |> select([l], {l.game_type, type(sum(l.duration_seconds), :integer)})
    |> order_by([l], desc: sum(l.duration_seconds))
    |> Repo.all()
  end

  @doc """
  사용자 기간별 시계열 — by_period_for_user(user_id, :game_type, :day) 등.
  return: [{date_or_period_label, seconds}, ...]
  """
  def by_period_for_user(user_id, game_type \\ nil, period \\ :month) when is_binary(user_id) do
    Log
    |> where([l], l.user_id == ^user_id)
    |> filter_game(game_type)
    |> filter_period(period)
    |> group_by([l], fragment("DATE(?)", l.started_at))
    |> select([l], {fragment("DATE(?)", l.started_at), sum(l.duration_seconds)})
    |> order_by([l], asc: fragment("DATE(?)", l.started_at))
    |> Repo.all()
  end

  # ============================================================================
  # Admin 조회
  # ============================================================================

  @doc """
  Admin: 사용자별 통합 — top_users(:month). [{user_id, nickname, seconds}, ...].
  user_id nil (게스트) 은 nickname "(게스트)" 로 표시.
  limit default 50.
  """
  def top_users(period \\ :all, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Log
    |> filter_period(period)
    |> join(:left, [l], u in assoc(l, :user))
    |> group_by([l, u], [l.user_id, u.nickname])
    |> select([l, u], %{
      user_id: l.user_id,
      nickname: u.nickname,
      seconds: type(sum(l.duration_seconds), :integer)
    })
    |> order_by([l], desc: sum(l.duration_seconds))
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "Admin: 게임별 전체 합. [{game_type, seconds}, ...] descending."
  def by_game_admin(period \\ :all) do
    Log
    |> filter_period(period)
    |> group_by([l], l.game_type)
    |> select([l], {l.game_type, type(sum(l.duration_seconds), :integer)})
    |> order_by([l], desc: sum(l.duration_seconds))
    |> Repo.all()
  end

  @doc "Admin: 전체 누적 (선택 기간) — 한 숫자."
  def total_seconds_admin(period \\ :all) do
    Log
    |> filter_period(period)
    |> select([l], type(coalesce(sum(l.duration_seconds), 0), :integer))
    |> Repo.one()
  end

  # ============================================================================
  # Format helpers (UI용)
  # ============================================================================

  @doc "초 → '1h 23m 45s' 또는 짧을 시 '45s'."
  def format_duration(nil), do: "0s"
  def format_duration(0), do: "0s"

  def format_duration(seconds) when is_integer(seconds) and seconds > 0 do
    h = div(seconds, 3600)
    m = div(rem(seconds, 3600), 60)
    s = rem(seconds, 60)

    cond do
      h > 0 -> "#{h}h #{m}m"
      m > 0 -> "#{m}m #{s}s"
      true -> "#{s}s"
    end
  end

  defp filter_game(query, nil), do: query
  defp filter_game(query, game_type), do: where(query, [l], l.game_type == ^game_type)
end
