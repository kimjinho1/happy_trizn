defmodule HappyTrizn.Trizmon.SavesTest do
  use HappyTrizn.DataCase, async: false

  alias HappyTrizn.Trizmon.Saves

  defp register!(suffix) do
    {:ok, u} =
      HappyTrizn.Accounts.register_user(%{
        email: "trzs#{suffix}@trizn.kr",
        nickname: "trzs#{suffix}",
        password: "hello12345"
      })

    u
  end

  describe "get_or_init!/1" do
    test "첫 호출 — starting_town 자동 생성" do
      u = register!(System.unique_integer([:positive]))
      save = Saves.get_or_init!(u)

      assert save.user_id == u.id
      assert save.current_map == "starting_town"
      assert save.player_x == 7
      assert save.player_y == 9
      assert save.badges == 0
      assert save.money == 1000
    end

    test "두번째 호출 — 같은 row 반환 (자동 생성 X)" do
      u = register!(System.unique_integer([:positive]))
      save1 = Saves.get_or_init!(u)
      save2 = Saves.get_or_init!(u)

      assert save1.user_id == save2.user_id
      assert save1.player_x == save2.player_x
    end
  end

  describe "update_position!/4" do
    test "위치 갱신 + last_played_at 갱신" do
      u = register!(System.unique_integer([:positive]))
      save = Saves.get_or_init!(u)

      new_save = Saves.update_position!(save, 5, 8)
      assert new_save.player_x == 5
      assert new_save.player_y == 8

      # 같은 row 갱신 — DB count 1.
      assert HappyTrizn.Repo.aggregate(HappyTrizn.Trizmon.Save, :count, :user_id) == 1
    end
  end

  describe "reset!/1" do
    test "기존 save 삭제 + 새 starting_town" do
      u = register!(System.unique_integer([:positive]))
      _ = Saves.get_or_init!(u) |> Saves.update_position!(2, 3)

      save = Saves.reset!(u)
      assert save.player_x == 7
      assert save.player_y == 9
    end
  end
end
