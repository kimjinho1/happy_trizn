defmodule HappyTriznWeb.ProfileLiveTest do
  use HappyTriznWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "/me — 마이페이지" do
    test "비로그인 → /lobby 리다이렉트", %{conn: conn} do
      conn = Plug.Test.init_test_session(conn, %{})
      assert {:error, {:redirect, %{to: "/lobby"}}} = live(conn, ~p"/me")
    end

    test "게스트 → /lobby 리다이렉트 (current_user nil)", %{conn: conn} do
      conn = log_in_user(conn, nil, "guest_#{System.unique_integer([:positive])}")
      assert {:error, {:redirect, %{to: "/lobby"}}} = live(conn, ~p"/me")
    end

    test "등록 사용자 — 닉네임 / 이메일 / form 노출", %{conn: conn} do
      user = user_fixture(nickname: "me_#{System.unique_integer([:positive])}")
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/me")

      assert html =~ user.nickname
      assert html =~ user.email
      assert html =~ "phx-submit=\"save\""
      assert html =~ "phx-change=\"validate\""
      # avatar 미업로드 — 첫글자 fallback.
      assert html =~ String.first(user.nickname) |> String.upcase()
    end

    test "닉네임 저장 → DB 반영", %{conn: conn} do
      user = user_fixture(nickname: "old_#{System.unique_integer([:positive])}")
      conn = log_in_user(conn, user)
      {:ok, view, _} = live(conn, ~p"/me")

      new_nick = "new_#{System.unique_integer([:positive])}"

      view
      |> form("form[phx-submit='save']", user: %{nickname: new_nick})
      |> render_submit()

      reloaded = HappyTrizn.Accounts.get_user(user.id)
      assert reloaded.nickname == new_nick
    end

    test "닉네임 짧음 → 에러 메시지", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      {:ok, view, _} = live(conn, ~p"/me")

      view
      |> form("form[phx-submit='save']", user: %{nickname: "a"})
      |> render_submit()

      reloaded = HappyTrizn.Accounts.get_user(user.id)
      # 변경 안 됨.
      assert reloaded.nickname == user.nickname
    end
  end

  describe "글로벌 top nav 아바타" do
    test "등록 사용자 — 첫 글자 fallback 노출", %{conn: conn} do
      user = user_fixture(nickname: "tnav_#{System.unique_integer([:positive])}")
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/lobby")

      # /me 링크 + 닉네임 첫글자.
      assert html =~ "href=\"/me\""
      assert html =~ user.nickname
    end
  end
end
