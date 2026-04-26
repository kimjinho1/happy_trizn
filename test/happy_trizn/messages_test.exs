defmodule HappyTrizn.MessagesTest do
  use HappyTrizn.DataCase, async: false

  alias HappyTrizn.Accounts
  alias HappyTrizn.Friends
  alias HappyTrizn.Messages

  defp user(suffix) do
    {:ok, u} =
      Accounts.register_user(%{
        email: "u#{suffix}@trizn.kr",
        nickname: "u#{suffix}",
        password: "hello12345"
      })

    u
  end

  defp make_friends(u1, u2) do
    {:ok, f} = Friends.send_request(u1, u2)
    {:ok, _} = Friends.accept(u2, f)
    :ok
  end

  describe "send/3" do
    test "친구 사이 — 정상 발송" do
      u1 = user(System.unique_integer([:positive]))
      u2 = user(System.unique_integer([:positive]))
      make_friends(u1, u2)

      assert {:ok, msg} = Messages.send(u1, u2, "안녕")
      assert msg.from_user_id == u1.id
      assert msg.to_user_id == u2.id
      assert msg.body == "안녕"
      assert is_nil(msg.read_at)
    end

    test "친구 아니면 거부 :not_friends" do
      u1 = user(System.unique_integer([:positive]))
      u2 = user(System.unique_integer([:positive]))
      assert {:error, :not_friends} = Messages.send(u1, u2, "hi")
    end

    test "자기 자신 거부 :invalid" do
      u1 = user(System.unique_integer([:positive]))
      assert {:error, :invalid} = Messages.send(u1, u1, "hi")
    end

    test "공백/빈 본문 거부 :invalid" do
      u1 = user(System.unique_integer([:positive]))
      u2 = user(System.unique_integer([:positive]))
      make_friends(u1, u2)
      assert {:error, :invalid} = Messages.send(u1, u2, "   ")
    end

    test "1000자 초과 시 slice" do
      u1 = user(System.unique_integer([:positive]))
      u2 = user(System.unique_integer([:positive]))
      make_friends(u1, u2)
      long = String.duplicate("a", 1500)
      {:ok, msg} = Messages.send(u1, u2, long)
      assert String.length(msg.body) == 1000
    end
  end

  describe "list_thread/3" do
    test "양방향 메시지 시간 오름차순" do
      u1 = user(System.unique_integer([:positive]))
      u2 = user(System.unique_integer([:positive]))
      make_friends(u1, u2)

      {:ok, _} = Messages.send(u1, u2, "1")
      Process.sleep(1100)
      {:ok, _} = Messages.send(u2, u1, "2")
      Process.sleep(1100)
      {:ok, _} = Messages.send(u1, u2, "3")

      ms = Messages.list_thread(u1, u2)
      assert length(ms) == 3
      assert Enum.map(ms, & &1.body) == ["1", "2", "3"]
    end
  end

  describe "mark_thread_read/2 + unread_count/1" do
    test "읽기 전 — unread > 0, 읽고 나면 0" do
      u1 = user(System.unique_integer([:positive]))
      u2 = user(System.unique_integer([:positive]))
      make_friends(u1, u2)

      {:ok, _} = Messages.send(u1, u2, "hi")
      {:ok, _} = Messages.send(u1, u2, "world")

      assert Messages.unread_count(u2) == 2
      assert Messages.unread_count(u1) == 0

      assert Messages.mark_thread_read(u2, u1) == 2
      assert Messages.unread_count(u2) == 0
    end
  end

  describe "recent_threads/1" do
    test "친구 별 최근 메시지 + unread 갯수" do
      me = user(System.unique_integer([:positive]))
      f1 = user(System.unique_integer([:positive]))
      f2 = user(System.unique_integer([:positive]))
      make_friends(me, f1)
      make_friends(me, f2)

      {:ok, _} = Messages.send(f1, me, "hi from f1")
      Process.sleep(1100)
      {:ok, _} = Messages.send(f2, me, "hi from f2")

      threads = Messages.recent_threads(me)
      assert length(threads) == 2
      # 최근 메시지부터 정렬 — f2 먼저.
      assert hd(threads).peer.id == f2.id
      # unread 둘 다 1.
      Enum.each(threads, fn t -> assert t.unread == 1 end)
    end

    test "친구 없으면 빈 리스트" do
      me = user(System.unique_integer([:positive]))
      assert Messages.recent_threads(me) == []
    end
  end

  describe "PubSub" do
    test "send → 받는 사람 topic 으로 :dm_received broadcast" do
      u1 = user(System.unique_integer([:positive]))
      u2 = user(System.unique_integer([:positive]))
      make_friends(u1, u2)

      Messages.subscribe(u2)
      {:ok, _} = Messages.send(u1, u2, "ping")

      assert_receive {:dm_received, %{body: "ping"}}, 500
    end

    test "mark_thread_read → 보낸 사람 topic 으로 :dm_read broadcast" do
      u1 = user(System.unique_integer([:positive]))
      u2 = user(System.unique_integer([:positive]))
      make_friends(u1, u2)

      {:ok, _} = Messages.send(u1, u2, "ping")

      Messages.subscribe(u1)
      Messages.mark_thread_read(u2, u1)

      assert_receive {:dm_read, %{count: 1}}, 500
    end
  end
end
