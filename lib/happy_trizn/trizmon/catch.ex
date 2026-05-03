defmodule HappyTrizn.Trizmon.Catch do
  @moduledoc """
  몬스터볼 잡기 시스템 (Sprint 5c-3d).

  포켓몬 컨벤션 catch_rate 공식 (단순 ball, 상태 이상 보정 X):

      a = floor((3 * max_hp - 2 * current_hp) * catch_rate / (3 * max_hp))
      a >= 255  → 100% 잡힘
      else      → a / 255 확률

  성공 시 새 instance 생성 (random IV/nature, level = 야생 mon level).
  pokedex caught 갱신 + 파티 빈 슬롯 자동 할당 (없으면 보관함 in_party_slot nil).

  spec: docs/TRIZMON_SPEC.md §13 (잡기 시스템 5c-3d)
  """

  alias HappyTrizn.Repo
  alias HappyTrizn.Trizmon.{Instance, Move, Nature, Party, Pokedex, Species, Stats}

  @doc """
  잡기 시도. wild_mon = %BattleMon{} (Battle.Mon struct).
  user = %Accounts.User{}.

  return:
    {:caught, %Instance{}, slot}     — 잡기 성공 (slot = 1..6 또는 nil 보관함)
    :missed                           — 잡기 실패
    :already_fainted                  — 야생 mon HP 0 (잡을 수 없음)
  """
  def attempt(user, wild_mon) do
    cond do
      wild_mon.fainted? or wild_mon.current_hp <= 0 ->
        :already_fainted

      true ->
        species = Repo.get!(Species, wild_mon.species_id)
        a = catch_a(wild_mon, species.catch_rate)
        roll = :rand.uniform(255)

        if a >= 255 or roll <= a do
          {instance, slot} = create_instance!(user, species, wild_mon)
          Pokedex.mark_caught!(user.id, species.id)
          {:caught, instance, slot}
        else
          # 본 적은 있음으로 등록.
          Pokedex.mark_seen!(user.id, species.id)
          :missed
        end
    end
  end

  @doc """
  catch_rate 'a' 값 (0..255). 디버깅 / 테스트.
  """
  def catch_a(wild_mon, catch_rate) when is_integer(catch_rate) do
    max_hp = max(wild_mon.max_hp, 1)
    current = max(wild_mon.current_hp, 0)

    floor((3 * max_hp - 2 * current) * catch_rate / (3 * max_hp))
  end

  # 잡힌 야생 mon → DB instance.
  defp create_instance!(user, species, wild_mon) do
    ivs = Stats.random_ivs()

    # current_hp 계산용 임시 — 새 instance 의 stats 로 max_hp 재계산.
    nature_str = Nature.random() |> Atom.to_string()

    temp_instance =
      Map.merge(ivs, %{
        level: wild_mon.level,
        ev_hp: 0,
        ev_atk: 0,
        ev_def: 0,
        ev_spa: 0,
        ev_spd: 0,
        ev_spe: 0,
        nature: nature_str
      })

    stats = Stats.all_stats(temp_instance, species)

    # 잡힌 야생 mon 의 current_hp 비율 보존.
    hp_ratio = if wild_mon.max_hp > 0, do: wild_mon.current_hp / wild_mon.max_hp, else: 1.0
    new_current_hp = max(round(stats.hp * hp_ratio), 1)

    # 학습 가능 기술 중 4개 (level 이하).
    moves = pick_moves(species, wild_mon.level)
    move_attrs = move_attrs_for_instance(moves)

    # 빈 in_party_slot 1..6 찾기.
    slot = next_free_slot(user.id)

    attrs =
      Map.merge(ivs, %{
        user_id: user.id,
        species_id: species.id,
        nickname: nil,
        level: wild_mon.level,
        exp: 0,
        nature: nature_str,
        current_hp: new_current_hp,
        status: nil,
        status_turns: 0,
        caught_at: DateTime.utc_now() |> DateTime.truncate(:second),
        caught_location: "야생",
        is_starter: false,
        in_party_slot: slot
      })
      |> Map.merge(move_attrs)

    instance =
      %Instance{}
      |> Instance.changeset(attrs)
      |> Repo.insert!()

    {instance, slot}
  end

  defp pick_moves(species, level) do
    import Ecto.Query

    move_ids =
      Repo.all(
        from sm in "trizmon_species_moves",
          where:
            sm.species_id == ^species.id and sm.learn_method == "level" and
              (is_nil(sm.learn_level) or sm.learn_level <= ^level),
          select: sm.move_id
      )

    case move_ids do
      [] ->
        case Repo.get_by(Move, slug: "tackle-001") do
          nil -> []
          m -> [m]
        end

      ids ->
        Repo.all(from m in Move, where: m.id in ^ids)
        |> Enum.shuffle()
        |> Enum.take(4)
    end
  end

  defp move_attrs_for_instance(moves) do
    %{
      move1_id: get_in_id(moves, 0),
      move2_id: get_in_id(moves, 1),
      move3_id: get_in_id(moves, 2),
      move4_id: get_in_id(moves, 3),
      move1_pp: get_in_pp(moves, 0),
      move2_pp: get_in_pp(moves, 1),
      move3_pp: get_in_pp(moves, 2),
      move4_pp: get_in_pp(moves, 3)
    }
  end

  defp get_in_id(list, idx) do
    case Enum.at(list, idx) do
      nil -> nil
      m -> m.id
    end
  end

  defp get_in_pp(list, idx) do
    case Enum.at(list, idx) do
      nil -> 0
      m -> m.pp
    end
  end

  defp next_free_slot(user_id) do
    used =
      Party.list_party(user_id)
      |> Enum.map(& &1.in_party_slot)
      |> MapSet.new()

    Enum.find(1..6, fn slot -> not MapSet.member?(used, slot) end)
    # nil = 보관함.
  end
end
