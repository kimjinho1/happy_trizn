defmodule HappyTrizn.Trizmon.Instance do
  @moduledoc """
  사용자 보유 Trizmon 한 마리 (Sprint 5c-1).

  spec: docs/TRIZMON_SPEC.md §4
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias HappyTrizn.Accounts.User
  alias HappyTrizn.Trizmon.{Move, Species}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "trizmon_instances" do
    belongs_to :user, User
    belongs_to :species, Species, type: :id

    field :nickname, :string

    field :level, :integer, default: 5
    field :exp, :integer, default: 0

    field :iv_hp, :integer, default: 0
    field :iv_atk, :integer, default: 0
    field :iv_def, :integer, default: 0
    field :iv_spa, :integer, default: 0
    field :iv_spd, :integer, default: 0
    field :iv_spe, :integer, default: 0

    field :ev_hp, :integer, default: 0
    field :ev_atk, :integer, default: 0
    field :ev_def, :integer, default: 0
    field :ev_spa, :integer, default: 0
    field :ev_spd, :integer, default: 0
    field :ev_spe, :integer, default: 0

    field :nature, :string, default: "hardy"

    field :current_hp, :integer
    field :status, :string
    field :status_turns, :integer, default: 0

    belongs_to :move1, Move, type: :id
    belongs_to :move2, Move, type: :id
    belongs_to :move3, Move, type: :id
    belongs_to :move4, Move, type: :id

    field :move1_pp, :integer, default: 0
    field :move2_pp, :integer, default: 0
    field :move3_pp, :integer, default: 0
    field :move4_pp, :integer, default: 0

    field :caught_at, :utc_datetime
    field :caught_location, :string

    field :is_starter, :boolean, default: false
    field :in_party_slot, :integer

    timestamps(type: :utc_datetime)
  end

  def changeset(instance, attrs) do
    instance
    |> cast(attrs, [
      :user_id,
      :species_id,
      :nickname,
      :level,
      :exp,
      :iv_hp,
      :iv_atk,
      :iv_def,
      :iv_spa,
      :iv_spd,
      :iv_spe,
      :ev_hp,
      :ev_atk,
      :ev_def,
      :ev_spa,
      :ev_spd,
      :ev_spe,
      :nature,
      :current_hp,
      :status,
      :status_turns,
      :move1_id,
      :move2_id,
      :move3_id,
      :move4_id,
      :move1_pp,
      :move2_pp,
      :move3_pp,
      :move4_pp,
      :caught_at,
      :caught_location,
      :is_starter,
      :in_party_slot
    ])
    |> validate_required([:user_id, :species_id, :level, :nature, :current_hp, :caught_at])
    |> validate_number(:level, greater_than_or_equal_to: 1, less_than_or_equal_to: 100)
    |> validate_number(:in_party_slot,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 6,
      message: "must be 1..6"
    )
    |> validate_iv_range()
    |> validate_ev_range()
  end

  defp validate_iv_range(cs) do
    Enum.reduce([:iv_hp, :iv_atk, :iv_def, :iv_spa, :iv_spd, :iv_spe], cs, fn k, acc ->
      validate_number(acc, k, greater_than_or_equal_to: 0, less_than_or_equal_to: 31)
    end)
  end

  defp validate_ev_range(cs) do
    Enum.reduce([:ev_hp, :ev_atk, :ev_def, :ev_spa, :ev_spd, :ev_spe], cs, fn k, acc ->
      validate_number(acc, k, greater_than_or_equal_to: 0, less_than_or_equal_to: 252)
    end)
  end
end
