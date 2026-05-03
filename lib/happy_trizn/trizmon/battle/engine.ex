defmodule HappyTrizn.Trizmon.Battle.Engine do
  @moduledoc """
  1v1 배틀 엔진 (Sprint 5c-2a).

  6vs6 team switch 는 5c-2b 에서 wrap. 현재는 핵심 알고리즘 — 양쪽 action submit
  → 우선도 → 실행 → status proc → 한쪽 KO 시 종료.

  state struct:
    %{
      a: %Mon{},
      b: %Mon{},
      turn_no: 1,
      pending_a: nil | action_tuple,
      pending_b: nil | action_tuple,
      log: [string],   # 가장 최신 turn 의 메시지 list
      status: :await_actions | :resolved | :ended,
      winner: nil | :a | :b
    }

  spec: docs/TRIZMON_SPEC.md §7
  """

  alias HappyTrizn.Trizmon.Battle.{AI, Damage, Mon, Status, Turn}

  @doc "1v1 초기 state (single mon vs single mon)."
  def new(mon_a, mon_b) do
    new_team([mon_a], [mon_b], :"1v1")
  end

  @doc """
  Team 배틀 초기 state. team_a/b = [%Mon{}, ...]. format = :"3v3" | :"6v6" | :"1v1".
  active_a/b = 0 (team 의 첫 마리). KO 시 next 자동.
  """
  def new_team(team_a, team_b, format \\ :"6v6")
      when is_list(team_a) and is_list(team_b) and team_a != [] and team_b != [] do
    a = hd(team_a)
    b = hd(team_b)

    %{
      a: a,
      b: b,
      team_a: team_a,
      team_b: team_b,
      active_a: 0,
      active_b: 0,
      format: format,
      turn_no: 1,
      pending_a: nil,
      pending_b: nil,
      log: ["#{a.name} vs #{b.name} — 배틀 시작!"],
      status: :await_actions,
      winner: nil
    }
  end

  @doc """
  player 양쪽 action 제출. 둘 다 채워지면 자동 resolve.
  side: :a | :b. action: {:move, move_idx, move_struct}.
  """
  def submit_action(state, side, action) when side in [:a, :b] do
    new_state =
      case side do
        :a -> %{state | pending_a: action}
        :b -> %{state | pending_b: action}
      end

    if new_state.pending_a && new_state.pending_b do
      resolve_turn(new_state)
    else
      new_state
    end
  end

  @doc """
  CPU side 자동 행동 + resolve 한 턴 (편의 함수).
  player_action = :a 가 player 인 경우. CPU = :b.
  """
  def submit_player_and_resolve(state, player_action, difficulty \\ :easy) do
    cpu_action = AI.choose(state.b, state.a, difficulty)

    state
    |> submit_action(:a, player_action)
    |> submit_action(:b, cpu_action)
  end

  # --- internals ---

  defp resolve_turn(state) do
    order = Turn.order(state.a, state.b, state.pending_a, state.pending_b)

    log = ["턴 #{state.turn_no}"]

    {state, log} =
      Enum.reduce(order, {state, log}, fn side, {st, l} ->
        execute_action(st, side, l)
      end)

    # active mon 의 변경사항을 team 에 flush (현재 active idx 자리 update).
    state = flush_active_to_team(state)

    # 둘 다 행동 후 status end-of-turn 처리 — 살아있는 active 만.
    {state, log} =
      cond do
        state.a.fainted? or state.b.fainted? ->
          {state, log}

        true ->
          {a, log_a} = Status.end_of_turn(state.a)
          {b, log_b} = Status.end_of_turn(state.b)
          new_state = %{state | a: a, b: b}
          new_state = flush_active_to_team(new_state)
          {new_state, log ++ log_a ++ log_b}
      end

    # KO 처리 + 자동 교체 + 종료 검사.
    {state, log} = handle_faints(state, log)

    %{
      state
      | turn_no: state.turn_no + 1,
        pending_a: nil,
        pending_b: nil,
        log: log
    }
  end

  # KO 시: 같은 side 의 next 살아있는 mon 자동 교체. 모두 fainted 면 종료.
  defp handle_faints(state, log) do
    {state, log} = swap_if_fainted(state, :a, log)
    {state, log} = swap_if_fainted(state, :b, log)

    cond do
      team_all_fainted?(state.team_a) and team_all_fainted?(state.team_b) ->
        {%{state | status: :ended, winner: nil}, log ++ ["양쪽 다 전멸! 무승부"]}

      team_all_fainted?(state.team_a) ->
        {%{state | status: :ended, winner: :b}, log ++ ["나의 팀 전멸 — 패배"]}

      team_all_fainted?(state.team_b) ->
        {%{state | status: :ended, winner: :a}, log ++ ["상대 팀 전멸 — 승리!"]}

      true ->
        {%{state | status: :await_actions}, log}
    end
  end

  defp swap_if_fainted(state, side, log) do
    {active, team, idx_key} =
      case side do
        :a -> {state.a, state.team_a, :active_a}
        :b -> {state.b, state.team_b, :active_b}
      end

    if active.fainted? do
      case next_alive_idx(team, Map.get(state, idx_key)) do
        nil ->
          # 그 side 전멸 — 종료 단계에서 처리.
          {state, log ++ ["#{active.name} 쓰러졌다! 더 이상 보낼 트리즈몬이 없다"]}

        new_idx ->
          new_active = Enum.at(team, new_idx)
          state = put_active(state, side, new_active, new_idx)
          {state, log ++ ["#{active.name} 쓰러졌다!", "가라, #{new_active.name}!"]}
      end
    else
      {state, log}
    end
  end

  defp next_alive_idx(team, current_idx) do
    team
    |> Enum.with_index()
    |> Enum.find(fn {mon, idx} -> idx != current_idx and not mon.fainted? end)
    |> case do
      nil -> nil
      {_mon, idx} -> idx
    end
  end

  defp team_all_fainted?(team), do: Enum.all?(team, & &1.fainted?)

  defp put_active(state, :a, mon, idx) do
    new_team = List.replace_at(state.team_a, idx, mon)
    %{state | a: mon, active_a: idx, team_a: new_team}
  end

  defp put_active(state, :b, mon, idx) do
    new_team = List.replace_at(state.team_b, idx, mon)
    %{state | b: mon, active_b: idx, team_b: new_team}
  end

  defp flush_active_to_team(state) do
    %{
      state
      | team_a: List.replace_at(state.team_a, state.active_a, state.a),
        team_b: List.replace_at(state.team_b, state.active_b, state.b)
    }
  end

  # 한 side 행동 실행.
  defp execute_action(state, side, log) do
    {attacker, defender, action} =
      case side do
        :a -> {state.a, state.b, state.pending_a}
        :b -> {state.b, state.a, state.pending_b}
      end

    # 이미 KO 상태 면 skip.
    if attacker.fainted? do
      {state, log}
    else
      # 행동 가능 여부 (status check).
      case Status.can_act?(attacker) do
        {:cannot_act, new_attacker, msgs} ->
          state = put_side(state, side, new_attacker)
          {state, log ++ msgs}

        {:can_act, new_attacker, msgs} ->
          state = put_side(state, side, new_attacker)
          execute_move(state, side, action, defender, log ++ msgs)
      end
    end
  end

  defp execute_move(state, side, {:move, move_idx, _move_meta}, _defender, log) do
    {attacker, defender} = get_pair(state, side)

    case Mon.consume_pp(attacker, move_idx) do
      {:error, :no_pp} ->
        {state, log ++ ["#{attacker.name}: PP 가 없다!"]}

      {:error, :invalid_move} ->
        {state, log ++ ["#{attacker.name}: 잘못된 기술!"]}

      {:ok, attacker, move} ->
        state = put_side(state, side, attacker)

        # 명중 체크.
        if missed?(move) do
          {state, log ++ ["#{attacker.name} 의 #{move.name_ko}! 빗나갔다."]}
        else
          apply_move(state, side, attacker, defender, move, log)
        end
    end
  end

  defp execute_move(state, _side, _action, _defender, log) do
    {state, log ++ ["알 수 없는 행동"]}
  end

  defp apply_move(state, side, attacker, defender, %{category: :status} = move, log) do
    # status move — 5c-late 본격 effect_code dispatcher. 현재는 단순 메시지.
    {state, log ++ ["#{attacker.name} 의 #{move.name_ko}! (효과 미구현)"]}
  end

  defp apply_move(state, side, attacker, defender, move, log) do
    atk_stat = if move.category == :physical, do: attacker.stats.atk, else: attacker.stats.spa
    def_stat = if move.category == :physical, do: defender.stats.def, else: defender.stats.spd

    crit? = Damage.crit?()

    result =
      Damage.calculate(%{
        level: attacker.level,
        power: move.power,
        atk: atk_stat,
        def: def_stat,
        attacker_types: attacker.types,
        move_type: move.type,
        defender_types: defender.types,
        random: Damage.random_ratio(),
        category: move.category,
        crit?: crit?,
        burn?: attacker.status == :burn
      })

    new_defender = Mon.apply_damage(defender, result.damage)
    state = put_other(state, side, new_defender)

    msg = "#{attacker.name} 의 #{move.name_ko}! #{result.damage} 데미지"
    eff_msg = Damage.effectiveness_label(result.type_eff)
    crit_msg = if result.crit?, do: "급소에 맞았다!", else: ""

    extras = [msg, eff_msg, crit_msg] |> Enum.reject(&(&1 == ""))
    {state, log ++ extras}
  end

  defp missed?(%{accuracy: nil}), do: false

  defp missed?(%{accuracy: acc}) when is_integer(acc) do
    :rand.uniform(100) > acc
  end

  defp get_pair(state, :a), do: {state.a, state.b}
  defp get_pair(state, :b), do: {state.b, state.a}

  defp put_side(state, :a, mon), do: %{state | a: mon}
  defp put_side(state, :b, mon), do: %{state | b: mon}

  defp put_other(state, :a, mon), do: %{state | b: mon}
  defp put_other(state, :b, mon), do: %{state | a: mon}
end
