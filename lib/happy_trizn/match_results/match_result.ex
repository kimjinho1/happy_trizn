defmodule HappyTrizn.MatchResults.MatchResult do
  @moduledoc """
  매치(라운드) 결과 schema.

  - 멀티: room_id + winner_id (null 가능 = 무승부 / 양쪽 떠남)
  - 싱글: room_id null + winner_id null
  - stats: 게임별 자유 JSON (Tetris: per-player score/lines/pps/apm/...)
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "match_results" do
    field :game_type, :string
    field :room_id, :binary_id
    field :winner_id, :binary_id
    field :duration_ms, :integer, default: 0
    field :stats, :map, default: %{}
    field :finished_at, :utc_datetime

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(result, attrs) do
    result
    |> cast(attrs, [:game_type, :room_id, :winner_id, :duration_ms, :stats, :finished_at])
    |> validate_required([:game_type, :duration_ms, :stats, :finished_at])
    |> validate_length(:game_type, max: 32)
    |> validate_number(:duration_ms, greater_than_or_equal_to: 0)
  end
end
