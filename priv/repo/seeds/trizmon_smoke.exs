# Sprint 5c-1 smoke seed — 1 종 + 1 기술 + 학습 표.
#
# 실행:
#   docker compose exec app /app/bin/happy_trizn eval 'Code.require_file("priv/repo/seeds/trizmon_smoke.exs")'
# 또는 mix run priv/repo/seeds/trizmon_smoke.exs (test/dev).
#
# spec: docs/TRIZMON_SPEC.md §15

alias HappyTrizn.Repo
alias HappyTrizn.Trizmon.{Move, Species}

# 1 종 — 불꽃이 (시작 몬스터, fire single)
species_attrs = %{
  slug: "pyromon-001",
  name_ko: "불꽃이",
  name_en: "Pyromon",
  type1: "fire",
  type2: nil,
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
  evolution_method: nil,
  image_url: "/images/trizmon/pyromon-001.png"
}

%Species{}
|> Species.changeset(species_attrs)
|> Repo.insert!(on_conflict: :nothing, conflict_target: [:slug])

# 1 기술 — 몸통박치기 (normal physical, 무난)
move_attrs = %{
  slug: "tackle-001",
  name_ko: "몸통박치기",
  type: "normal",
  category: "physical",
  power: 40,
  accuracy: 100,
  pp: 35,
  priority: 0,
  effect_code: nil,
  description: "온몸을 부딪쳐서 상대를 공격한다."
}

%Move{}
|> Move.changeset(move_attrs)
|> Repo.insert!(on_conflict: :nothing, conflict_target: [:slug])

# 학습 표 — 불꽃이 가 1 lv 부터 몸통박치기 학습.
species = Repo.get_by!(Species, slug: "pyromon-001")
move = Repo.get_by!(Move, slug: "tackle-001")

import Ecto.Query

unless Repo.exists?(
         from sm in "trizmon_species_moves",
           where:
             sm.species_id == ^species.id and sm.move_id == ^move.id and
               sm.learn_method == "level"
       ) do
  Repo.insert_all("trizmon_species_moves", [
    %{
      species_id: species.id,
      move_id: move.id,
      learn_method: "level",
      learn_level: 1
    }
  ])
end

IO.puts("[trizmon_smoke] seed 완료: 1 종 (불꽃이) + 1 기술 (몸통박치기)")
