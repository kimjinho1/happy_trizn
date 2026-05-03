defmodule HappyTrizn.Repo.Migrations.CreateTrizmonBattles do
  use Ecto.Migration

  def change do
    # Sprint 5c-1 — Trizmon 배틀 결과 (PvE / PvP). match_results 와 분리.
    # spec: docs/TRIZMON_SPEC.md §15
    create table(:trizmon_battles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :mode, :string, null: false, size: 16  # "pve_random" / "pve_tour" / "pvp"
      add :format, :string, null: false, size: 8  # "3v3" / "6v6" / "1v1_wild"

      add :user_a_id,
          references(:users, type: :binary_id, on_delete: :nilify_all)

      add :user_b_id,
          references(:users, type: :binary_id, on_delete: :nilify_all)
      # PvE 면 user_b_id = nil (CPU)

      add :winner_id, :binary_id  # user_a_id or user_b_id, nil = draw / abort
      add :turns, :integer, null: false, default: 0
      add :duration_seconds, :integer, null: false, default: 0
      add :ended_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:trizmon_battles, [:user_a_id])
    create index(:trizmon_battles, [:user_b_id])
    create index(:trizmon_battles, [:ended_at])
  end
end
