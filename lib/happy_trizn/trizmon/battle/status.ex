defmodule HappyTrizn.Trizmon.Battle.Status do
  @moduledoc """
  상태 이상 처리 (Sprint 5c-2a).

  매 턴 종료 시 호출 — burn / poison 데미지 누적, sleep / freeze counter 감소.
  매 행동 시도 시 호출 — paralysis (25% 행동 X), sleep (행동 X 카운터 감소),
  freeze (행동 X, 20% 풀림).

  spec: docs/TRIZMON_SPEC.md §6
  """

  alias HappyTrizn.Trizmon.Battle.Mon

  @doc """
  턴 종료 시 처리. 데미지 + 카운터 갱신 + log msg.

  return: {%Mon{}, [log_msg]}
  """
  def end_of_turn(%Mon{status: nil} = mon), do: {mon, []}

  def end_of_turn(%Mon{status: :burn} = mon) do
    dmg = max(div(mon.max_hp, 16), 1)
    new_mon = Mon.apply_damage(mon, dmg)
    {new_mon, ["#{mon.name} 은(는) 화상 데미지! (#{dmg})"]}
  end

  def end_of_turn(%Mon{status: :poison} = mon) do
    dmg = max(div(mon.max_hp, 8), 1)
    new_mon = Mon.apply_damage(mon, dmg)
    {new_mon, ["#{mon.name} 은(는) 독 데미지! (#{dmg})"]}
  end

  def end_of_turn(%Mon{} = mon), do: {mon, []}

  @doc """
  행동 시도 시 처리. 행동 가능 여부 + log + 갱신된 mon.

  return: {:can_act, %Mon{}, []} | {:cannot_act, %Mon{}, [log_msg]}
  """
  def can_act?(%Mon{status: nil} = mon), do: {:can_act, mon, []}

  def can_act?(%Mon{status: :paralysis} = mon) do
    if :rand.uniform(4) == 1 do
      {:cannot_act, mon, ["#{mon.name} 은(는) 마비되어서 움직일 수 없다!"]}
    else
      {:can_act, mon, []}
    end
  end

  def can_act?(%Mon{status: :sleep, status_turns: t} = mon) when t > 0 do
    new_mon = %{mon | status_turns: t - 1}

    if t - 1 == 0 do
      cleared = Mon.clear_status(new_mon)
      {:can_act, cleared, ["#{mon.name} 이(가) 깼다!"]}
    else
      {:cannot_act, new_mon, ["#{mon.name} 은(는) 잠들어 있다."]}
    end
  end

  def can_act?(%Mon{status: :freeze} = mon) do
    if :rand.uniform(5) == 1 do
      cleared = Mon.clear_status(mon)
      {:can_act, cleared, ["#{mon.name} 의 얼음이 녹았다!"]}
    else
      {:cannot_act, mon, ["#{mon.name} 은(는) 얼어 있다."]}
    end
  end

  def can_act?(%Mon{} = mon), do: {:can_act, mon, []}

  @doc """
  speed mod for status. 마비 시 50% 속도.
  """
  def speed_modifier(%Mon{status: :paralysis}), do: 0.5
  def speed_modifier(_), do: 1.0
end
