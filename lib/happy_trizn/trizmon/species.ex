defmodule HappyTrizn.Trizmon.Species do
  @moduledoc """
  Trizmon 종 (정적). spec: docs/TRIZMON_SPEC.md §4
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "trizmon_species" do
    field :slug, :string
    field :name_ko, :string
    field :name_en, :string
    field :type1, :string
    field :type2, :string

    field :base_hp, :integer
    field :base_atk, :integer
    field :base_def, :integer
    field :base_spa, :integer
    field :base_spd, :integer
    field :base_spe, :integer

    field :catch_rate, :integer, default: 45
    field :exp_curve, :string, default: "medium_fast"
    field :height_m, :float
    field :weight_kg, :float
    field :pokedex_text, :string

    belongs_to :evolves_to, __MODULE__, foreign_key: :evolves_to_id
    field :evolves_at_level, :integer
    field :evolution_method, :string

    field :image_url, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(species, attrs) do
    species
    |> cast(attrs, [
      :slug,
      :name_ko,
      :name_en,
      :type1,
      :type2,
      :base_hp,
      :base_atk,
      :base_def,
      :base_spa,
      :base_spd,
      :base_spe,
      :catch_rate,
      :exp_curve,
      :height_m,
      :weight_kg,
      :pokedex_text,
      :evolves_to_id,
      :evolves_at_level,
      :evolution_method,
      :image_url
    ])
    |> validate_required([
      :slug,
      :name_ko,
      :type1,
      :base_hp,
      :base_atk,
      :base_def,
      :base_spa,
      :base_spd,
      :base_spe
    ])
    |> validate_number(:base_hp, greater_than: 0, less_than: 256)
    |> validate_number(:catch_rate, greater_than: 0, less_than: 256)
    |> validate_inclusion(:exp_curve, ~w(fast medium_fast medium_slow slow))
    |> maybe_validate_evolution_method()
    |> unique_constraint(:slug)
  end

  defp maybe_validate_evolution_method(cs) do
    case get_change(cs, :evolution_method) do
      nil -> cs
      _ -> validate_inclusion(cs, :evolution_method, ~w(level stone friendship trade))
    end
  end
end
