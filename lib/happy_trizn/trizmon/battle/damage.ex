defmodule HappyTrizn.Trizmon.Battle.Damage do
  @moduledoc """
  데미지 계산 (Sprint 5c-1).

  포켓몬 컨벤션 공식:

      damage = floor(
        ((2 * level / 5 + 2) * power * (atk / def) / 50 + 2)
        * stab
        * type_eff
        * crit
        * random
        * burn_mult
      )

  spec: docs/TRIZMON_SPEC.md §7
  """

  alias HappyTrizn.Trizmon.TypeChart

  @doc """
  한 공격의 데미지.

  params:
    %{
      level: 50,
      power: 40,
      atk: 100,
      def: 80,
      attacker_types: [:fire, ...],
      move_type: :fire,
      defender_types: [:grass, ...],
      crit?: false,
      random: 0.85..1.0 (default 1.0 — 테스트용),
      burn?: false (물리 + 화상 시 0.5),
      category: :physical | :special
    }

  return: %{damage: int, type_eff: float, crit?: bool, miss?: false}.

  miss 처리는 호출자 책임 (이 함수는 명중 시 데미지 만 계산).
  """
  def calculate(params) do
    level = params.level
    power = params.power
    atk = params.atk
    defense = params.def
    move_type = params.move_type
    attacker_types = Map.get(params, :attacker_types, [])
    defender_types = Map.get(params, :defender_types, [])
    crit? = Map.get(params, :crit?, false)
    random = Map.get(params, :random, 1.0)
    burn? = Map.get(params, :burn?, false)
    category = Map.get(params, :category, :physical)

    base = (2 * level / 5 + 2) * power * (atk / defense) / 50 + 2

    stab = if move_type in attacker_types, do: 1.5, else: 1.0
    type_eff = type_effectiveness(move_type, defender_types)
    crit_mult = if crit?, do: 1.5, else: 1.0
    burn_mult = if burn? and category == :physical, do: 0.5, else: 1.0

    raw = base * stab * type_eff * crit_mult * random * burn_mult
    damage = max(floor(raw), 1)
    # type_eff = 0 (무효) 일 때만 0 데미지.
    damage = if type_eff == 0.0, do: 0, else: damage

    %{
      damage: damage,
      type_eff: type_eff,
      crit?: crit?,
      stab?: stab > 1.0
    }
  end

  @doc """
  타입 효과 (방어 1~2 타입). 반환: 0.0 / ¼ / ½ / 1 / 2 / 4.
  """
  def type_effectiveness(_move_type, []), do: 1.0

  def type_effectiveness(move_type, [type1]),
    do: TypeChart.multiplier(move_type, type1)

  def type_effectiveness(move_type, [type1, type2]) do
    TypeChart.multiplier(move_type, type1) * TypeChart.multiplier(move_type, type2)
  end

  @doc """
  타입 효과 라벨 (UI 메시지).
  """
  def effectiveness_label(0.0), do: "효과가 없는 듯하다"
  def effectiveness_label(eff) when eff < 1.0, do: "효과는 별로인 듯하다"
  def effectiveness_label(eff) when eff > 1.0, do: "효과는 굉장했다!"
  def effectiveness_label(_), do: ""

  @doc "랜덤 ratio (0.85~1.0) — 실제 배틀에서 사용. 테스트는 명시 1.0."
  def random_ratio do
    # 0.85 ~ 1.0 균등.
    0.85 + :rand.uniform() * 0.15
  end

  @doc "crit 발동? (1/24 default)."
  def crit?(rate \\ 24) do
    :rand.uniform(rate) == 1
  end
end
