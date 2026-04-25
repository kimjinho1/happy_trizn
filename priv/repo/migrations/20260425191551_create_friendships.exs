defmodule HappyTrizn.Repo.Migrations.CreateFriendships do
  use Ecto.Migration

  def change do
    # 양방향 친구. 한 row 로 표현 — user_a_id < user_b_id (canonical 정렬)
    # 으로 (a,b) vs (b,a) 중복 row 회피. requested_by 가 보낸 사람.
    create table(:friendships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_a_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :user_b_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :status, :string, null: false, size: 16, default: "pending"
      add :requested_by, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:friendships, [:user_a_id, :user_b_id])
    create index(:friendships, [:user_b_id])
    create index(:friendships, [:status])
  end
end
