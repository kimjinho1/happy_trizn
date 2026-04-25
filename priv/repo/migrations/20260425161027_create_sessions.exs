defmodule HappyTrizn.Repo.Migrations.CreateSessions do
  use Ecto.Migration

  def change do
    # 세션 = 게스트(닉네임만, user_id null) + 등록자(user_id 채움) 두 트랙.
    # DB-backed 라 컨테이너 재배포 / 재시작 시에도 로그인 유지.
    create table(:sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: true
      add :nickname, :string, null: false, size: 32
      add :token_hash, :binary, null: false, size: 32
      add :expires_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:sessions, [:token_hash])
    create index(:sessions, [:user_id])
    create index(:sessions, [:expires_at])
  end
end
