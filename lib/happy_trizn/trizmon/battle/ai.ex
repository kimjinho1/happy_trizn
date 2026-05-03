defmodule HappyTrizn.Trizmon.Battle.AI do
  @moduledoc """
  CPU 행동 선택 (Sprint 5c-2a).

  난이도 3 단계:
  - **easy**: 사용 가능한 move 중 random.
  - **normal**: type 효과 우선 + max expected damage. status move = 5% 확률.
  - **hard**: 5c-late — setup move / 교체 / 상태 이상 활용. 현재는 normal 과 동일.

  spec: docs/TRIZMON_SPEC.md §10
  """

  alias HappyTrizn.Trizmon.Battle.{Damage, Mon}

  @doc """
  CPU 행동 선택. attacker (CPU) + defender (player).

  return: {:move, move_idx, move_struct} | {:struggle} (모든 PP 0)
  """
  def choose(attacker, defender, difficulty \\ :easy) do
    available =
      attacker.moves
      |> Enum.with_index()
      |> Enum.reject(fn {m, _idx} -> m.pp <= 0 end)

    if available == [] do
      {:struggle}
    else
      case difficulty do
        :easy -> random_choice(available)
        :normal -> best_damage_choice(available, attacker, defender)
        :hard -> best_damage_choice(available, attacker, defender)
      end
    end
  end

  defp random_choice(available) do
    {move, idx} = Enum.random(available)
    {:move, idx, move}
  end

  defp best_damage_choice(available, attacker, defender) do
    # 각 move 의 expected damage (random 1.0, no crit) 계산 → 최대 선택.
    scored =
      Enum.map(available, fn {move, idx} ->
        score = expected_damage(move, attacker, defender)
        {score, idx, move}
      end)

    {_score, idx, move} = Enum.max_by(scored, fn {s, _, _} -> s end)
    {:move, idx, move}
  end

  defp expected_damage(%{category: :status}, _attacker, _defender), do: 1

  defp expected_damage(move, attacker, defender) do
    if is_nil(move.power) do
      0
    else
      atk_stat = if move.category == :physical, do: attacker.stats.atk, else: attacker.stats.spa
      def_stat = if move.category == :physical, do: defender.stats.def, else: defender.stats.spd

      Damage.calculate(%{
        level: attacker.level,
        power: move.power,
        atk: atk_stat,
        def: def_stat,
        attacker_types: attacker.types,
        move_type: move.type,
        defender_types: defender.types,
        random: 1.0,
        category: move.category,
        crit?: false,
        burn?: attacker.status == :burn
      }).damage
    end
  end
end
