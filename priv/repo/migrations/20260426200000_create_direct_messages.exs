defmodule HappyTrizn.Repo.Migrations.CreateDirectMessages do
  use Ecto.Migration

  def change do
    create table(:direct_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :from_user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :to_user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :body, :text, null: false
      add :read_at, :utc_datetime, null: true

      timestamps(type: :utc_datetime, updated_at: false)
    end

    # 두 사용자 사이 thread 조회 — from + to 양쪽 모두 인덱스 활용 가능하게.
    create index(:direct_messages, [:from_user_id, :to_user_id, :inserted_at])
    create index(:direct_messages, [:to_user_id, :from_user_id, :inserted_at])
    # unread count.
    create index(:direct_messages, [:to_user_id, :read_at])
  end
end
