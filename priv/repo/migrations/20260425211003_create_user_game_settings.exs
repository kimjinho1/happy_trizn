defmodule HappyTrizn.Repo.Migrations.CreateUserGameSettings do
  use Ecto.Migration

  def change do
    # 사용자별 게임 옵션 (key bindings + options) — 1 row per (user, game_type).
    # 게스트는 localStorage (DB 미저장).
    create table(:user_game_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :game_type, :string, size: 32, null: false
      add :key_bindings, :json, null: false
      add :options, :json, null: false

      timestamps(type: :utc_datetime, inserted_at: false)
    end

    create unique_index(:user_game_settings, [:user_id, :game_type])
    create index(:user_game_settings, [:game_type])
  end
end
