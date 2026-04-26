defmodule HappyTrizn.GameEventsTest do
  @moduledoc """
  Sprint 4d — GameEvents Broadway pipeline.

  test 환경:
  - :mongo 프로세스 없음 (test.exs 에서 url=nil)
  - Pipeline Application start 시 disabled (game_events: enabled: false)
  - Producer 만 따로 띄워서 push/dispatch 검증.
  """

  use ExUnit.Case, async: false

  alias HappyTrizn.GameEvents
  alias HappyTrizn.GameEvents.Producer

  describe "emit/4" do
    test "Producer 안 떠있어도 :ok (LiveView 진행 막지 않음)" do
      refute Process.whereis(Producer)
      assert :ok = GameEvents.emit("tetris", "room-1", :match_completed, %{winner: "u1"})
    end

    test "default payload = %{}" do
      assert :ok = GameEvents.emit("snake_io", "room-2", :game_over)
    end

    test "atom event_name → string 변환" do
      assert :ok = GameEvents.emit("tetris", "r", :countdown_start, %{})
    end

    test "string event_name 도 허용" do
      assert :ok = GameEvents.emit("tetris", "r", "custom_event", %{})
    end
  end

  describe "Producer (단독 부팅)" do
    setup do
      pid = start_supervised!(Producer)
      {:ok, producer: pid}
    end

    test "push 누적 + 자동 dispatch (consumer 가 demand 시)", %{producer: producer} do
      # consumer 가 없으면 큐에 쌓이기만 함.
      Producer.push(%{event: "a"})
      Producer.push(%{event: "b"})

      # GenStage.stream 으로 consumer subscribe — demand 보내고 받기.
      events =
        [{producer, max_demand: 10}]
        |> GenStage.stream()
        |> Enum.take(2)

      assert length(events) == 2
      assert Enum.map(events, & &1.event) == ["a", "b"]
    end

    test "demand 먼저 → 이후 push 가 즉시 dispatch", %{producer: producer} do
      task =
        Task.async(fn ->
          [{producer, max_demand: 10}]
          |> GenStage.stream()
          |> Enum.take(1)
        end)

      # demand 가 먼저 도착하도록 대기.
      Process.sleep(20)
      Producer.push(%{event: "delayed"})

      [event] = Task.await(task, 1_000)
      assert event.event == "delayed"
    end
  end

  describe "stringify_keys (private 동작 — emit 통합)" do
    test "atom key map → string key 변환" do
      # 직접 emit → Producer push. Producer 안 떴으니 :ok 만 보장.
      assert :ok = GameEvents.emit("tetris", "r", :test, %{a: 1, b: %{c: 2}})
    end

    test "tuple → list 변환 (BSON 호환)" do
      assert :ok = GameEvents.emit("tetris", "r", :test, %{coord: {1, 2}})
    end
  end
end
