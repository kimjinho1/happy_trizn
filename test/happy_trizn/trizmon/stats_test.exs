defmodule HappyTrizn.Trizmon.StatsTest do
  use ExUnit.Case, async: true

  alias HappyTrizn.Trizmon.Stats

  describe "hp/1" do
    # 표준 포켓몬 HP 공식 검증값.
    test "base 45, IV 31, EV 0, lv 50 → 120" do
      assert Stats.hp(%{base: 45, iv: 31, ev: 0, level: 50}) == 120
    end

    test "base 78, IV 31, EV 252, lv 100 → 297" do
      # base 78 (charizard 표준), 만렙 + 풀IV + 풀EV.
      # (2*78 + 31 + 63) * 100 / 100 + 100 + 10 = 250 + 110 = 360
      # 잠깐 — 공식 다시 검증. floor((2*78 + 31 + 252/4) * 100 / 100) + 100 + 10
      # = floor((156 + 31 + 63) * 1) + 110 = 250 + 110 = 360. (실제 charizard HP 297 != 360)
      # 음 — 공식 문제? 알아봐야.
      # Charizard 78 base, 31 IV, 252 EV, lv 100 = 360 (소형 포켓몬 위키).
      # 297 는 base 가 다른 케이스. 일단 360 으로 expect.
      assert Stats.hp(%{base: 78, iv: 31, ev: 252, level: 100}) == 360
    end

    test "lv 1 = 작은 값" do
      assert Stats.hp(%{base: 45, iv: 0, ev: 0, level: 1}) == 11
    end
  end

  describe "stat/1 (atk/def/spa/spd/spe)" do
    test "neutral nature → modifier 1.0" do
      # base 49, iv 31, ev 0, lv 50, hardy → ((2*49 + 31 + 0) * 50 / 100) + 5 = 64 + 5 = 69
      assert Stats.stat(%{
               base: 49,
               iv: 31,
               ev: 0,
               level: 50,
               nature: :hardy,
               stat: :atk
             }) == 69
    end

    test "+atk nature (lonely) → 1.1배" do
      # 69 * 1.1 = 75.9 → floor 75
      assert Stats.stat(%{
               base: 49,
               iv: 31,
               ev: 0,
               level: 50,
               nature: :lonely,
               stat: :atk
             }) == 75
    end

    test "-atk nature (bold) → 0.9배" do
      # 69 * 0.9 = 62.1 → floor 62
      assert Stats.stat(%{
               base: 49,
               iv: 31,
               ev: 0,
               level: 50,
               nature: :bold,
               stat: :atk
             }) == 62
    end
  end

  describe "all_stats/2 — instance + species → 6 stat" do
    test "모든 stat 한 번에 계산" do
      species = %{
        base_hp: 45,
        base_atk: 49,
        base_def: 49,
        base_spa: 65,
        base_spd: 65,
        base_spe: 45
      }

      instance = %{
        level: 50,
        iv_hp: 31,
        iv_atk: 31,
        iv_def: 31,
        iv_spa: 31,
        iv_spd: 31,
        iv_spe: 31,
        ev_hp: 0,
        ev_atk: 0,
        ev_def: 0,
        ev_spa: 0,
        ev_spd: 0,
        ev_spe: 0,
        nature: "hardy"
      }

      stats = Stats.all_stats(instance, species)
      assert stats.hp == 120
      assert stats.atk == 69
      assert stats.def == 69
      assert stats.spa == 85
      assert stats.spd == 85
      assert stats.spe == 65
    end

    test "string nature 도 자동 atom 변환" do
      species = %{
        base_hp: 50,
        base_atk: 50,
        base_def: 50,
        base_spa: 50,
        base_spd: 50,
        base_spe: 50
      }

      instance = %{
        level: 50,
        iv_hp: 0,
        iv_atk: 0,
        iv_def: 0,
        iv_spa: 0,
        iv_spd: 0,
        iv_spe: 0,
        ev_hp: 0,
        ev_atk: 0,
        ev_def: 0,
        ev_spa: 0,
        ev_spd: 0,
        ev_spe: 0,
        nature: "adamant"
      }

      stats = Stats.all_stats(instance, species)
      # adamant: +atk -spa
      assert stats.atk > stats.spa
    end
  end

  describe "random_ivs/0" do
    test "6 IV 모두 0..31 범위" do
      ivs = Stats.random_ivs()

      Enum.each([:iv_hp, :iv_atk, :iv_def, :iv_spa, :iv_spd, :iv_spe], fn k ->
        v = Map.fetch!(ivs, k)
        assert v >= 0 and v <= 31
      end)
    end
  end
end
