defmodule HappyTrizn.Trizmon.Party do
  @moduledoc """
  사용자 Trizmon 파티 / 보관함 관리 + Starter 자동 생성 (Sprint 5c-2c).

  5c-2c smoke — 사용자 mount 시 starter (불꽃이) 자동 생성. 본격 seed
  migration 으로 species / moves 일괄 삽입은 5c-2d.
  """

  import Ecto.Query

  alias HappyTrizn.Repo
  alias HappyTrizn.Trizmon.{Instance, Move, Species, Stats}

  @starter_species_slug "pyromon-001"
  @starter_move_slug "tackle-001"

  @doc """
  사용자의 in_party_slot 1..6 instance preload (species + 보유 moves).
  return: [%Instance{species: ..., moves_loaded: [...]}, ...] sorted by slot.
  """
  def list_party(user_id) when is_binary(user_id) do
    Instance
    |> where([i], i.user_id == ^user_id and not is_nil(i.in_party_slot))
    |> order_by([i], asc: i.in_party_slot)
    |> preload([:species, :move1, :move2, :move3, :move4])
    |> Repo.all()
  end

  @doc """
  사용자의 첫 starter — 없으면 자동 생성.

  Sprint 5c-2c smoke — 종 / 기술 데이터가 없으면 자동 생성 + starter 생성.
  본격 seed migration 으로 교체될 때까지 self-contained.
  """
  def ensure_starter!(user) do
    case list_party(user.id) do
      [] ->
        species = ensure_species!()
        move = ensure_move!()
        ensure_species_move!(species, move)
        create_starter!(user, species, move)

      [first | _] ->
        first
    end
  end

  defp ensure_species! do
    case Repo.get_by(Species, slug: @starter_species_slug) do
      nil ->
        attrs = %{
          slug: @starter_species_slug,
          name_ko: "불꽃이",
          name_en: "Pyromon",
          type1: "fire",
          base_hp: 39,
          base_atk: 52,
          base_def: 43,
          base_spa: 60,
          base_spd: 50,
          base_spe: 65,
          catch_rate: 45,
          exp_curve: "medium_slow",
          height_m: 0.6,
          weight_kg: 8.5,
          pokedex_text: "꼬리 끝의 작은 불꽃은 감정에 따라 흔들린다. 화나면 활활 타오른다.",
          image_url: "/images/trizmon/pyromon-001.png"
        }

        %Species{} |> Species.changeset(attrs) |> Repo.insert!()

      s ->
        s
    end
  end

  defp ensure_move! do
    case Repo.get_by(Move, slug: @starter_move_slug) do
      nil ->
        attrs = %{
          slug: @starter_move_slug,
          name_ko: "몸통박치기",
          type: "normal",
          category: "physical",
          power: 40,
          accuracy: 100,
          pp: 35,
          priority: 0,
          description: "온몸을 부딪쳐서 상대를 공격한다."
        }

        %Move{} |> Move.changeset(attrs) |> Repo.insert!()

      m ->
        m
    end
  end

  defp ensure_species_move!(species, move) do
    exists =
      Repo.exists?(
        from sm in "trizmon_species_moves",
          where:
            sm.species_id == ^species.id and sm.move_id == ^move.id and
              sm.learn_method == "level"
      )

    unless exists do
      Repo.insert_all("trizmon_species_moves", [
        %{
          species_id: species.id,
          move_id: move.id,
          learn_method: "level",
          learn_level: 1
        }
      ])
    end

    :ok
  end

  defp create_starter!(user, species, move) do
    level = 5
    ivs = Stats.random_ivs()

    # current_hp = stats.hp 계산용 임시 instance.
    temp_instance =
      Map.merge(ivs, %{
        level: level,
        ev_hp: 0,
        ev_atk: 0,
        ev_def: 0,
        ev_spa: 0,
        ev_spd: 0,
        ev_spe: 0,
        nature: "hardy"
      })

    stats = Stats.all_stats(temp_instance, species)

    attrs =
      Map.merge(ivs, %{
        user_id: user.id,
        species_id: species.id,
        nickname: nil,
        level: level,
        exp: 0,
        nature: HappyTrizn.Trizmon.Nature.random() |> Atom.to_string(),
        current_hp: stats.hp,
        status: nil,
        status_turns: 0,
        move1_id: move.id,
        move1_pp: move.pp,
        move2_pp: 0,
        move3_pp: 0,
        move4_pp: 0,
        caught_at: DateTime.utc_now() |> DateTime.truncate(:second),
        caught_location: "초기 마을",
        is_starter: true,
        in_party_slot: 1
      })

    %Instance{}
    |> Instance.changeset(attrs)
    |> Repo.insert!()
    |> Repo.preload([:species, :move1, :move2, :move3, :move4])
  end

  @doc """
  Instance + species + 학습된 move list → BattleMon.
  미사용 move slot 은 nil → reject.
  """
  def to_battle_mon(instance) do
    moves =
      [instance.move1, instance.move2, instance.move3, instance.move4]
      |> Enum.reject(&is_nil/1)

    HappyTrizn.Trizmon.Battle.Mon.from_instance(instance, instance.species, moves)
  end

  @doc """
  랜덤 CPU opponent (Sprint 5c-2d) — 사용자 level 근방의 random species.
  DB instance 저장 X (in-memory). 학습 가능한 기술 중 level 이하 4개 random pick.

  return: %BattleMon{}
  """
  def random_cpu_mon(level) when is_integer(level) do
    species = Repo.all(Species) |> Enum.random()

    # 학습 가능한 기술 (level <= 사용자 level) 중 4개 random.
    import Ecto.Query

    move_ids =
      Repo.all(
        from sm in "trizmon_species_moves",
          where:
            sm.species_id == ^species.id and sm.learn_method == "level" and
              (is_nil(sm.learn_level) or sm.learn_level <= ^level),
          select: sm.move_id
      )

    moves =
      cond do
        move_ids == [] ->
          # 학습 가능 기술 없으면 fallback — 몸통박치기.
          case Repo.get_by(Move, slug: "tackle-001") do
            nil -> []
            m -> [m]
          end

        true ->
          Repo.all(from m in Move, where: m.id in ^move_ids)
          |> Enum.shuffle()
          |> Enum.take(4)
      end

    ivs = Stats.random_ivs()

    cpu_instance =
      Map.merge(ivs, %{
        id: nil,
        nickname: "야생 #{species.name_ko}",
        level: level,
        ev_hp: 0,
        ev_atk: 0,
        ev_def: 0,
        ev_spa: 0,
        ev_spd: 0,
        ev_spe: 0,
        nature: HappyTrizn.Trizmon.Nature.random() |> Atom.to_string(),
        current_hp: nil,
        status: nil,
        status_turns: 0,
        move1_pp: pp_for(moves, 0),
        move2_pp: pp_for(moves, 1),
        move3_pp: pp_for(moves, 2),
        move4_pp: pp_for(moves, 3)
      })

    HappyTrizn.Trizmon.Battle.Mon.from_instance(cpu_instance, species, moves)
  end

  defp pp_for(moves, idx) do
    case Enum.at(moves, idx) do
      nil -> 0
      m -> m.pp
    end
  end
end
