defmodule HappyTrizn.Repo.Migrations.CreateTrizmonSpeciesMoves do
  use Ecto.Migration

  def change do
    # Sprint 5c-1 — 종이 학습 가능한 기술 정의.
    # spec: docs/TRIZMON_SPEC.md §5
    create table(:trizmon_species_moves, primary_key: false) do
      add :species_id,
          references(:trizmon_species, on_delete: :delete_all),
          null: false,
          primary_key: true

      add :move_id,
          references(:trizmon_moves, on_delete: :delete_all),
          null: false,
          primary_key: true

      add :learn_method, :string, null: false, size: 16, primary_key: true
      # "level" / "tm" / "egg" / "tutor"

      add :learn_level, :integer  # nil = TM/HM/egg
    end

    create index(:trizmon_species_moves, [:species_id])
    create index(:trizmon_species_moves, [:move_id])
  end
end
