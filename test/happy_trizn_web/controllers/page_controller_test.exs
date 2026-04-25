defmodule HappyTriznWeb.PageControllerTest do
  use HappyTriznWeb.ConnCase, async: true

  describe "GET /" do
    test "anonymous 게스트 입장 폼 렌더", %{conn: conn} do
      conn = get(conn, ~p"/")
      body = html_response(conn, 200)
      assert body =~ "Happy Trizn"
      assert body =~ "닉네임으로 즉시 입장"
      assert body =~ "@trizn.kr 가입"
    end

    test "게스트 세션 → 환영 + /lobby 링크", %{conn: conn} do
      conn = log_in_user(conn, nil, "guesty_visitor") |> get(~p"/")
      body = html_response(conn, 200)
      assert body =~ "guesty_visitor"
      assert body =~ "기록은 저장되지 않습니다"
      assert body =~ "로비 입장"
    end

    test "등록자 세션 → 환영 + 이메일", %{conn: conn} do
      user = user_fixture(nickname: "regulus", email: "regulus@trizn.kr")
      conn = log_in_user(conn, user) |> get(~p"/")
      body = html_response(conn, 200)
      assert body =~ "regulus"
      assert body =~ "regulus@trizn.kr"
      assert body =~ "로비 입장"
    end
  end
end
