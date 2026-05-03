defmodule HappyTrizn.Repo.Migrations.CreateTrizmonInstances do
  use Ecto.Migration

  def change do
    # Sprint 5c-1 — 사용자가 보유한 Trizmon 한 마리.
    # spec: docs/TRIZMON_SPEC.md §4
    create table(:trizmon_instances, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id,
          references(:users, type: :binary_id, on_delete: :delete_all),
          null: false

      add :species_id, references(:trizmon_species, on_delete: :delete_all), null: false
      add :nickname, :string, size: 32

      add :level, :integer, null: false, default: 5
      add :exp, :integer, null: false, default: 0

      # IV (개체값) 0..31
      add :iv_hp, :integer, null: false, default: 0
      add :iv_atk, :integer, null: false, default: 0
      add :iv_def, :integer, null: false, default: 0
      add :iv_spa, :integer, null: false, default: 0
      add :iv_spd, :integer, null: false, default: 0
      add :iv_spe, :integer, null: false, default: 0

      # EV (노력치) 0..252, sum max 510
      add :ev_hp, :integer, null: false, default: 0
      add :ev_atk, :integer, null: false, default: 0
      add :ev_def, :integer, null: false, default: 0
      add :ev_spa, :integer, null: false, default: 0
      add :ev_spd, :integer, null: false, default: 0
      add :ev_spe, :integer, null: false, default: 0

      add :nature, :string, null: false, size: 16, default: "hardy"

      add :current_hp, :integer, null: false  # 배틀 후 잔여 HP
      add :status, :string, size: 16  # burn / poison / paralysis / freeze / sleep / nil
      add :status_turns, :integer, null: false, default: 0

      # 보유 기술 (최대 4) — nullable, 학습 안 한 슬롯은 nil
      add :move1_id, references(:trizmon_moves, on_delete: :nilify_all)
      add :move2_id, references(:trizmon_moves, on_delete: :nilify_all)
      add :move3_id, references(:trizmon_moves, on_delete: :nilify_all)
      add :move4_id, references(:trizmon_moves, on_delete: :nilify_all)

      add :move1_pp, :integer, null: false, default: 0
      add :move2_pp, :integer, null: false, default: 0
      add :move3_pp, :integer, null: false, default: 0
      add :move4_pp, :integer, null: false, default: 0

      add :caught_at, :utc_datetime, null: false
      add :caught_location, :string, size: 64

      add :is_starter, :boolean, null: false, default: false
      add :in_party_slot, :integer  # nil = 보관함, 1..6 = 파티

      timestamps(type: :utc_datetime)
    end

    create index(:trizmon_instances, [:user_id, :in_party_slot])
    create index(:trizmon_instances, [:user_id, :species_id])
  end
end
