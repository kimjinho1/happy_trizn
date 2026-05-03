defmodule HappyTrizn.Repo.Migrations.CreateTrizmonSpecies do
  use Ecto.Migration

  def change do
    # Sprint 5c-1 — Trizmon 종 (정적 데이터, seed 로 채움).
    # spec: docs/TRIZMON_SPEC.md §4
    create table(:trizmon_species) do
      add :slug, :string, null: false, size: 64
      add :name_ko, :string, null: false, size: 32
      add :name_en, :string, size: 32
      add :type1, :string, null: false, size: 16
      add :type2, :string, size: 16

      add :base_hp, :integer, null: false
      add :base_atk, :integer, null: false
      add :base_def, :integer, null: false
      add :base_spa, :integer, null: false
      add :base_spd, :integer, null: false
      add :base_spe, :integer, null: false

      add :catch_rate, :integer, null: false, default: 45
      add :exp_curve, :string, null: false, size: 16, default: "medium_fast"
      add :height_m, :float
      add :weight_kg, :float
      add :pokedex_text, :text

      add :evolves_to_id, references(:trizmon_species, on_delete: :nilify_all)
      add :evolves_at_level, :integer
      add :evolution_method, :string, size: 16

      add :image_url, :string, size: 255

      timestamps(type: :utc_datetime)
    end

    create unique_index(:trizmon_species, [:slug])
    create index(:trizmon_species, [:type1])
  end
end
