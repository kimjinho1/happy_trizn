defmodule HappyTrizn.Repo.Migrations.CreateAdminActions do
  use Ecto.Migration

  def change do
    # 감사 로그. Admin 은 .env 고정 계정 (DB 분리) 이지만 누가 어느 시점에
    # 어떤 액션을 했는지 추적 — 향후 다중 admin 도입 대비.
    create table(:admin_actions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :admin_id, :string, null: false, size: 64
      add :action, :string, null: false, size: 32
      add :target_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :target_room_id, :binary_id
      add :payload, :map
      add :inserted_at, :utc_datetime, null: false
    end

    create index(:admin_actions, [:admin_id])
    create index(:admin_actions, [:action])
    create index(:admin_actions, [:target_user_id])
    create index(:admin_actions, [:inserted_at])
  end
end
