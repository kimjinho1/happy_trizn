defmodule HappyTrizn.Chat do
  @moduledoc """
  Chat 영구 저장 (MongoDB chat_logs).

  - log_message/1: best-effort. Mongo 안 떠있거나 실패해도 LiveView 진행 막지 않음.
  - 향후 Sprint 4 에서 Broadway 비동기 큐로 전환 (현재는 fire-and-forget sync).
  """

  require Logger

  @collection "chat_logs"

  @type message :: %{
          id: String.t(),
          nickname: String.t(),
          body: String.t(),
          ts: DateTime.t(),
          registered: boolean(),
          channel: String.t()
        }

  @doc """
  채팅 메시지 영구 저장. Mongo 안 떠있거나 에러 나도 :ok 반환.

  channel: "lobby" (글로벌), "dm:<a>:<b>" (DM, Sprint 2)
  """
  def log_message(msg, channel \\ "lobby") do
    doc = %{
      _id: msg.id,
      nickname: msg.nickname,
      body: msg.body,
      ts: msg.ts,
      registered: Map.get(msg, :registered, false),
      channel: channel
    }

    if mongo_alive?() do
      try do
        Mongo.insert_one(:mongo, @collection, doc)
      rescue
        e ->
          Logger.warning("[Chat] Mongo insert failed: #{Exception.message(e)}")
      catch
        kind, reason ->
          Logger.warning("[Chat] Mongo insert crashed: #{kind} #{inspect(reason)}")
      end
    end

    :ok
  end

  @doc "Admin 검토용: 최근 메시지 조회."
  def recent_messages(channel \\ "lobby", limit \\ 100) do
    if mongo_alive?() do
      try do
        Mongo.find(:mongo, @collection, %{channel: channel},
          sort: [ts: -1],
          limit: limit
        )
        |> Enum.to_list()
      rescue
        _ -> []
      catch
        _, _ -> []
      end
    else
      []
    end
  end

  defp mongo_alive? do
    is_pid(Process.whereis(:mongo))
  end
end
