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

  @doc "초기 state."
  def new(mon_a, mon_b) do
    %{
      a: mon_a,
      b: mon_b,
      turn_no: 1,
      pending_a: nil,
      pending_b: nil,
      log: ["#{mon_a.name} vs #{mon_b.name} — 배틀 시작!"],
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

    # 양쪽 KO 체크 — 종료 검사.
    cond do
      state.a.fainted? and state.b.fainted? ->
        # 동시 KO — draw (선공이 이긴 것 으로 정책 — 5c-late 결정)
        %{
          state
          | status: :ended,
            winner: nil,
            log: log ++ ["둘 다 쓰러졌다! 무승부"],
            pending_a: nil,
            pending_b: nil
        }

      state.a.fainted? ->
        %{
          state
          | status: :ended,
            winner: :b,
            log: log ++ ["#{state.a.name} 쓰러졌다! 패배"],
            pending_a: nil,
            pending_b: nil
        }

      state.b.fainted? ->
        %{
          state
          | status: :ended,
            winner: :a,
            log: log ++ ["#{state.b.name} 쓰러졌다! 승리"],
            pending_a: nil,
            pending_b: nil
        }

      true ->
        # 턴 종료 status proc.
        {a, log_a} = Status.end_of_turn(state.a)
        {b, log_b} = Status.end_of_turn(state.b)

        new_state = %{
          state
          | a: a,
            b: b,
            turn_no: state.turn_no + 1,
            pending_a: nil,
            pending_b: nil,
            log: log ++ log_a ++ log_b,
            status: check_end_after_status(a, b)
        }

        new_state =
          case new_state.status do
            :ended ->
              winner =
                cond do
                  a.fainted? and b.fainted? -> nil
                  a.fainted? -> :b
                  b.fainted? -> :a
                  true -> nil
                end

              %{new_state | winner: winner}

            _ ->
              %{new_state | status: :await_actions}
          end

        new_state
    end
  end

  defp check_end_after_status(a, b) do
    if a.fainted? or b.fainted?, do: :ended, else: :await_actions
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
