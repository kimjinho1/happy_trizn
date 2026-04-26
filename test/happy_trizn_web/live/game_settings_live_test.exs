defmodule HappyTriznWeb.GameSettingsLiveTest do
  use HappyTriznWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias HappyTrizn.UserGameSettings

  describe "/settings/games — 인증 가드" do
    test "비입장 → / 리다이렉트", %{conn: conn} do
      conn = Plug.Test.init_test_session(conn, %{})
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/settings/games")
    end
  end

  describe "/settings/games — index" do
    setup %{conn: conn} do
      user = user_fixture(nickname: "settings_user_#{System.unique_integer([:positive])}")
      {:ok, conn: log_in_user(conn, user), user: user}
    end

    test "마운트 + 게임 목록 표시", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings/games")
      assert html =~ "게임 옵션"
      assert html =~ "Tetris"
    end
  end

  describe "/settings/games/tetris — show" do
    setup %{conn: conn} do
      user = user_fixture(nickname: "tet_set_#{System.unique_integer([:positive])}")
      {:ok, conn: log_in_user(conn, user), user: user}
    end

    test "마운트 + 폼 표시 + 기본 키 바인딩", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings/games/tetris")
      assert html =~ "Tetris 옵션"
      assert html =~ "ArrowLeft"
      assert html =~ "DAS"
    end

    test "save_binding → DB 저장 + flash", %{conn: conn, user: user} do
      {:ok, view, _} = live(conn, ~p"/settings/games/tetris")

      view
      |> form("form[phx-submit='save_binding']:first-of-type", %{
        "action" => "move_left",
        "keys" => "j, ArrowLeft"
      })
      |> render_submit()

      result = UserGameSettings.get_for(user, "tetris")
      assert result.bindings["move_left"] == ["j", "ArrowLeft"]
    end

    test "save_options → DB 저장", %{conn: conn, user: user} do
      {:ok, view, _} = live(conn, ~p"/settings/games/tetris")

      view
      |> form("form[phx-submit='save_options']", %{
        "options" => %{
          "das" => "80",
          "arr" => "5",
          "soft_drop_speed" => "fast",
          "grid" => "full",
          "ghost" => "true",
          "sound_volume" => "30"
        }
      })
      |> render_submit()

      result = UserGameSettings.get_for(user, "tetris")
      assert result.das == 80
      assert result.arr == 5
      assert result.options["soft_drop_speed"] == "fast"
      assert result.options["ghost"] == true
    end

    test "reset → row 삭제 + 기본값 복귀", %{conn: conn, user: user} do
      {:ok, _} =
        UserGameSettings.upsert(user, "tetris", %{
          key_bindings: %{"move_left" => ["q"]},
          options: %{"das" => 999}
        })

      {:ok, view, _} = live(conn, ~p"/settings/games/tetris")
      view |> element("button[phx-click='reset']") |> render_click()

      result = UserGameSettings.get_for(user, "tetris")
      # 기본값 복귀
      assert result.das == 133
      assert "ArrowLeft" in result.bindings["move_left"]
    end
  end

  describe "/settings/games — 게스트" do
    setup %{conn: conn} do
      {:ok, conn: log_in_user(conn, nil, "guest_settings_#{System.unique_integer([:positive])}")}
    end

    test "게스트도 페이지는 보임 (저장 비활성)", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings/games/tetris")
      assert html =~ "Tetris 옵션"
      assert html =~ "게스트는"
      # disabled 상태
      assert html =~ "disabled"
    end

    test "게스트 save_binding → flash error + DB 변동 없음", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/settings/games/tetris")

      html =
        view
        |> render_hook("save_binding", %{"action" => "move_left", "keys" => "x"})

      assert html =~ "게스트는"
    end
  end

  describe "/settings/games/:game_type — non-tetris 게임 (제너릭 폼)" do
    setup %{conn: conn} do
      user = user_fixture(nickname: "gen_set_#{System.unique_integer([:positive])}")
      {:ok, conn: log_in_user(conn, user), user: user}
    end

    test "bomberman 옵션 페이지 마운트", %{conn: conn} do
      {:ok, _, html} = live(conn, ~p"/settings/games/bomberman")
      assert html =~ "Bomberman"
      # bindings 액션 표시
      assert html =~ "place_bomb"
    end

    test "skribbl 옵션 폼 + chat_sound 체크박스", %{conn: conn} do
      {:ok, _, html} = live(conn, ~p"/settings/games/skribbl")
      assert html =~ "캐치마인드"
      assert html =~ "chat_sound"
      assert html =~ "round_seconds"
    end

    test "snake_io binding 저장 가능", %{conn: conn, user: user} do
      {:ok, view, _} = live(conn, ~p"/settings/games/snake_io")

      view
      |> form("form[phx-submit='save_binding']:first-of-type", %{
        "action" => "boost",
        "keys" => "Shift, x"
      })
      |> render_submit()

      result = UserGameSettings.get_for(user, "snake_io")
      assert result.bindings["boost"] == ["Shift", "x"]
    end

    test "checkbox unchecked → false 로 저장 (hidden field)", %{conn: conn, user: user} do
      {:ok, view, _} = live(conn, ~p"/settings/games/skribbl")

      # chat_sound 끄기 — hidden=false 만 보내고 checkbox value 안 보냄
      view
      |> form("form[phx-submit='save_options']", %{
        "options" => %{"chat_sound" => "false"}
      })
      |> render_submit()

      result = UserGameSettings.get_for(user, "skribbl")
      assert result.options["chat_sound"] == false
    end
  end

  describe "/settings/games/:game_type — invalid slug" do
    setup %{conn: conn} do
      user = user_fixture(nickname: "inv_slug_#{System.unique_integer([:positive])}")
      {:ok, conn: log_in_user(conn, user)}
    end

    test "없는 game_type → 게임 목록으로 redirect", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/settings/games"}}} =
               live(conn, ~p"/settings/games/nopegame")
    end
  end
end
