defmodule HappyTrizn.Trizmon.PokedexTest do
  use HappyTrizn.DataCase, async: false

  alias HappyTrizn.Trizmon.{Pokedex, Seed, Species}

  defp register!(suffix) do
    {:ok, u} =
      HappyTrizn.Accounts.register_user(%{
        email: "pdx#{suffix}@trizn.kr",
        nickname: "pdx#{suffix}",
        password: "hello12345"
      })

    u
  end

  setup do
    Seed.run!()
    species = HappyTrizn.Repo.get_by!(Species, slug: "pyromon-001")
    {:ok, user: register!(System.unique_integer([:positive])), species: species}
  end

  describe "mark_seen!/2" do
    test "처음 → seen entry insert", %{user: u, species: s} do
      :ok = Pokedex.mark_seen!(u.id, s.id)

      stats = Pokedex.stats_for_user(u.id)
      assert stats.seen_count == 1
      assert stats.caught_count == 0
    end

    test "두 번 호출 → 중복 X (idempotent)", %{user: u, species: s} do
      :ok = Pokedex.mark_seen!(u.id, s.id)
      :ok = Pokedex.mark_seen!(u.id, s.id)

      stats = Pokedex.stats_for_user(u.id)
      assert stats.seen_count == 1
    end
  end

  describe "mark_caught!/2" do
    test "처음 → caught entry (seen + caught 동시)", %{user: u, species: s} do
      :ok = Pokedex.mark_caught!(u.id, s.id)

      stats = Pokedex.stats_for_user(u.id)
      assert stats.seen_count == 1
      assert stats.caught_count == 1
    end

    test "seen → caught 승격", %{user: u, species: s} do
      :ok = Pokedex.mark_seen!(u.id, s.id)

      pre = Pokedex.stats_for_user(u.id)
      assert pre.caught_count == 0

      :ok = Pokedex.mark_caught!(u.id, s.id)

      post = Pokedex.stats_for_user(u.id)
      assert post.seen_count == 1
      assert post.caught_count == 1
    end

    test "이미 caught → noop", %{user: u, species: s} do
      :ok = Pokedex.mark_caught!(u.id, s.id)
      :ok = Pokedex.mark_caught!(u.id, s.id)
      assert Pokedex.stats_for_user(u.id).caught_count == 1
    end
  end

  describe "list_for_user/1" do
    test "여러 종 + species 정보 join", %{user: u} do
      s1 = HappyTrizn.Repo.get_by!(Species, slug: "pyromon-001")
      s2 = HappyTrizn.Repo.get_by!(Species, slug: "aquamon-001")

      :ok = Pokedex.mark_seen!(u.id, s1.id)
      :ok = Pokedex.mark_caught!(u.id, s2.id)

      list = Pokedex.list_for_user(u.id)
      assert length(list) == 2

      pyromon = Enum.find(list, &(&1.slug == "pyromon-001"))
      assert pyromon.status == "seen"
      assert pyromon.name_ko == "불꽃이"

      aquamon = Enum.find(list, &(&1.slug == "aquamon-001"))
      assert aquamon.status == "caught"
    end
  end
end
