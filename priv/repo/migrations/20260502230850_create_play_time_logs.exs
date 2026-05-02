defmodule HappyTrizn.Repo.Migrations.CreatePlayTimeLogs do
  use Ecto.Migration

  def change do
    # Sprint 5b — 실제 게임 플레이 시간 추적.
    #
    # 한 row = 한 "playing 세션" — game.status == :playing 인 시간 구간.
    # waiting / countdown / over / 빈 방 대기 = 카운트 X.
    #
    # user_id nullable — 게스트도 user_id null 로 저장 (admin 통계에만 노출).
    # game_type + duration_seconds 필수.
    # room_id 는 멀티게임만 (싱글은 nil).
    create table(:play_time_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: true
      add :game_type, :string, null: false, size: 32
      add :duration_seconds, :integer, null: false
      add :started_at, :utc_datetime, null: false
      add :ended_at, :utc_datetime, null: false
      add :room_id, :binary_id, null: true

      timestamps(type: :utc_datetime, updated_at: false)
    end

    # 사용자 + 게임별 + 기간 집계 — 가장 자주 쓰는 쿼리 path.
    create index(:play_time_logs, [:user_id, :game_type, :started_at])
    # 게임별 + 기간 집계 (admin 게임 통합).
    create index(:play_time_logs, [:game_type, :started_at])
    # 기간 집계 (admin 전체 합).
    create index(:play_time_logs, [:started_at])
  end
end
