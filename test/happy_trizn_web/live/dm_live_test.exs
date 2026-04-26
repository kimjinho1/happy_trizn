defmodule HappyTriznWeb.DmLiveTest do
  use HappyTriznWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias HappyTrizn.Friends
  alias HappyTrizn.Messages

  defp setup_friends(conn, suffix) do
    me = user_fixture(nickname: "me_dm_#{suffix}")
    peer = user_fixture(nickname: "peer_dm_#{suffix}")
    {:ok, fr} = Friends.send_request(me, peer)
    {:ok, _} = Friends.accept(peer, fr)
    {log_in_user(conn, me), me, peer}
  end

  describe "/dm — 대화 상대 리스트" do
    test "비로그인 → 리다이렉트", %{conn: conn} do
      conn = Plug.Test.init_test_session(conn, %{})
      assert {:error, {:redirect, %{to: "/lobby"}}} = live(conn, ~p"/dm")
    end

    test "친구 없으면 안내 노출", %{conn: conn} do
      user = user_fixture(nickname: "alone_#{System.unique_integer([:positive])}")
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/dm")
      assert html =~ "친구 추가 후 메시지"
    end

    test "친구 + 메시지 1개 → 대화 상대 list 노출", %{conn: conn} do
      {conn, me, peer} = setup_friends(conn, System.unique_integer([:positive]))
      {:ok, _} = Messages.send(peer, me, "hello")

      {:ok, _view, html} = live(conn, ~p"/dm")
      assert html =~ peer.nickname
      assert html =~ "hello"
      # unread 1.
      assert html =~ "badge-error"
    end
  end

  describe "/dm/:peer_id — thread" do
    test "친구 아니면 /dm 리다이렉트", %{conn: conn} do
      me = user_fixture()
      stranger = user_fixture()
      conn = log_in_user(conn, me)
      assert {:error, {:redirect, %{to: "/dm"}}} = live(conn, ~p"/dm/#{stranger.id}")
    end

    test "친구 thread — 메시지 노출 + 자동 mark_read", %{conn: conn} do
      {conn, me, peer} = setup_friends(conn, System.unique_integer([:positive]))
      {:ok, _} = Messages.send(peer, me, "ping")
      assert Messages.unread_count(me) == 1

      {:ok, _view, html} = live(conn, ~p"/dm/#{peer.id}")
      assert html =~ "ping"
      # mount 시 mark_thread_read.
      assert Messages.unread_count(me) == 0
    end

    test "send form → 메시지 추가 + DB 저장 + thread 갱신", %{conn: conn} do
      {conn, me, peer} = setup_friends(conn, System.unique_integer([:positive]))
      {:ok, view, _} = live(conn, ~p"/dm/#{peer.id}")

      view
      |> form("form#dm-form", %{body: "안녕"})
      |> render_submit()

      Process.sleep(20)
      html = render(view)
      assert html =~ "안녕"

      thread = Messages.list_thread(me, peer)
      assert length(thread) == 1
      assert hd(thread).body == "안녕"
    end

    test "PubSub — peer 가 보낸 메시지 실시간 추가", %{conn: conn} do
      {conn, me, peer} = setup_friends(conn, System.unique_integer([:positive]))
      {:ok, view, _} = live(conn, ~p"/dm/#{peer.id}")

      send(
        view.pid,
        {:dm_received,
         %{
           id: Ecto.UUID.generate(),
           from_user_id: peer.id,
           to_user_id: me.id,
           body: "live ping",
           read_at: nil,
           inserted_at: DateTime.utc_now() |> DateTime.truncate(:second)
         }}
      )

      Process.sleep(20)
      assert render(view) =~ "live ping"
    end
  end

  describe "글로벌 unread badge (top nav)" do
    test "unread > 0 → 헤더 💬 옆 badge 노출", %{conn: conn} do
      {conn, me, peer} = setup_friends(conn, System.unique_integer([:positive]))
      {:ok, _} = Messages.send(peer, me, "hi")

      {:ok, _view, html} = live(conn, ~p"/lobby")
      # 💬 링크 + badge.
      assert html =~ "href=\"/dm\""
      assert html =~ "1"
      _ = me
    end
  end

  describe "DM 실시간 알림 hook" do
    test "lobby 같은 다른 LV 에서도 DM 도착 시 dm:notify push_event 발행", %{conn: conn} do
      {conn, me, peer} = setup_friends(conn, System.unique_integer([:positive]))
      {:ok, view, _} = live(conn, ~p"/lobby")

      # peer 가 me 에게 DM 보냄.
      {:ok, _} = Messages.send(peer, me, "ping toast!")

      # hook 이 받아 push_event "dm:notify" 발행.
      assert_push_event(view, "dm:notify", %{body: "ping toast!", unread_count: 1})
    end

    test "비로그인 LV — hook attach 안 함 (subscribe / push_event 없음)", %{conn: conn} do
      conn = Plug.Test.init_test_session(conn, %{})
      {:error, _} = live(conn, ~p"/lobby")
      # 로그인 안 했으니 lobby 진입 자체 거부 — hook 도 작동 안 함.
    end
  end
end
