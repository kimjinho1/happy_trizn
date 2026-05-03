defmodule HappyTrizn.Trizmon.SeedTest do
  use HappyTrizn.DataCase, async: false

  alias HappyTrizn.Trizmon.{Move, Seed, Species}
  alias HappyTrizn.Repo

  describe "run!/0 — idempotent" do
    test "1차 run — 29 species + 31 moves 삽입" do
      assert :ok = Seed.run!()

      assert Repo.aggregate(Species, :count, :id) == 29
      assert Repo.aggregate(Move, :count, :id) == 31
    end

    test "2회 run — 중복 삽입 X" do
      Seed.run!()
      species_count_1 = Repo.aggregate(Species, :count, :id)
      moves_count_1 = Repo.aggregate(Move, :count, :id)

      Seed.run!()
      species_count_2 = Repo.aggregate(Species, :count, :id)
      moves_count_2 = Repo.aggregate(Move, :count, :id)

      assert species_count_1 == species_count_2
      assert moves_count_1 == moves_count_2
    end

    test "starter 3종 존재" do
      Seed.run!()

      Enum.each(Seed.starter_slugs(), fn slug ->
        assert %Species{slug: ^slug} = Repo.get_by(Species, slug: slug)
      end)
    end

    test "진화 트리 — pyromon-001 → pyromon-002 → pyromon-003" do
      Seed.run!()

      first = Repo.get_by!(Species, slug: "pyromon-001")
      second = Repo.get_by!(Species, slug: "pyromon-002")
      third = Repo.get_by!(Species, slug: "pyromon-003")

      assert first.evolves_to_id == second.id
      assert first.evolves_at_level == 16
      assert second.evolves_to_id == third.id
      assert second.evolves_at_level == 36
      # 최종 단계 — 진화 X
      assert is_nil(third.evolves_to_id)
    end

    test "각 종이 학습 가능 기술 1개 이상" do
      Seed.run!()
      import Ecto.Query

      Repo.all(Species)
      |> Enum.each(fn s ->
        count =
          Repo.aggregate(
            from(sm in "trizmon_species_moves", where: sm.species_id == ^s.id),
            :count,
            :species_id
          )

        assert count >= 1, "species #{s.slug} 학습 가능 기술 없음"
      end)
    end
  end

  describe "starter_slugs/0" do
    test "3종 — 불 / 물 / 풀" do
      assert ["pyromon-001", "aquamon-001", "leafmon-001"] = Seed.starter_slugs()
    end
  end
end
