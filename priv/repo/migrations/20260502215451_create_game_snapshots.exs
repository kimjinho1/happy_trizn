defmodule HappyTrizn.Repo.Migrations.CreateGameSnapshots do
  use Ecto.Migration

  def change do
    # 싱글 게임 진행 상태 자동 저장 (Sprint 4k).
    #
    # 게임 모듈의 game_state 를 통째로 :erlang.term_to_binary 로 직렬화 → blob.
    # tuple / atom 도 보존되므로 게임 모듈 callback 추가 없이 작동.
    # state_blob 은 deserialize 시 [:safe] 옵션으로만 사용.
    #
    # schema_version: 게임 모듈 state 구조가 바뀌어도 옛 snapshot 은 무시.
    # 기본 1. 게임 모듈 변경 시 manual bump.
    create table(:game_snapshots, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :game_type, :string, null: false, size: 32
      add :state_blob, :binary, null: false
      add :schema_version, :integer, null: false, default: 1

      timestamps(type: :utc_datetime)
    end

    # 사용자 + 게임당 최대 1개 snapshot.
    create unique_index(:game_snapshots, [:user_id, :game_type])
    create index(:game_snapshots, [:updated_at])
  end
end
