defmodule HappyTrizn.Trizmon.CatchTest do
  use HappyTrizn.DataCase, async: false

  alias HappyTrizn.Trizmon.{Catch, Party, Pokedex, Seed, Species}
  alias HappyTrizn.Trizmon.Battle.Mon

  defp register!(suffix) do
    {:ok, u} =
      HappyTrizn.Accounts.register_user(%{
        email: "ctc#{suffix}@trizn.kr",
        nickname: "ctc#{suffix}",
        password: "hello12345"
      })

    u
  end

  defp build_wild_mon(species) do
    Party.cpu_mon_for_species(species.slug, 5)
  end

  setup do
    Seed.run!()
    species = HappyTrizn.Repo.get_by!(Species, slug: "normalmon-001")
    {:ok, user: register!(System.unique_integer([:positive])), species: species}
  end

  describe "catch_a/2 — 확률값" do
    test "full HP + catch_rate 45 (default) → ~15", %{species: species} do
      wild = build_wild_mon(species)
      a = Catch.catch_a(%{wild | current_hp: wild.max_hp}, 45)
      # (3*max - 2*max) * 45 / (3*max) = max * 45 / (3*max) = 15
      assert a == 15
    end

    test "low HP → a 증가", %{species: species} do
      wild = build_wild_mon(species)
      full = Catch.catch_a(%{wild | current_hp: wild.max_hp}, 45)
      low = Catch.catch_a(%{wild | current_hp: 1}, 45)
      assert low > full
    end

    test "catch_rate 255 + low HP → a 매우 큼 (보통 100% 잡힘)", %{species: species} do
      wild = build_wild_mon(species)
      a = Catch.catch_a(%{wild | current_hp: 1}, 255)
      # max_hp 작아서 정확히 255 못 도달 — 200 이상이면 거의 100% 확률.
      assert a >= 200
    end
  end

  describe "attempt/2" do
    test "fainted 야생 → :already_fainted", %{user: u, species: species} do
      wild = build_wild_mon(species) |> Mon.apply_damage(9999)
      assert :already_fainted = Catch.attempt(u, wild)
    end

    test "확정 잡기 (catch_rate 255 + low HP) → :caught + instance + slot",
         %{user: u} do
      # catch_rate 255 인 종 직접 만듦.
      attrs = %{
        slug: "easy_catch_test",
        name_ko: "EasyCatch",
        type1: "normal",
        base_hp: 50,
        base_atk: 50,
        base_def: 50,
        base_spa: 50,
        base_spd: 50,
        base_spe: 50,
        catch_rate: 255,
        exp_curve: "medium_fast"
      }

      species =
        %Species{}
        |> Species.changeset(attrs)
        |> HappyTrizn.Repo.insert!()

      # current_hp 1 + fainted? false 강제 (catch attempt 가능 상태).
      wild = Party.cpu_mon_for_species(species.slug, 5)
      wild = %{wild | current_hp: 1, fainted?: false}

      assert {:caught, instance, slot} = Catch.attempt(u, wild)
      assert instance.user_id == u.id
      assert instance.species_id == species.id
      assert slot in 1..6 or is_nil(slot)

      # pokedex caught 갱신.
      assert Pokedex.stats_for_user(u.id).caught_count >= 1
    end
  end
end
