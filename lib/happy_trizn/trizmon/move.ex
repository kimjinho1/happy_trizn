defmodule HappyTrizn.Trizmon.Move do
  @moduledoc """
  Trizmon 기술 (정적). spec: docs/TRIZMON_SPEC.md §5
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "trizmon_moves" do
    field :slug, :string
    field :name_ko, :string
    field :type, :string
    field :category, :string  # physical / special / status
    field :power, :integer
    field :accuracy, :integer
    field :pp, :integer, default: 10
    field :priority, :integer, default: 0
    field :effect_code, :string
    field :description, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(move, attrs) do
    move
    |> cast(attrs, [
      :slug,
      :name_ko,
      :type,
      :category,
      :power,
      :accuracy,
      :pp,
      :priority,
      :effect_code,
      :description
    ])
    |> validate_required([:slug, :name_ko, :type, :category, :pp])
    |> validate_inclusion(:category, ~w(physical special status))
    |> validate_number(:pp, greater_than: 0, less_than_or_equal_to: 40)
    |> validate_number(:priority, greater_than_or_equal_to: -7, less_than_or_equal_to: 5)
    |> unique_constraint(:slug)
  end
end
