defmodule HappyTrizn.Trizmon.Seed do
  @moduledoc """
  Trizmon 종 / 기술 / 학습 표 idempotent seed (Sprint 5c-2d).

  Application boot 시 자동 run (prod env). test env disable.
  Admin 수동 trigger 도 가능 (`HappyTrizn.Trizmon.Seed.run!()`).

  25 종 + 30 기술 + 학습 표. 18 타입 모두 cover. starter 3종 (불/물/풀) + 각 진화.
  진화 트리는 species insert 후 evolves_to_id update.

  spec: docs/TRIZMON_SPEC.md §15
  """

  require Logger

  alias HappyTrizn.Repo
  alias HappyTrizn.Trizmon.{Move, Species}

  # ============================================================================
  # 25 종 (slug, attrs)
  # ============================================================================
  # 진화 트리: 자기 다음 단계 evolves_to_slug + evolves_at_level. nil = 최종 단계.
  #
  # base stats 합 ≈ 200 (1단), 320 (2단), 450 (3단) 정도 — 포켓몬 컨벤션.

  @species [
    # === Fire 진화 트리 (3단) ===
    %{slug: "pyromon-001", name_ko: "불꽃이", type1: "fire", base: {39, 52, 43, 60, 50, 65},
      evolves_to: "pyromon-002", evolves_at: 16, exp_curve: "medium_slow",
      pokedex: "꼬리 끝 불꽃이 감정에 따라 흔들린다."},
    %{slug: "pyromon-002", name_ko: "타오르", type1: "fire", base: {58, 64, 58, 80, 65, 80},
      evolves_to: "pyromon-003", evolves_at: 36, exp_curve: "medium_slow",
      pokedex: "꼬리 불꽃이 활활 타오른다."},
    %{slug: "pyromon-003", name_ko: "화룡", type1: "fire", type2: "flying",
      base: {78, 84, 78, 109, 85, 100}, exp_curve: "medium_slow",
      pokedex: "강력한 화염을 뿜는다."},

    # === Water 진화 트리 (3단) ===
    %{slug: "aquamon-001", name_ko: "물방울", type1: "water", base: {44, 48, 65, 50, 64, 43},
      evolves_to: "aquamon-002", evolves_at: 16, exp_curve: "medium_slow",
      pokedex: "등 껍질이 단단하다."},
    %{slug: "aquamon-002", name_ko: "슈슈", type1: "water", base: {59, 63, 80, 65, 80, 58},
      evolves_to: "aquamon-003", evolves_at: 36, exp_curve: "medium_slow",
      pokedex: "꼬리로 물줄기를 쏜다."},
    %{slug: "aquamon-003", name_ko: "거북왕자", type1: "water",
      base: {79, 83, 100, 85, 105, 78}, exp_curve: "medium_slow",
      pokedex: "강력한 물대포를 발사한다."},

    # === Grass 진화 트리 (3단) ===
    %{slug: "leafmon-001", name_ko: "새싹이", type1: "grass", type2: "poison",
      base: {45, 49, 49, 65, 65, 45}, evolves_to: "leafmon-002", evolves_at: 16,
      exp_curve: "medium_slow", pokedex: "등에 씨앗을 짊어진 채 태어난다."},
    %{slug: "leafmon-002", name_ko: "잎새", type1: "grass", type2: "poison",
      base: {60, 62, 63, 80, 80, 60}, evolves_to: "leafmon-003", evolves_at: 32,
      exp_curve: "medium_slow", pokedex: "등의 봉오리가 점점 부풀어 오른다."},
    %{slug: "leafmon-003", name_ko: "숲지기", type1: "grass", type2: "poison",
      base: {80, 82, 83, 100, 100, 80}, exp_curve: "medium_slow",
      pokedex: "등의 큰 꽃이 향기를 뿜는다."},

    # === Electric (2단) ===
    %{slug: "voltmon-001", name_ko: "찌릿", type1: "electric",
      base: {35, 55, 40, 50, 50, 90}, evolves_to: "voltmon-002", evolves_at: 22,
      exp_curve: "medium_fast", pokedex: "양 볼에 전기를 저장한다."},
    %{slug: "voltmon-002", name_ko: "천둥", type1: "electric",
      base: {60, 90, 55, 90, 80, 110}, exp_curve: "medium_fast",
      pokedex: "강력한 전류를 방출한다."},

    # === Ice (2단) ===
    %{slug: "frostmon-001", name_ko: "빙결", type1: "ice",
      base: {50, 50, 50, 65, 35, 35}, evolves_to: "frostmon-002", evolves_at: 30,
      exp_curve: "medium_fast", pokedex: "주변 공기를 차갑게 만든다."},
    %{slug: "frostmon-002", name_ko: "얼음잠", type1: "ice", type2: "psychic",
      base: {95, 50, 95, 95, 95, 65}, exp_curve: "medium_fast",
      pokedex: "차가운 입김으로 적을 얼린다."},

    # === Fighting (2단) ===
    %{slug: "fistmon-001", name_ko: "격투꾼", type1: "fighting",
      base: {50, 80, 50, 25, 25, 35}, evolves_to: "fistmon-002", evolves_at: 28,
      exp_curve: "medium_slow", pokedex: "강력한 주먹을 가졌다."},
    %{slug: "fistmon-002", name_ko: "무술왕", type1: "fighting",
      base: {88, 130, 80, 65, 85, 75}, exp_curve: "medium_slow",
      pokedex: "오랜 수련으로 무술을 익혔다."},

    # === Ground (단일) ===
    %{slug: "earthmon-001", name_ko: "흙거인", type1: "ground", type2: "rock",
      base: {80, 110, 130, 55, 65, 45}, exp_curve: "medium_slow",
      pokedex: "단단한 바위 같은 몸을 가졌다."},

    # === Flying (2단) ===
    %{slug: "windmon-001", name_ko: "비행이", type1: "normal", type2: "flying",
      base: {40, 45, 40, 35, 35, 56}, evolves_to: "windmon-002", evolves_at: 18,
      exp_curve: "medium_slow", pokedex: "작은 새의 모습을 한 트리즈몬."},
    %{slug: "windmon-002", name_ko: "회오리", type1: "normal", type2: "flying",
      base: {83, 80, 75, 70, 70, 101}, exp_curve: "medium_slow",
      pokedex: "강한 바람을 일으킨다."},

    # === Psychic (단일) ===
    %{slug: "mindmon-001", name_ko: "사념", type1: "psychic",
      base: {40, 45, 35, 100, 70, 90}, exp_curve: "medium_slow",
      pokedex: "강력한 정신력으로 사물을 움직인다."},

    # === Bug (2단) ===
    %{slug: "bugmon-001", name_ko: "벌레맨", type1: "bug",
      base: {45, 30, 35, 20, 20, 45}, evolves_to: "bugmon-002", evolves_at: 10,
      exp_curve: "medium_fast", pokedex: "잎을 갉아먹으며 자란다."},
    %{slug: "bugmon-002", name_ko: "나방", type1: "bug", type2: "flying",
      base: {60, 45, 50, 90, 80, 70}, exp_curve: "medium_fast",
      pokedex: "야간에 활발히 활동한다."},

    # === Rock (단일) ===
    %{slug: "rockmon-001", name_ko: "돌덩이", type1: "rock",
      base: {50, 70, 100, 35, 35, 35}, exp_curve: "medium_slow",
      pokedex: "단단한 돌덩어리 모양 트리즈몬."},

    # === Ghost (단일) ===
    %{slug: "ghostmon-001", name_ko: "유령아", type1: "ghost", type2: "poison",
      base: {30, 35, 30, 100, 35, 80}, exp_curve: "medium_slow",
      pokedex: "어둠 속에서 나타난다."},

    # === Dragon (2단) ===
    %{slug: "dragonmon-001", name_ko: "새끼용", type1: "dragon",
      base: {45, 60, 45, 50, 50, 50}, evolves_to: "dragonmon-002", evolves_at: 30,
      exp_curve: "slow", pokedex: "전설의 용족 새끼."},
    %{slug: "dragonmon-002", name_ko: "청룡", type1: "dragon", type2: "flying",
      base: {91, 134, 95, 100, 100, 80}, exp_curve: "slow",
      pokedex: "하늘을 가르는 강력한 용."},

    # === Dark (단일) ===
    %{slug: "darkmon-001", name_ko: "그림자", type1: "dark",
      base: {65, 90, 60, 70, 70, 95}, exp_curve: "medium_slow",
      pokedex: "어둠 속에서 사냥한다."},

    # === Steel (단일) ===
    %{slug: "steelmon-001", name_ko: "강철로보", type1: "steel",
      base: {65, 80, 140, 40, 70, 70}, exp_curve: "medium_slow",
      pokedex: "강철로 된 몸을 가진 트리즈몬."},

    # === Fairy (단일) ===
    %{slug: "fairymon-001", name_ko: "페어리꼬마", type1: "fairy",
      base: {55, 50, 75, 75, 95, 70}, exp_curve: "fast",
      pokedex: "달빛을 받아 강해진다."},

    # === Normal (단일) ===
    %{slug: "normalmon-001", name_ko: "다람쥐", type1: "normal",
      base: {35, 55, 30, 30, 30, 75}, exp_curve: "medium_fast",
      pokedex: "들판을 빠르게 달린다."}
  ]

  # ============================================================================
  # 30 기술
  # ============================================================================

  @moves [
    # === 일반 (5) ===
    %{slug: "tackle-001", name_ko: "몸통박치기", type: "normal", category: "physical",
      power: 40, accuracy: 100, pp: 35, priority: 0,
      description: "온몸을 부딪쳐서 상대를 공격한다."},
    %{slug: "scratch-001", name_ko: "할퀴기", type: "normal", category: "physical",
      power: 40, accuracy: 100, pp: 35, priority: 0,
      description: "날카로운 발톱으로 할퀸다."},
    %{slug: "bite-001", name_ko: "갉아먹기", type: "normal", category: "physical",
      power: 60, accuracy: 100, pp: 25, priority: 0,
      description: "강한 이빨로 깨문다."},
    %{slug: "quick-attack-001", name_ko: "빠른공격", type: "normal", category: "physical",
      power: 40, accuracy: 100, pp: 30, priority: 1,
      description: "선제 공격으로 상대보다 먼저 공격한다."},
    %{slug: "weak-strike-001", name_ko: "약한공격", type: "normal", category: "physical",
      power: 30, accuracy: 100, pp: 35, priority: 0,
      description: "약하지만 빠른 공격."},

    # === 불 (3) ===
    %{slug: "ember-001", name_ko: "불씨", type: "fire", category: "special",
      power: 40, accuracy: 100, pp: 25, priority: 0,
      description: "작은 불씨를 던진다."},
    %{slug: "fire-fang-001", name_ko: "불꽃세례", type: "fire", category: "special",
      power: 60, accuracy: 95, pp: 20, priority: 0,
      description: "불꽃을 연속으로 발사한다."},
    %{slug: "flamethrower-001", name_ko: "화염방사", type: "fire", category: "special",
      power: 90, accuracy: 100, pp: 15, priority: 0,
      description: "강력한 화염을 뿜는다."},

    # === 물 (3) ===
    %{slug: "water-gun-001", name_ko: "물대포", type: "water", category: "special",
      power: 40, accuracy: 100, pp: 25, priority: 0,
      description: "물줄기를 쏜다."},
    %{slug: "water-pulse-001", name_ko: "물의파동", type: "water", category: "special",
      power: 60, accuracy: 100, pp: 20, priority: 0,
      description: "물의 파동으로 공격한다."},
    %{slug: "hydro-pump-001", name_ko: "하이드로펌프", type: "water", category: "special",
      power: 110, accuracy: 80, pp: 5, priority: 0,
      description: "엄청난 양의 물을 발사한다."},

    # === 풀 (3) ===
    %{slug: "vine-whip-001", name_ko: "덩굴채찍", type: "grass", category: "physical",
      power: 45, accuracy: 100, pp: 25, priority: 0,
      description: "덩굴로 후려친다."},
    %{slug: "absorb-001", name_ko: "흡수", type: "grass", category: "special",
      power: 20, accuracy: 100, pp: 25, priority: 0,
      description: "상대 HP를 흡수한다 (효과 5c-late)."},
    %{slug: "solar-beam-001", name_ko: "솔라빔", type: "grass", category: "special",
      power: 120, accuracy: 100, pp: 10, priority: 0,
      description: "태양 에너지를 발사한다."},

    # === 전기 (2) ===
    %{slug: "thunder-shock-001", name_ko: "전기쇼크", type: "electric", category: "special",
      power: 40, accuracy: 100, pp: 30, priority: 0,
      description: "약한 전기로 공격한다."},
    %{slug: "thunderbolt-001", name_ko: "10만볼트", type: "electric", category: "special",
      power: 90, accuracy: 100, pp: 15, priority: 0,
      description: "강력한 전류를 발사한다."},

    # === 얼음 (2) ===
    %{slug: "icy-wind-001", name_ko: "얼음숨결", type: "ice", category: "special",
      power: 55, accuracy: 95, pp: 15, priority: 0,
      description: "차가운 바람으로 공격한다."},
    %{slug: "blizzard-001", name_ko: "눈보라", type: "ice", category: "special",
      power: 110, accuracy: 70, pp: 5, priority: 0,
      description: "거대한 눈보라를 일으킨다."},

    # === 격투 (2) ===
    %{slug: "karate-chop-001", name_ko: "격투킥", type: "fighting", category: "physical",
      power: 50, accuracy: 100, pp: 25, priority: 0,
      description: "강력한 발차기."},
    %{slug: "high-kick-001", name_ko: "무릎차기", type: "fighting", category: "physical",
      power: 80, accuracy: 90, pp: 15, priority: 0,
      description: "강한 무릎차기."},

    # === 독 (1) ===
    %{slug: "poison-sting-001", name_ko: "독찌르기", type: "poison", category: "physical",
      power: 15, accuracy: 100, pp: 35, priority: 0,
      description: "독이 묻은 침으로 찌른다."},

    # === 땅 (1) ===
    %{slug: "earth-power-001", name_ko: "땅가르기", type: "ground", category: "special",
      power: 90, accuracy: 100, pp: 10, priority: 0,
      description: "지면을 흔들어 공격한다."},

    # === 비행 (1) ===
    %{slug: "wing-attack-001", name_ko: "날개치기", type: "flying", category: "physical",
      power: 60, accuracy: 100, pp: 35, priority: 0,
      description: "큰 날개로 후려친다."},

    # === 에스퍼 (1) ===
    %{slug: "psychic-001", name_ko: "사이코키네시스", type: "psychic", category: "special",
      power: 90, accuracy: 100, pp: 10, priority: 0,
      description: "강력한 염력으로 공격한다."},

    # === 벌레 (1) ===
    %{slug: "bug-bite-001", name_ko: "무는공격", type: "bug", category: "physical",
      power: 60, accuracy: 100, pp: 20, priority: 0,
      description: "날카로운 입으로 깨문다."},

    # === 바위 (1) ===
    %{slug: "rock-throw-001", name_ko: "돌떨구기", type: "rock", category: "physical",
      power: 50, accuracy: 90, pp: 15, priority: 0,
      description: "큰 돌을 던진다."},

    # === 고스트 (1) ===
    %{slug: "shadow-claw-001", name_ko: "그림자손", type: "ghost", category: "physical",
      power: 70, accuracy: 100, pp: 15, priority: 0,
      description: "어둠의 손으로 할퀸다."},

    # === 드래곤 (1) ===
    %{slug: "dragon-breath-001", name_ko: "용의숨결", type: "dragon", category: "special",
      power: 60, accuracy: 100, pp: 20, priority: 0,
      description: "용의 숨결로 공격한다."},

    # === 악 (1) ===
    %{slug: "feint-attack-001", name_ko: "비열한공격", type: "dark", category: "physical",
      power: 60, accuracy: nil, pp: 20, priority: 0,
      description: "방심한 틈을 노린다 (반드시 명중)."},

    # === 강철 (1) ===
    %{slug: "metal-claw-001", name_ko: "메탈크로", type: "steel", category: "physical",
      power: 50, accuracy: 95, pp: 35, priority: 0,
      description: "강철 발톱으로 공격한다."},

    # === 페어리 (1) ===
    %{slug: "draining-kiss-001", name_ko: "매력있는소리", type: "fairy", category: "special",
      power: 50, accuracy: 100, pp: 10, priority: 0,
      description: "달콤한 소리로 공격한다."}
  ]

  # ============================================================================
  # 학습 표 — species_slug → [{move_slug, level}, ...]
  # ============================================================================
  # 각 종이 type 일치 기술 + 일반 기술 4-5개 학습.

  @species_moves %{
    # Fire 진화
    "pyromon-001" => [{"tackle-001", 1}, {"ember-001", 1}, {"scratch-001", 7}, {"fire-fang-001", 17}],
    "pyromon-002" => [{"tackle-001", 1}, {"ember-001", 1}, {"fire-fang-001", 17}, {"flamethrower-001", 30}],
    "pyromon-003" => [{"tackle-001", 1}, {"ember-001", 1}, {"flamethrower-001", 30}, {"wing-attack-001", 36}],

    # Water 진화
    "aquamon-001" => [{"tackle-001", 1}, {"water-gun-001", 1}, {"bite-001", 7}, {"water-pulse-001", 17}],
    "aquamon-002" => [{"tackle-001", 1}, {"water-gun-001", 1}, {"water-pulse-001", 17}, {"hydro-pump-001", 30}],
    "aquamon-003" => [{"tackle-001", 1}, {"water-gun-001", 1}, {"hydro-pump-001", 30}, {"icy-wind-001", 36}],

    # Grass 진화
    "leafmon-001" => [{"tackle-001", 1}, {"vine-whip-001", 1}, {"absorb-001", 7}, {"poison-sting-001", 17}],
    "leafmon-002" => [{"tackle-001", 1}, {"vine-whip-001", 1}, {"poison-sting-001", 17}, {"solar-beam-001", 32}],
    "leafmon-003" => [{"tackle-001", 1}, {"vine-whip-001", 1}, {"solar-beam-001", 32}, {"poison-sting-001", 17}],

    # Electric
    "voltmon-001" => [{"quick-attack-001", 1}, {"thunder-shock-001", 1}, {"thunderbolt-001", 22}],
    "voltmon-002" => [{"quick-attack-001", 1}, {"thunder-shock-001", 1}, {"thunderbolt-001", 22}],

    # Ice
    "frostmon-001" => [{"tackle-001", 1}, {"icy-wind-001", 1}, {"blizzard-001", 30}],
    "frostmon-002" => [{"tackle-001", 1}, {"icy-wind-001", 1}, {"blizzard-001", 30}, {"psychic-001", 35}],

    # Fighting
    "fistmon-001" => [{"tackle-001", 1}, {"karate-chop-001", 1}, {"high-kick-001", 28}],
    "fistmon-002" => [{"tackle-001", 1}, {"karate-chop-001", 1}, {"high-kick-001", 28}, {"bite-001", 1}],

    # Ground
    "earthmon-001" => [{"tackle-001", 1}, {"rock-throw-001", 1}, {"earth-power-001", 25}, {"bite-001", 10}],

    # Flying
    "windmon-001" => [{"tackle-001", 1}, {"quick-attack-001", 5}, {"wing-attack-001", 18}],
    "windmon-002" => [{"tackle-001", 1}, {"quick-attack-001", 5}, {"wing-attack-001", 18}, {"bite-001", 22}],

    # Psychic
    "mindmon-001" => [{"weak-strike-001", 1}, {"psychic-001", 15}, {"absorb-001", 5}],

    # Bug
    "bugmon-001" => [{"tackle-001", 1}, {"bug-bite-001", 10}, {"absorb-001", 1}],
    "bugmon-002" => [{"tackle-001", 1}, {"bug-bite-001", 10}, {"wing-attack-001", 15}, {"absorb-001", 1}],

    # Rock
    "rockmon-001" => [{"tackle-001", 1}, {"rock-throw-001", 1}, {"earth-power-001", 25}],

    # Ghost
    "ghostmon-001" => [{"weak-strike-001", 1}, {"shadow-claw-001", 12}, {"poison-sting-001", 1}, {"feint-attack-001", 18}],

    # Dragon
    "dragonmon-001" => [{"tackle-001", 1}, {"dragon-breath-001", 10}, {"bite-001", 7}],
    "dragonmon-002" => [{"tackle-001", 1}, {"dragon-breath-001", 10}, {"bite-001", 7}, {"wing-attack-001", 30}],

    # Dark
    "darkmon-001" => [{"scratch-001", 1}, {"feint-attack-001", 12}, {"bite-001", 7}, {"shadow-claw-001", 20}],

    # Steel
    "steelmon-001" => [{"tackle-001", 1}, {"metal-claw-001", 1}, {"rock-throw-001", 15}],

    # Fairy
    "fairymon-001" => [{"weak-strike-001", 1}, {"draining-kiss-001", 10}, {"absorb-001", 5}],

    # Normal
    "normalmon-001" => [{"tackle-001", 1}, {"quick-attack-001", 5}, {"scratch-001", 7}, {"bite-001", 12}]
  }

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Idempotent — 호출해도 중복 X. species/move/species_moves 모두 ensure.
  """
  def run! do
    ensure_moves!()
    ensure_species!()
    ensure_evolution_links!()
    ensure_species_moves!()

    Logger.info(
      "[trizmon.seed] done — species=#{length(@species)} moves=#{length(@moves)} species_moves=#{count_species_moves()}"
    )

    :ok
  end

  defp count_species_moves do
    Enum.reduce(@species_moves, 0, fn {_, list}, acc -> acc + length(list) end)
  end

  defp ensure_moves! do
    Enum.each(@moves, fn attrs ->
      case Repo.get_by(Move, slug: attrs.slug) do
        nil -> %Move{} |> Move.changeset(attrs) |> Repo.insert!()
        _ -> :ok
      end
    end)
  end

  defp ensure_species! do
    Enum.each(@species, fn data ->
      case Repo.get_by(Species, slug: data.slug) do
        nil ->
          {hp, atk, def_, spa, spd, spe} = data.base

          attrs =
            %{
              slug: data.slug,
              name_ko: data.name_ko,
              type1: data.type1,
              type2: Map.get(data, :type2),
              base_hp: hp,
              base_atk: atk,
              base_def: def_,
              base_spa: spa,
              base_spd: spd,
              base_spe: spe,
              catch_rate: 45,
              exp_curve: data.exp_curve,
              pokedex_text: data.pokedex,
              image_url: "/images/trizmon/#{data.slug}.png"
            }

          %Species{} |> Species.changeset(attrs) |> Repo.insert!()

        _ ->
          :ok
      end
    end)
  end

  # 진화 트리 — species 모두 insert 후 evolves_to_id 채움 (forward reference 회피).
  defp ensure_evolution_links! do
    by_slug =
      @species
      |> Enum.map(& &1.slug)
      |> Enum.map(fn slug -> {slug, Repo.get_by!(Species, slug: slug)} end)
      |> Map.new()

    Enum.each(@species, fn data ->
      case Map.get(data, :evolves_to) do
        nil ->
          :ok

        target_slug ->
          source = Map.fetch!(by_slug, data.slug)
          target = Map.fetch!(by_slug, target_slug)

          if source.evolves_to_id != target.id do
            source
            |> Species.changeset(%{
              evolves_to_id: target.id,
              evolves_at_level: data.evolves_at,
              evolution_method: "level"
            })
            |> Repo.update!()
          end
      end
    end)
  end

  defp ensure_species_moves! do
    moves_by_slug =
      @moves
      |> Enum.map(& &1.slug)
      |> Enum.map(fn slug -> {slug, Repo.get_by!(Move, slug: slug)} end)
      |> Map.new()

    species_by_slug =
      @species
      |> Enum.map(& &1.slug)
      |> Enum.map(fn slug -> {slug, Repo.get_by!(Species, slug: slug)} end)
      |> Map.new()

    import Ecto.Query

    Enum.each(@species_moves, fn {species_slug, learn_list} ->
      species = Map.fetch!(species_by_slug, species_slug)

      Enum.each(learn_list, fn {move_slug, level} ->
        move = Map.fetch!(moves_by_slug, move_slug)

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
              learn_level: level
            }
          ])
        end
      end)
    end)
  end

  @doc "starter 후보 종 (UI picker 용 — Sprint 5c-late)."
  def starter_slugs, do: ["pyromon-001", "aquamon-001", "leafmon-001"]
end
