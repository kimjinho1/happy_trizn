defmodule HappyTrizn.Repo.Migrations.CreateTrizmonMoves do
  use Ecto.Migration

  def change do
    # Sprint 5c-1 — Trizmon 기술 (정적 데이터, seed 로 채움).
    # spec: docs/TRIZMON_SPEC.md §5
    create table(:trizmon_moves) do
      add :slug, :string, null: false, size: 64
      add :name_ko, :string, null: false, size: 32
      add :type, :string, null: false, size: 16
      add :category, :string, null: false, size: 16  # physical / special / status
      add :power, :integer  # 변화기는 nil
      add :accuracy, :integer  # nil = 100%
      add :pp, :integer, null: false, default: 10
      add :priority, :integer, null: false, default: 0
      add :effect_code, :string, size: 32  # "burn_10" "para_30" "stat_atk_user_+1" 등
      add :description, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:trizmon_moves, [:slug])
    create index(:trizmon_moves, [:type])
  end
end
