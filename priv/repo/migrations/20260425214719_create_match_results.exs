defmodule HappyTrizn.Repo.Migrations.CreateMatchResults do
  use Ecto.Migration

  def change do
    # 라운드 단위 결과 — 멀티 끝나면 한 row, 게임별 stats 는 JSON.
    # 싱글 게임은 winner_id null + room_id null 가능 (개인 기록).
    create table(:match_results, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :game_type, :string, size: 32, null: false
      add :room_id, :binary_id, null: true
      add :winner_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: true
      add :duration_ms, :integer, null: false, default: 0
      add :stats, :json, null: false
      add :finished_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:match_results, [:game_type])
    create index(:match_results, [:winner_id])
    create index(:match_results, [:finished_at])
    create index(:match_results, [:room_id])
  end
end
