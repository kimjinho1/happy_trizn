defmodule HappyTrizn.Repo.Migrations.CreateTrizmonPokedexEntries do
  use Ecto.Migration

  def change do
    # Sprint 5c-1 — 사용자 도감 entry. saves 의 pokedex_seen/caught 정규화.
    # MySQL :array 미지원 회피 + index 가능 + 첫 만난/잡은 시점 추적.
    # spec: docs/TRIZMON_SPEC.md §12
    create table(:trizmon_pokedex_entries, primary_key: false) do
      add :user_id,
          references(:users, type: :binary_id, on_delete: :delete_all),
          null: false,
          primary_key: true

      add :species_id,
          references(:trizmon_species, on_delete: :delete_all),
          null: false,
          primary_key: true

      add :status, :string, null: false, size: 8  # "seen" / "caught"
      add :first_seen_at, :utc_datetime, null: false
      add :first_caught_at, :utc_datetime
    end

    create index(:trizmon_pokedex_entries, [:user_id, :status])
  end
end
