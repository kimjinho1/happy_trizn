defmodule HappyTrizn.Trizmon.Battle.Mon do
  @moduledoc """
  배틀 한 마리의 in-memory 상태 (Sprint 5c-2a).

  DB instance + species + 계산된 stats + 배틀 중 mutation (current_hp / status /
  status_turns / move pp / boost levels). 배틀 종료 후 DB 의 instance 에 일부
  flush (current_hp / status / pp 등).

  spec: docs/TRIZMON_SPEC.md §6, §7
  """

  alias HappyTrizn.Trizmon.{Stats, TypeChart}

  @enforce_keys [:species_id, :name, :level, :stats, :max_hp, :current_hp, :types, :moves]
  defstruct species_id: nil,
            instance_id: nil,
            name: "?",
            level: 5,
            types: [],
            stats: %{},
            max_hp: 0,
            current_hp: 0,
            status: nil,
            status_turns: 0,
            # 일시 능력치 보정 단계 -6..+6 (배틀 중만, KO 시 reset)
            boost_atk: 0,
            boost_def: 0,
            boost_spa: 0,
            boost_spd: 0,
            boost_spe: 0,
            boost_acc: 0,
            boost_eva: 0,
            # moves: [%{id, slug, name_ko, type, category, power, accuracy, pp, max_pp, priority, effect_code}]
            moves: [],
            # 배틀 종료 신호
            fainted?: false

  @doc """
  DB instance + species + 보유 moves (struct list) → BattleMon.
  """
  def from_instance(instance, species, moves) when is_list(moves) do
    stats = Stats.all_stats(instance, species)
    types = parse_types(species)

    move_structs =
      moves
      |> Enum.with_index()
      |> Enum.map(fn {m, idx} ->
        pp_field = String.to_existing_atom("move#{idx + 1}_pp")
        current_pp = Map.get(instance, pp_field, m.pp)

        %{
          id: m.id,
          slug: m.slug,
          name_ko: m.name_ko,
          type: TypeChart.from_slug(m.type) || :normal,
          category: parse_category(m.category),
          power: m.power,
          accuracy: m.accuracy,
          pp: current_pp,
          max_pp: m.pp,
          priority: m.priority,
          effect_code: m.effect_code
        }
      end)

    %__MODULE__{
      species_id: species.id,
      instance_id: Map.get(instance, :id),
      name: instance.nickname || species.name_ko,
      level: instance.level,
      types: types,
      stats: stats,
      max_hp: stats.hp,
      current_hp: instance.current_hp || stats.hp,
      status: parse_status(instance.status),
      status_turns: instance.status_turns || 0,
      moves: move_structs,
      fainted?: (instance.current_hp || stats.hp) <= 0
    }
  end

  @doc """
  HP 적용 (음수 dmg 받기). KO 시 fainted? = true.
  """
  def apply_damage(%__MODULE__{} = mon, damage) when is_integer(damage) and damage >= 0 do
    new_hp = max(mon.current_hp - damage, 0)
    %{mon | current_hp: new_hp, fainted?: new_hp <= 0}
  end

  @doc """
  HP 회복 (max 까지).
  """
  def heal(%__MODULE__{} = mon, amount) when is_integer(amount) and amount >= 0 do
    new_hp = min(mon.current_hp + amount, mon.max_hp)
    %{mon | current_hp: new_hp, fainted?: new_hp <= 0}
  end

  @doc "status 부여 — 이미 status 있으면 X (단일 status 정책)."
  def apply_status(%__MODULE__{status: nil} = mon, status, turns \\ 0)
      when status in [:burn, :poison, :paralysis, :sleep, :freeze] do
    %{mon | status: status, status_turns: turns}
  end

  def apply_status(mon, _, _), do: mon

  def clear_status(%__MODULE__{} = mon) do
    %{mon | status: nil, status_turns: 0}
  end

  @doc """
  move 사용 — pp 1 차감. pp 0 이면 :no_pp 반환.
  """
  def consume_pp(%__MODULE__{moves: moves} = mon, move_idx) when is_integer(move_idx) do
    case Enum.at(moves, move_idx) do
      nil ->
        {:error, :invalid_move}

      %{pp: 0} ->
        {:error, :no_pp}

      move ->
        new_move = %{move | pp: move.pp - 1}
        new_moves = List.replace_at(moves, move_idx, new_move)
        {:ok, %{mon | moves: new_moves}, move}
    end
  end

  defp parse_types(species) do
    [species.type1, species.type2]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&TypeChart.from_slug/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_category("physical"), do: :physical
  defp parse_category("special"), do: :special
  defp parse_category("status"), do: :status
  defp parse_category(_), do: :physical

  defp parse_status(nil), do: nil
  defp parse_status(""), do: nil

  defp parse_status(s) when is_binary(s) do
    case s do
      "burn" -> :burn
      "poison" -> :poison
      "paralysis" -> :paralysis
      "sleep" -> :sleep
      "freeze" -> :freeze
      _ -> nil
    end
  end

  defp parse_status(s) when is_atom(s), do: s
end
