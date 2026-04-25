defmodule HappyTrizn.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false, size: 160
      add :nickname, :string, null: false, size: 32
      add :password_hash, :string, null: false, size: 100
      add :status, :string, null: false, size: 16, default: "active"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])
    create unique_index(:users, [:nickname])
    create index(:users, [:status])
  end
end
