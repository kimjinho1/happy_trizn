defmodule HappyTrizn.Trizmon.Battle.DamageTest do
  use ExUnit.Case, async: true

  alias HappyTrizn.Trizmon.Battle.Damage

  describe "type_effectiveness/2" do
    test "1 타입 방어" do
      assert Damage.type_effectiveness(:fire, [:grass]) == 2.0
      assert Damage.type_effectiveness(:fire, [:water]) == 0.5
    end

    test "2 타입 방어 — 곱" do
      assert Damage.type_effectiveness(:fire, [:grass, :ice]) == 4.0
      assert Damage.type_effectiveness(:fire, [:water, :rock]) == 0.25
    end

    test "타입 무효 → 0.0" do
      assert Damage.type_effectiveness(:normal, [:ghost]) == 0.0
      assert Damage.type_effectiveness(:normal, [:ghost, :fire]) == 0.0
    end

    test "방어 빈 list → 1.0" do
      assert Damage.type_effectiveness(:fire, []) == 1.0
    end
  end

  describe "calculate/1 — 기본 데미지" do
    test "STAB + 효과 굉장 → 큰 데미지" do
      # 불 attacker, 풀 defender, 불 기술 (STAB)
      result =
        Damage.calculate(%{
          level: 50,
          power: 60,
          atk: 70,
          def: 60,
          attacker_types: [:fire],
          move_type: :fire,
          defender_types: [:grass],
          random: 1.0
        })

      # ((100/5+2) * 60 * 70/60 / 50 + 2) * 1.5 (STAB) * 2.0 (eff) * 1.0 (no crit)
      # = (22 * 60 * 1.1667 / 50 + 2) * 3.0
      # = (30.8 + 2) * 3.0 = 32.8 * 3 = 98.4 ≈ 98
      assert result.damage > 80 and result.damage < 110
      assert result.type_eff == 2.0
      assert result.stab? == true
    end

    test "타입 무효 → 데미지 0" do
      result =
        Damage.calculate(%{
          level: 50,
          power: 80,
          atk: 100,
          def: 80,
          attacker_types: [:normal],
          move_type: :normal,
          defender_types: [:ghost],
          random: 1.0
        })

      assert result.damage == 0
      assert result.type_eff == 0.0
    end

    test "STAB X (move type ≠ attacker types) → 1.0배" do
      result_stab =
        Damage.calculate(%{
          level: 50,
          power: 40,
          atk: 50,
          def: 50,
          attacker_types: [:fire],
          move_type: :fire,
          defender_types: [:normal],
          random: 1.0
        })

      result_no_stab =
        Damage.calculate(%{
          level: 50,
          power: 40,
          atk: 50,
          def: 50,
          attacker_types: [:water],
          move_type: :fire,
          defender_types: [:normal],
          random: 1.0
        })

      assert result_stab.damage > result_no_stab.damage
      assert result_stab.stab? == true
      assert result_no_stab.stab? == false
    end

    test "Crit → 1.5배" do
      params = %{
        level: 50,
        power: 40,
        atk: 50,
        def: 50,
        attacker_types: [:normal],
        move_type: :normal,
        defender_types: [:normal],
        random: 1.0
      }

      no_crit = Damage.calculate(Map.put(params, :crit?, false))
      crit = Damage.calculate(Map.put(params, :crit?, true))

      assert crit.damage > no_crit.damage
      assert crit.crit? == true
    end

    test "최소 데미지 1 (type_eff > 0 일 때)" do
      result =
        Damage.calculate(%{
          level: 1,
          power: 1,
          atk: 1,
          def: 999,
          attacker_types: [:normal],
          move_type: :normal,
          defender_types: [:normal],
          random: 0.85
        })

      assert result.damage >= 1
    end

    test "burn + physical → 0.5배" do
      params = %{
        level: 50,
        power: 80,
        atk: 100,
        def: 80,
        attacker_types: [:normal],
        move_type: :normal,
        defender_types: [:normal],
        category: :physical,
        random: 1.0
      }

      no_burn = Damage.calculate(Map.put(params, :burn?, false))
      burn = Damage.calculate(Map.put(params, :burn?, true))

      assert burn.damage < no_burn.damage
    end

    test "burn + special → 영향 X" do
      params = %{
        level: 50,
        power: 80,
        atk: 100,
        def: 80,
        attacker_types: [:normal],
        move_type: :normal,
        defender_types: [:normal],
        category: :special,
        random: 1.0
      }

      no_burn = Damage.calculate(Map.put(params, :burn?, false))
      burn = Damage.calculate(Map.put(params, :burn?, true))

      assert burn.damage == no_burn.damage
    end
  end

  describe "effectiveness_label/1" do
    test "0.0 → 효과 없음" do
      assert Damage.effectiveness_label(0.0) == "효과가 없는 듯하다"
    end

    test "0.5 → 효과 별로" do
      assert Damage.effectiveness_label(0.5) == "효과는 별로인 듯하다"
    end

    test "2.0 → 효과 굉장" do
      assert Damage.effectiveness_label(2.0) == "효과는 굉장했다!"
    end

    test "1.0 → 빈 문자열" do
      assert Damage.effectiveness_label(1.0) == ""
    end
  end

  describe "random_ratio/0" do
    test "0.85 ~ 1.0 범위" do
      Enum.each(1..100, fn _ ->
        r = Damage.random_ratio()
        assert r >= 0.85 and r <= 1.0
      end)
    end
  end
end
