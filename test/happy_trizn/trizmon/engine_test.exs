defmodule HappyTrizn.Trizmon.Battle.EngineTest do
  use ExUnit.Case, async: true

  alias HappyTrizn.Trizmon.Battle.{Engine, Mon, Status, Turn}

  # Helper — 가짜 instance / species / move map (DB 안 거침).
  defp mk_species(opts \\ []) do
    %{
      id: opts[:id] || 1,
      name_ko: opts[:name_ko] || "테스트몬",
      type1: opts[:type1] || "normal",
      type2: opts[:type2],
      base_hp: opts[:base_hp] || 50,
      base_atk: opts[:base_atk] || 50,
      base_def: opts[:base_def] || 50,
      base_spa: opts[:base_spa] || 50,
      base_spd: opts[:base_spd] || 50,
      base_spe: opts[:base_spe] || 50
    }
  end

  defp mk_instance(opts \\ []) do
    %{
      id: opts[:id] || Ecto.UUID.generate(),
      nickname: opts[:nickname],
      level: opts[:level] || 50,
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
      nature: "hardy",
      current_hp: opts[:current_hp],
      status: opts[:status],
      status_turns: opts[:status_turns] || 0,
      move1_pp: opts[:move1_pp] || 35,
      move2_pp: opts[:move2_pp] || 0,
      move3_pp: 0,
      move4_pp: 0
    }
  end

  defp mk_move(opts \\ []) do
    %{
      id: opts[:id] || 1,
      slug: opts[:slug] || "tackle",
      name_ko: opts[:name_ko] || "몸통박치기",
      type: opts[:type] || "normal",
      category: opts[:category] || "physical",
      power: opts[:power] || 40,
      accuracy: opts[:accuracy] || 100,
      pp: opts[:pp] || 35,
      priority: opts[:priority] || 0,
      effect_code: opts[:effect_code]
    }
  end

  defp mk_mon(opts \\ []) do
    species = mk_species(opts[:species] || [])
    instance = mk_instance(opts[:instance] || [])
    moves = (opts[:moves] || [mk_move()])
    Mon.from_instance(instance, species, moves)
  end

  describe "Mon.from_instance/3" do
    test "stats 자동 계산" do
      mon = mk_mon()
      assert mon.max_hp == 110
      assert mon.current_hp == 110
      # base 50, IV 0, EV 0, lv 50, hardy → ((2*50 + 0 + 0) * 50/100) + 5 = 55
      assert mon.stats.atk == 55
      assert mon.types == [:normal]
    end

    test "current_hp 명시 시 그 값 보존" do
      mon = mk_mon(instance: [current_hp: 50])
      assert mon.current_hp == 50
      assert mon.max_hp == 110
    end

    test "2 타입 species" do
      mon = mk_mon(species: [type1: "fire", type2: "flying"])
      assert mon.types == [:fire, :flying]
    end
  end

  describe "Mon.apply_damage/2 + heal/2" do
    test "데미지 적용 + KO" do
      mon = mk_mon()
      mon = Mon.apply_damage(mon, 30)
      assert mon.current_hp == mon.max_hp - 30
      refute mon.fainted?

      mon = Mon.apply_damage(mon, 1000)
      assert mon.current_hp == 0
      assert mon.fainted?
    end

    test "회복 = max 까지" do
      mon = mk_mon() |> Mon.apply_damage(50)
      mon = Mon.heal(mon, 9999)
      assert mon.current_hp == mon.max_hp
    end
  end

  describe "Mon.consume_pp/2" do
    test "정상 차감" do
      mon = mk_mon()
      {:ok, new_mon, move} = Mon.consume_pp(mon, 0)
      assert hd(new_mon.moves).pp == 34
      assert move.name_ko == "몸통박치기"
    end

    test "PP 0 → :no_pp" do
      mon = mk_mon(instance: [move1_pp: 0])
      assert {:error, :no_pp} = Mon.consume_pp(mon, 0)
    end
  end

  describe "Status.end_of_turn/1" do
    test "burn — 1/16 dmg" do
      mon = mk_mon() |> Mon.apply_status(:burn)
      {new_mon, log} = Status.end_of_turn(mon)
      expected_dmg = max(div(mon.max_hp, 16), 1)
      assert new_mon.current_hp == mon.current_hp - expected_dmg
      assert log != []
    end

    test "poison — 1/8 dmg" do
      mon = mk_mon() |> Mon.apply_status(:poison)
      {new_mon, _log} = Status.end_of_turn(mon)
      expected_dmg = max(div(mon.max_hp, 8), 1)
      assert new_mon.current_hp == mon.current_hp - expected_dmg
    end

    test "no status → 변화 X" do
      mon = mk_mon()
      {new_mon, log} = Status.end_of_turn(mon)
      assert new_mon == mon
      assert log == []
    end
  end

  describe "Turn.order/4" do
    test "speed 빠른 쪽 먼저" do
      a = mk_mon(species: [base_spe: 100])
      b = mk_mon(species: [base_spe: 50])
      action = {:move, 0, %{priority: 0}}

      assert Turn.order(a, b, action, action) == [:a, :b]
    end

    test "priority 높은 쪽 먼저 (speed 무시)" do
      a = mk_mon(species: [base_spe: 50])
      b = mk_mon(species: [base_spe: 100])
      action_a = {:move, 0, %{priority: 1}}
      action_b = {:move, 0, %{priority: 0}}

      assert Turn.order(a, b, action_a, action_b) == [:a, :b]
    end

    test "마비 시 speed 절반" do
      a = mk_mon(species: [base_spe: 100], instance: [status: "paralysis"])
      b = mk_mon(species: [base_spe: 60])
      action = {:move, 0, %{priority: 0}}

      # a effective = 100 * 0.5 = 50, b = 60 → b 먼저
      assert Turn.order(a, b, action, action) == [:b, :a]
    end
  end

  describe "Engine.new/2 + submit_action/3 (1v1)" do
    test "초기 state — await_actions" do
      a = mk_mon(species: [name_ko: "A"])
      b = mk_mon(species: [name_ko: "B"])
      state = Engine.new(a, b)

      assert state.turn_no == 1
      assert state.status == :await_actions
      assert state.winner == nil
      assert hd(state.log) =~ "배틀 시작"
    end

    test "한쪽만 submit → 여전히 await" do
      state = Engine.new(mk_mon(), mk_mon())
      state = Engine.submit_action(state, :a, {:move, 0, %{priority: 0}})

      assert state.status == :await_actions
      assert state.pending_a != nil
    end

    test "둘 다 submit → resolve, turn 증가" do
      a = mk_mon(species: [name_ko: "Ace", base_spe: 100])
      b = mk_mon(species: [name_ko: "Beta", base_spe: 50])
      state = Engine.new(a, b)

      action = {:move, 0, %{priority: 0}}

      state =
        state
        |> Engine.submit_action(:a, action)
        |> Engine.submit_action(:b, action)

      assert state.status == :await_actions
      assert state.turn_no == 2
      assert state.pending_a == nil
      assert state.pending_b == nil
      # 둘 다 dmg 받았어야 (서로 공격)
      assert state.a.current_hp < state.a.max_hp
      assert state.b.current_hp < state.b.max_hp
    end
  end

  describe "Engine — KO + 종료" do
    test "한쪽 HP 1 + 강한 공격 → KO + ended" do
      # b 가 HP 1 인 상태
      a = mk_mon(species: [name_ko: "A", base_atk: 200])
      b = mk_mon(species: [name_ko: "B"], instance: [current_hp: 1])
      state = Engine.new(a, b)

      action = {:move, 0, %{priority: 0}}

      state =
        state
        |> Engine.submit_action(:a, action)
        |> Engine.submit_action(:b, action)

      assert state.status == :ended
      assert state.winner == :a
      assert state.b.fainted?
    end
  end

  describe "Engine.submit_player_and_resolve/3 — CPU AI 자동" do
    test "CPU 가 random move 선택" do
      a = mk_mon(species: [name_ko: "Player"])
      b = mk_mon(species: [name_ko: "Enemy"])
      state = Engine.new(a, b)

      state =
        Engine.submit_player_and_resolve(
          state,
          {:move, 0, %{priority: 0}},
          :easy
        )

      assert state.turn_no == 2
    end
  end
end
