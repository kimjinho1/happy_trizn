defmodule HappyTrizn.Repo.Migrations.CreateRooms do
  use Ecto.Migration

  def change do
    create table(:rooms, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :game_type, :string, null: false, size: 32
      add :name, :string, null: false, size: 64
      add :password_salt, :binary, null: true, size: 16
      add :password_hash, :binary, null: true, size: 32
      add :host_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :max_players, :integer, null: false, default: 4
      add :status, :string, null: false, size: 16, default: "open"

      timestamps(type: :utc_datetime)
    end

    create index(:rooms, [:game_type])
    create index(:rooms, [:host_id])
    create index(:rooms, [:status])
    create index(:rooms, [:inserted_at])
  end
end
