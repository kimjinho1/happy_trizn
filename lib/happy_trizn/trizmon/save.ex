defmodule HappyTrizn.Trizmon.Save do
  @moduledoc """
  사용자 모험 진행 저장 (1 슬롯). spec: docs/TRIZMON_SPEC.md §9
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias HappyTrizn.Accounts.User

  @primary_key {:user_id, :binary_id, []}
  @foreign_key_type :binary_id

  schema "trizmon_saves" do
    field :current_map, :string, default: "starting_town"
    field :player_x, :integer, default: 0
    field :player_y, :integer, default: 0
    field :badges, :integer, default: 0
    field :money, :integer, default: 1000
    field :last_played_at, :utc_datetime

    belongs_to :user, User, define_field: false

    timestamps(type: :utc_datetime)
  end

  def changeset(save, attrs) do
    save
    |> cast(attrs, [
      :user_id,
      :current_map,
      :player_x,
      :player_y,
      :badges,
      :money,
      :last_played_at
    ])
    |> validate_required([:user_id, :current_map, :last_played_at])
    |> validate_number(:badges, greater_than_or_equal_to: 0)
    |> validate_number(:money, greater_than_or_equal_to: 0)
  end
end
