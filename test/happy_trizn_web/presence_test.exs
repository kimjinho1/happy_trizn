defmodule HappyTriznWeb.PresenceTest do
  use HappyTriznWeb.ConnCase, async: false

  alias HappyTriznWeb.Presence

  describe "track_user / online_user_ids / online?" do
    test "track + lookup" do
      pid = self()
      user_id = "test_user_#{System.unique_integer([:positive])}"

      assert {:ok, _} = Presence.track_user(pid, user_id)
      Process.sleep(20)

      assert MapSet.member?(Presence.online_user_ids(), user_id)
      assert Presence.online?(user_id)
    end

    test "untrack — process 종료 시 자동" do
      user_id = "ephemeral_#{System.unique_integer([:positive])}"

      task =
        Task.async(fn ->
          Presence.track_user(self(), user_id)
          Process.sleep(50)
        end)

      Process.sleep(20)
      assert Presence.online?(user_id)

      Task.await(task)
      Process.sleep(50)
      refute Presence.online?(user_id)
    end

    test "track_user nil → :ignore" do
      assert :ignore = Presence.track_user(self(), nil)
    end

    test "online? string user_id 만 매칭" do
      refute Presence.online?(nil)
      refute Presence.online?(123)
    end
  end
end
