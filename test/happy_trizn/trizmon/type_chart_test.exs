defmodule HappyTrizn.Trizmon.TypeChartTest do
  use ExUnit.Case, async: true

  alias HappyTrizn.Trizmon.TypeChart

  describe "all/0 + display_name/1" do
    test "18 타입" do
      assert length(TypeChart.all()) == 18
    end

    test "한글 표시" do
      assert TypeChart.display_name(:fire) == "불"
      assert TypeChart.display_name(:water) == "물"
      assert TypeChart.display_name(:fairy) == "페어리"
      assert TypeChart.display_name(:unknown) == "?"
    end
  end

  describe "multiplier/2" do
    test "기본 (관계 없음) = 1.0" do
      assert TypeChart.multiplier(:normal, :normal) == 1.0
      assert TypeChart.multiplier(:fire, :electric) == 1.0
    end

    test "효과 굉장 (2.0)" do
      assert TypeChart.multiplier(:fire, :grass) == 2.0
      assert TypeChart.multiplier(:water, :fire) == 2.0
      assert TypeChart.multiplier(:electric, :water) == 2.0
      assert TypeChart.multiplier(:grass, :water) == 2.0
    end

    test "효과 별로 (0.5)" do
      assert TypeChart.multiplier(:fire, :water) == 0.5
      assert TypeChart.multiplier(:water, :grass) == 0.5
      assert TypeChart.multiplier(:grass, :fire) == 0.5
    end

    test "효과 없음 (0.0)" do
      assert TypeChart.multiplier(:normal, :ghost) == 0.0
      assert TypeChart.multiplier(:ghost, :normal) == 0.0
      assert TypeChart.multiplier(:electric, :ground) == 0.0
      assert TypeChart.multiplier(:psychic, :dark) == 0.0
      assert TypeChart.multiplier(:dragon, :fairy) == 0.0
    end
  end

  describe "multi_multiplier/3 (방어 2 타입)" do
    test "둘 다 약점 → 4.0" do
      # 불 → 풀+벌레 = 2 × 2 = 4
      assert TypeChart.multi_multiplier(:fire, :grass, :bug) == 4.0
    end

    test "한쪽 약점 + 한쪽 저항 → 1.0" do
      # 불 → 풀(2) + 물(0.5) = 1
      assert TypeChart.multi_multiplier(:fire, :grass, :water) == 1.0
    end

    test "둘 다 저항 → 0.25" do
      # 불 → 물(0.5) + 바위(0.5) = 0.25
      assert TypeChart.multi_multiplier(:fire, :water, :rock) == 0.25
    end

    test "한쪽 무효 → 0.0" do
      # 일반 → 고스트(0) + 무엇이든 = 0
      assert TypeChart.multi_multiplier(:normal, :ghost, :flying) == 0.0
    end

    test "type2 = nil → 단일 타입과 동일" do
      assert TypeChart.multi_multiplier(:fire, :grass, nil) == 2.0
    end
  end

  describe "from_slug/1" do
    test "string → atom" do
      assert TypeChart.from_slug("fire") == :fire
      assert TypeChart.from_slug("fairy") == :fairy
      assert TypeChart.from_slug("nonexistent") == nil
      assert TypeChart.from_slug(nil) == nil
    end
  end
end
