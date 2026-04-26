defmodule HappyTrizn.UserGameSettingsTest do
  use HappyTrizn.DataCase, async: true

  alias HappyTrizn.UserGameSettings
  alias HappyTrizn.UserGameSettings.Setting

  defp user_fixture(suffix \\ nil) do
    suffix = suffix || System.unique_integer([:positive])

    {:ok, user} =
      HappyTrizn.Accounts.register_user(%{
        email: "ugs#{suffix}@trizn.kr",
        nickname: "ugs#{suffix}",
        password: "hello12345"
      })

    user
  end

  describe "defaults/1" do
    test "tetris 기본 키 + 옵션 포함" do
      d = UserGameSettings.defaults("tetris")
      assert is_map(d.bindings)
      assert Map.has_key?(d.bindings, "move_left")
      assert "ArrowLeft" in d.bindings["move_left"]
      assert d.das == 133
      assert d.arr == 10
      assert d.options["ghost"] == true
    end

    test "각 게임 별 defaults 존재" do
      for slug <- ~w(tetris bomberman skribbl snake_io games_2048 minesweeper pacman) do
        d = UserGameSettings.defaults(slug)
        assert map_size(d.bindings) > 0, "#{slug} bindings empty"
        assert is_map(d.options), "#{slug} options not a map"
      end
    end

    test "skribbl round_seconds 80" do
      assert UserGameSettings.defaults("skribbl").options["round_seconds"] == 80
    end

    test "games_2048 board_size 4" do
      assert UserGameSettings.defaults("games_2048").options["board_size"] == 4
    end

    test "minesweeper difficulty + custom 필드 defaults" do
      opts = UserGameSettings.defaults("minesweeper").options
      assert opts["difficulty"] == "medium"
      assert opts["custom_rows"] == 10
      assert opts["custom_cols"] == 10
      assert opts["custom_mines"] == 12
    end

    test "알 수 없는 게임 → 빈 map" do
      d = UserGameSettings.defaults("unknown")
      assert d.bindings == %{}
      assert d.options == %{}
    end
  end

  describe "get_for/2" do
    test "user nil → defaults 반환" do
      assert UserGameSettings.get_for(nil, "tetris") == UserGameSettings.defaults("tetris")
    end

    test "user 있고 row 없음 → defaults 반환" do
      user = user_fixture()
      assert UserGameSettings.get_for(user, "tetris") == UserGameSettings.defaults("tetris")
    end

    test "친화 표기 (\"Space\"/\"space\") 자동 정규화 → \" \"" do
      user = user_fixture()

      {:ok, _} =
        UserGameSettings.upsert(user, "tetris", %{
          key_bindings: %{"hard_drop" => ["Space", "space"]},
          options: %{}
        })

      result = UserGameSettings.get_for(user, "tetris")
      assert result.bindings["hard_drop"] == [" ", " "]
    end

    test "row 있으면 default merge" do
      user = user_fixture()

      {:ok, _} =
        UserGameSettings.upsert(user, "tetris", %{
          key_bindings: %{"move_left" => ["a"]},
          options: %{"das" => 50}
        })

      result = UserGameSettings.get_for(user, "tetris")
      # custom 적용
      assert result.bindings["move_left"] == ["a"]
      assert result.das == 50
      # default 유지
      assert "ArrowRight" in result.bindings["move_right"]
      assert result.arr == 10
    end
  end

  describe "upsert/3" do
    test "신규 row 생성" do
      user = user_fixture()

      assert {:ok, %Setting{}} =
               UserGameSettings.upsert(user, "tetris", %{
                 key_bindings: %{"move_left" => ["j"]},
                 options: %{"ghost" => false}
               })

      assert Repo.get_by(Setting, user_id: user.id, game_type: "tetris")
    end

    test "기존 row 업데이트 (unique constraint)" do
      user = user_fixture()
      {:ok, _} = UserGameSettings.upsert(user, "tetris", %{key_bindings: %{}, options: %{}})

      {:ok, _} =
        UserGameSettings.upsert(user, "tetris", %{
          key_bindings: %{"move_left" => ["x"]},
          options: %{"das" => 200}
        })

      [row] = Repo.all(Setting)
      assert row.key_bindings["move_left"] == ["x"]
      assert row.options["das"] == 200
    end

    test "게스트 nil → :guest_not_allowed" do
      assert {:error, :guest_not_allowed} =
               UserGameSettings.upsert(nil, "tetris", %{key_bindings: %{}, options: %{}})
    end

    test "잘못된 game_type 거부" do
      user = user_fixture()

      assert {:error, %Ecto.Changeset{} = cs} =
               UserGameSettings.upsert(user, "haxxor_game", %{key_bindings: %{}, options: %{}})

      assert "is invalid" in errors_on(cs).game_type
    end
  end

  describe "reset/2" do
    test "row 삭제" do
      user = user_fixture()

      {:ok, _} =
        UserGameSettings.upsert(user, "tetris", %{key_bindings: %{"a" => ["b"]}, options: %{}})

      assert :ok = UserGameSettings.reset(user, "tetris")
      refute Repo.get_by(Setting, user_id: user.id, game_type: "tetris")
    end
  end

  describe "list_for_user/1" do
    test "사용자의 모든 게임 설정" do
      user = user_fixture()
      {:ok, _} = UserGameSettings.upsert(user, "tetris", %{key_bindings: %{}, options: %{}})
      {:ok, _} = UserGameSettings.upsert(user, "games_2048", %{key_bindings: %{}, options: %{}})

      rows = UserGameSettings.list_for_user(user)
      assert length(rows) == 2
      assert Enum.map(rows, & &1.game_type) |> Enum.sort() == ["games_2048", "tetris"]
    end

    test "nil → 빈 list" do
      assert UserGameSettings.list_for_user(nil) == []
    end
  end
end
