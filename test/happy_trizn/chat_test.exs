defmodule HappyTrizn.ChatTest do
  @moduledoc """
  Chat module 은 Mongo 가 안 떠있을 때도 best-effort 로 :ok 반환해야 함.
  test 환경은 :mongo url=nil 이라 Process.whereis(:mongo) == nil → skip path 검증.
  """

  use ExUnit.Case, async: true

  alias HappyTrizn.Chat

  defp build_msg(body \\ "hello") do
    %{
      id: Ecto.UUID.generate(),
      nickname: "tester",
      body: body,
      ts: DateTime.utc_now(),
      registered: false
    }
  end

  describe "log_message/2" do
    test "Mongo 안 떠있어도 :ok 반환 (LiveView 진행 막지 않음)" do
      refute Process.whereis(:mongo)
      assert :ok = Chat.log_message(build_msg(), "lobby")
    end

    test "default channel = lobby" do
      assert :ok = Chat.log_message(build_msg())
    end

    test "긴 본문도 best-effort 통과" do
      long = String.duplicate("a", 500)
      assert :ok = Chat.log_message(build_msg(long))
    end

    test "registered=true 메시지" do
      msg = build_msg() |> Map.put(:registered, true)
      assert :ok = Chat.log_message(msg, "lobby")
    end
  end

  describe "recent_messages/2" do
    test "Mongo 없으면 빈 리스트" do
      refute Process.whereis(:mongo)
      assert [] = Chat.recent_messages("lobby", 100)
    end

    test "default 인자" do
      assert [] = Chat.recent_messages()
    end
  end
end
