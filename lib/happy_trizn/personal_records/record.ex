defmodule HappyTrizn.PersonalRecords.Record do
  @moduledoc """
  사용자별 게임별 누적 최고 기록 schema.

  - `(user_id, game_type)` unique — 한 row 만, 매치 끝날 때 비교 후 갱신.
  - `metadata` 는 게임별 자유 JSON (Tetris: max_pps, max_apm, max_lines_per_min 등).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_game_types ~w(tetris bomberman skribbl snake_io games_2048 minesweeper pacman)

  schema "personal_records" do
    belongs_to :user, HappyTrizn.Accounts.User
    field :game_type, :string
    field :max_score, :integer, default: 0
    field :max_lines, :integer, default: 0
    field :total_wins, :integer, default: 0
    field :metadata, :map, default: %{}
    field :achieved_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :user_id,
      :game_type,
      :max_score,
      :max_lines,
      :total_wins,
      :metadata,
      :achieved_at
    ])
    |> validate_required([:user_id, :game_type, :achieved_at])
    |> validate_inclusion(:game_type, @valid_game_types)
    |> validate_number(:max_score, greater_than_or_equal_to: 0)
    |> validate_number(:max_lines, greater_than_or_equal_to: 0)
    |> validate_number(:total_wins, greater_than_or_equal_to: 0)
    |> unique_constraint([:user_id, :game_type])
  end
end
