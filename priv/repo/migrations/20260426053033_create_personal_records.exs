defmodule HappyTrizn.Repo.Migrations.CreatePersonalRecords do
  use Ecto.Migration

  def change do
    # 사용자 별 게임 별 누적 최고 기록.
    # Tetris: max_score / max_lines / max_pps / max_apm 등.
    # 게임마다 metric 다양 → metadata JSON 으로 자유 확장.
    create table(:personal_records, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :game_type, :string, size: 32, null: false
      add :max_score, :integer, default: 0
      add :max_lines, :integer, default: 0
      add :total_wins, :integer, default: 0
      add :metadata, :json
      add :achieved_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:personal_records, [:user_id, :game_type])
    create index(:personal_records, [:game_type])
  end
end
