defmodule HappyTrizn.Trizmon.TypeChart do
  @moduledoc """
  18 타입 상성 (Sprint 5c-1).

  각 타입 = atom (`:fire`, `:water`, ...). 한글 표시 = `display_name/1`.
  `multiplier(attacker, defender)` → 0.0 / 0.5 / 1.0 / 2.0.
  2 타입 방어시 = `multi_multiplier(attacker, type1, type2)` → 곱 (0/¼/½/1/2/4).

  spec: docs/TRIZMON_SPEC.md §2-3
  """

  @types [
    :normal,
    :fire,
    :water,
    :grass,
    :electric,
    :ice,
    :fighting,
    :poison,
    :ground,
    :flying,
    :psychic,
    :bug,
    :rock,
    :ghost,
    :dragon,
    :dark,
    :steel,
    :fairy
  ]

  @display %{
    normal: "일반",
    fire: "불",
    water: "물",
    grass: "풀",
    electric: "전기",
    ice: "얼음",
    fighting: "격투",
    poison: "독",
    ground: "땅",
    flying: "비행",
    psychic: "에스퍼",
    bug: "벌레",
    rock: "바위",
    ghost: "고스트",
    dragon: "드래곤",
    dark: "악",
    steel: "강철",
    fairy: "페어리"
  }

  # 18×18 상성. {attacker, defender} → multiplier. 1.0 (기본) 은 생략.
  # spec §3 표 그대로.
  @chart %{
    # 일반
    {:normal, :rock} => 0.5,
    {:normal, :ghost} => 0.0,
    {:normal, :steel} => 0.5,

    # 불
    {:fire, :fire} => 0.5,
    {:fire, :water} => 0.5,
    {:fire, :grass} => 2.0,
    {:fire, :ice} => 2.0,
    {:fire, :bug} => 2.0,
    {:fire, :rock} => 0.5,
    {:fire, :dragon} => 0.5,
    {:fire, :steel} => 2.0,

    # 물
    {:water, :fire} => 2.0,
    {:water, :water} => 0.5,
    {:water, :grass} => 0.5,
    {:water, :ground} => 2.0,
    {:water, :rock} => 2.0,
    {:water, :dragon} => 0.5,

    # 풀
    {:grass, :fire} => 0.5,
    {:grass, :water} => 2.0,
    {:grass, :grass} => 0.5,
    {:grass, :poison} => 0.5,
    {:grass, :ground} => 2.0,
    {:grass, :flying} => 0.5,
    {:grass, :bug} => 0.5,
    {:grass, :rock} => 2.0,
    {:grass, :dragon} => 0.5,
    {:grass, :steel} => 0.5,

    # 전기
    {:electric, :water} => 2.0,
    {:electric, :grass} => 0.5,
    {:electric, :electric} => 0.5,
    {:electric, :ground} => 0.0,
    {:electric, :flying} => 2.0,
    {:electric, :dragon} => 0.5,

    # 얼음
    {:ice, :fire} => 0.5,
    {:ice, :water} => 0.5,
    {:ice, :grass} => 2.0,
    {:ice, :ice} => 0.5,
    {:ice, :ground} => 2.0,
    {:ice, :flying} => 2.0,
    {:ice, :dragon} => 2.0,
    {:ice, :steel} => 0.5,

    # 격투
    {:fighting, :normal} => 2.0,
    {:fighting, :ice} => 2.0,
    {:fighting, :poison} => 0.5,
    {:fighting, :flying} => 0.5,
    {:fighting, :psychic} => 0.5,
    {:fighting, :bug} => 0.5,
    {:fighting, :rock} => 2.0,
    {:fighting, :ghost} => 0.0,
    {:fighting, :dark} => 2.0,
    {:fighting, :steel} => 2.0,
    {:fighting, :fairy} => 0.5,

    # 독
    {:poison, :grass} => 2.0,
    {:poison, :poison} => 0.5,
    {:poison, :ground} => 0.5,
    {:poison, :rock} => 0.5,
    {:poison, :ghost} => 0.5,
    {:poison, :steel} => 0.0,
    {:poison, :fairy} => 2.0,

    # 땅
    {:ground, :fire} => 2.0,
    {:ground, :grass} => 0.5,
    {:ground, :electric} => 2.0,
    {:ground, :poison} => 2.0,
    {:ground, :flying} => 0.0,
    {:ground, :bug} => 0.5,
    {:ground, :rock} => 2.0,
    {:ground, :steel} => 2.0,

    # 비행
    {:flying, :grass} => 2.0,
    {:flying, :electric} => 0.5,
    {:flying, :fighting} => 2.0,
    {:flying, :bug} => 2.0,
    {:flying, :rock} => 0.5,
    {:flying, :steel} => 0.5,

    # 에스퍼
    {:psychic, :fighting} => 2.0,
    {:psychic, :poison} => 2.0,
    {:psychic, :psychic} => 0.5,
    {:psychic, :dark} => 0.0,
    {:psychic, :steel} => 0.5,

    # 벌레
    {:bug, :fire} => 0.5,
    {:bug, :grass} => 2.0,
    {:bug, :fighting} => 0.5,
    {:bug, :poison} => 0.5,
    {:bug, :flying} => 0.5,
    {:bug, :psychic} => 2.0,
    {:bug, :ghost} => 0.5,
    {:bug, :dark} => 2.0,
    {:bug, :steel} => 0.5,
    {:bug, :fairy} => 0.5,

    # 바위
    {:rock, :fire} => 2.0,
    {:rock, :ice} => 2.0,
    {:rock, :fighting} => 0.5,
    {:rock, :ground} => 0.5,
    {:rock, :flying} => 2.0,
    {:rock, :bug} => 2.0,
    {:rock, :steel} => 0.5,

    # 고스트
    {:ghost, :normal} => 0.0,
    {:ghost, :psychic} => 2.0,
    {:ghost, :ghost} => 2.0,
    {:ghost, :dark} => 0.5,

    # 드래곤
    {:dragon, :dragon} => 2.0,
    {:dragon, :steel} => 0.5,
    {:dragon, :fairy} => 0.0,

    # 악
    {:dark, :fighting} => 0.5,
    {:dark, :psychic} => 2.0,
    {:dark, :ghost} => 2.0,
    {:dark, :dark} => 0.5,
    {:dark, :fairy} => 0.5,

    # 강철
    {:steel, :fire} => 0.5,
    {:steel, :water} => 0.5,
    {:steel, :electric} => 0.5,
    {:steel, :ice} => 2.0,
    {:steel, :rock} => 2.0,
    {:steel, :steel} => 0.5,
    {:steel, :fairy} => 2.0,

    # 페어리
    {:fairy, :fire} => 0.5,
    {:fairy, :fighting} => 2.0,
    {:fairy, :poison} => 0.5,
    {:fairy, :dragon} => 2.0,
    {:fairy, :dark} => 2.0,
    {:fairy, :steel} => 0.5
  }

  @doc "18 타입 atom list."
  def all, do: @types

  @doc "타입 한글 표시."
  def display_name(type) when is_atom(type), do: Map.get(@display, type, "?")
  def display_name(_), do: "?"

  @doc """
  공격 → 방어 단일 타입 multiplier. 0.0 / 0.5 / 1.0 / 2.0.
  """
  def multiplier(attacker, defender) when is_atom(attacker) and is_atom(defender) do
    Map.get(@chart, {attacker, defender}, 1.0)
  end

  @doc """
  방어가 2 타입 일 때 (type1 + type2 가 nil 가능) → mult 곱.
  """
  def multi_multiplier(attacker, type1, type2)
      when is_atom(attacker) and is_atom(type1) do
    base = multiplier(attacker, type1)
    if type2, do: base * multiplier(attacker, type2), else: base
  end

  @doc "string slug → atom (DB row 의 type1/type2 string 변환)."
  def from_slug(slug) when is_binary(slug) do
    case Enum.find(@types, fn t -> Atom.to_string(t) == slug end) do
      nil -> nil
      t -> t
    end
  end

  def from_slug(_), do: nil
end
