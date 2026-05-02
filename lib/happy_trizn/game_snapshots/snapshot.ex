defmodule HappyTrizn.GameSnapshots.Snapshot do
  @moduledoc """
  싱글 게임 진행 자동 저장 (Sprint 4k).

  state_blob = :erlang.term_to_binary(game_state). schema_version 은 게임 모듈
  state 구조 변경 시 bump → 옛 snapshot 자동 폐기.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias HappyTrizn.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "game_snapshots" do
    field :game_type, :string
    field :state_blob, :binary
    field :schema_version, :integer, default: 1

    belongs_to :user, User, foreign_key: :user_id

    timestamps(type: :utc_datetime)
  end

  def changeset(snap, attrs) do
    snap
    |> cast(attrs, [:user_id, :game_type, :state_blob, :schema_version, :inserted_at, :updated_at])
    |> validate_required([:user_id, :game_type, :state_blob])
    |> validate_length(:game_type, min: 1, max: 32)
    |> unique_constraint([:user_id, :game_type])
  end
end
