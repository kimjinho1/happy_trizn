defmodule HappyTrizn.Repo.Migrations.CreateTrizmonSaves do
  use Ecto.Migration

  def change do
    # Sprint 5c-1 — 모험 모드 진행 저장 (사용자당 1 슬롯).
    # spec: docs/TRIZMON_SPEC.md §9
    create table(:trizmon_saves, primary_key: false) do
      add :user_id,
          references(:users, type: :binary_id, on_delete: :delete_all),
          null: false,
          primary_key: true

      add :current_map, :string, null: false, size: 64, default: "starting_town"
      add :player_x, :integer, null: false, default: 0
      add :player_y, :integer, null: false, default: 0
      add :badges, :integer, null: false, default: 0  # bitmask 길드 클리어
      # pokedex_seen / caught 는 별도 정규화 테이블 trizmon_pokedex_entries 로
      # (MySQL array 미지원 + 정규화 더 깨끗 + index 가능).
      add :money, :integer, null: false, default: 1000
      add :last_played_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end
  end
end
