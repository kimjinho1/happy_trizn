defmodule HappyTrizn.AdminTest do
  use HappyTrizn.DataCase, async: true

  alias HappyTrizn.Admin
  alias HappyTrizn.Admin.AdminAction
  alias HappyTrizn.Accounts

  defp register_user!(suffix) do
    {:ok, u} =
      Accounts.register_user(%{
        email: "u#{suffix}@trizn.kr",
        nickname: "u#{suffix}",
        password: "hello12345"
      })

    u
  end

  describe "log_action/3" do
    test "최소 인자 (admin_id + action)" do
      assert {:ok, %AdminAction{} = a} = Admin.log_action("admin", "ban")
      assert a.admin_id == "admin"
      assert a.action == "ban"
      assert is_nil(a.target_user_id)
      assert is_nil(a.target_room_id)
      assert is_nil(a.payload)
      assert a.inserted_at
    end

    test "target_user_id 포함" do
      user = register_user!(System.unique_integer([:positive]))
      assert {:ok, a} = Admin.log_action("admin", "ban", target_user_id: user.id)
      assert a.target_user_id == user.id
    end

    test "payload map 저장" do
      assert {:ok, a} = Admin.log_action("admin", "nickname_change", payload: %{from: "x", to: "y"})
      assert a.payload == %{"from" => "x", "to" => "y"} or a.payload == %{from: "x", to: "y"}
    end

    test "허용 안 된 action 거부" do
      assert {:error, cs} = Admin.log_action("admin", "totally_made_up")
      assert "is invalid" in errors_on(cs).action
    end

    test "admin_id 누락 거부" do
      assert {:error, cs} = Admin.log_action("", "ban")
      assert "can't be blank" in errors_on(cs).admin_id
    end
  end

  describe "list_actions/1" do
    setup do
      user = register_user!(System.unique_integer([:positive]))
      {:ok, _} = Admin.log_action("admin", "ban", target_user_id: user.id)
      {:ok, _} = Admin.log_action("admin", "unban", target_user_id: user.id)
      {:ok, _} = Admin.log_action("admin", "room_kill")
      :ok
    end

    test "default 100 limit, 최신 순" do
      results = Admin.list_actions()
      assert length(results) >= 3
      assert hd(results).action in ["ban", "unban", "room_kill"]
    end

    test "action 필터" do
      bans = Admin.list_actions(action: "ban")
      assert Enum.all?(bans, &(&1.action == "ban"))
    end

    test "limit 적용" do
      results = Admin.list_actions(limit: 1)
      assert length(results) == 1
    end
  end
end
