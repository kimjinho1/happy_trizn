defmodule HappyTrizn.GameEvents do
  @moduledoc """
  게임 이벤트 비동기 영구 적재 — Mongo `game_events` collection.

  Sprint 4d. game_session 의 broadcast 와 별개로, 분석/감사용 이벤트를
  Broadway pipeline 으로 batch 인서트.

  - emit/4 — fire-and-forget, 어떤 LiveView/GenServer 에서도 호출 가능.
  - Mongo 안 떠있어도 호출자 영향 없음 (Producer enqueue 만 됨, batch 시 skip).
  - batch_size 100, batch_timeout 1초 → 부하 적음.
  """

  alias HappyTrizn.GameEvents.Producer

  @doc """
  게임 이벤트 발행.

      GameEvents.emit("tetris", "room-abc", :match_completed, %{winner: "u123"})

  비동기 cast — 즉시 :ok.
  """
  @spec emit(String.t() | nil, String.t() | nil, atom() | String.t(), map()) :: :ok
  def emit(game_type, room_id, event_name, payload \\ %{})
      when is_map(payload) do
    doc = %{
      game_type: game_type,
      room_id: room_id,
      event: to_string(event_name),
      payload: stringify_keys(payload),
      ts: DateTime.utc_now()
    }

    Producer.push(doc)
    :ok
  end

  defp stringify_keys(%DateTime{} = dt), do: dt
  defp stringify_keys(%{__struct__: _} = v), do: inspect(v)

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), stringify_keys(v)} end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> stringify_keys()
  defp stringify_keys(v), do: v
end

defmodule HappyTrizn.GameEvents.Producer do
  @moduledoc """
  GenStage producer — buffered queue, demand-driven.

  Pipeline 의 processor 가 demand 보내면 큐에서 pop 하여 emit.
  Mongo 다운/Pipeline 다운이라도 push/3 는 항상 :ok (GenStage cast).
  """

  use GenStage

  def start_link(_opts) do
    GenStage.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  이벤트를 Broadway producer 큐에 적재. 비동기.

  Broadway 가 producer 이름을 자체 관리 (`Pipeline.Broadway.Producer_N`) 하므로
  `Broadway.producer_names/1` 으로 lookup. Pipeline 안 떠있으면 :ok skip.
  """
  def push(event) do
    pipeline = HappyTrizn.GameEvents.Pipeline

    cond do
      is_nil(Process.whereis(pipeline)) ->
        # 단독 부팅 (test) 모드 — Producer 직접 lookup.
        case Process.whereis(__MODULE__) do
          nil -> :ok
          pid -> GenStage.cast(pid, {:push, event})
        end

      true ->
        case Broadway.producer_names(pipeline) do
          [] -> :ok
          names -> GenStage.cast(Enum.random(names), {:push, event})
        end
    end
  rescue
    _ -> :ok
  end

  @impl true
  def init(_) do
    {:producer, %{queue: :queue.new(), demand: 0}}
  end

  @impl true
  def handle_cast({:push, event}, state) do
    new_queue = :queue.in(event, state.queue)
    dispatch(%{state | queue: new_queue}, [])
  end

  @impl true
  def handle_demand(incoming, state) do
    dispatch(%{state | demand: state.demand + incoming}, [])
  end

  defp dispatch(%{demand: 0} = state, events) do
    {:noreply, Enum.reverse(events), state}
  end

  defp dispatch(state, events) do
    case :queue.out(state.queue) do
      {:empty, _} ->
        {:noreply, Enum.reverse(events), state}

      {{:value, e}, q} ->
        dispatch(%{state | queue: q, demand: state.demand - 1}, [e | events])
    end
  end
end

defmodule HappyTrizn.GameEvents.Pipeline do
  @moduledoc """
  Broadway pipeline — Producer → batcher → MongoDB bulk insert.

  - batch_size 100, batch_timeout 1_000ms.
  - Mongo 안 떠있으면 batch handler 가 silent skip.
  """

  use Broadway

  alias Broadway.Message

  require Logger

  @collection "game_events"

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {HappyTrizn.GameEvents.Producer, []},
        transformer: {__MODULE__, :transform, []},
        concurrency: 1
      ],
      processors: [default: [concurrency: 1]],
      batchers: [
        mongo: [concurrency: 1, batch_size: 100, batch_timeout: 1_000]
      ]
    )
  end

  def transform(event, _opts) do
    %Message{data: event, acknowledger: Broadway.NoopAcknowledger.init()}
  end

  @impl true
  def handle_message(_processor, %Message{} = msg, _ctx) do
    Message.put_batcher(msg, :mongo)
  end

  @impl true
  def handle_batch(:mongo, messages, _info, _ctx) do
    docs = Enum.map(messages, & &1.data)

    if Process.whereis(:mongo) do
      try do
        Mongo.insert_many(:mongo, @collection, docs)
      rescue
        e ->
          Logger.warning("[GameEvents] Mongo bulk insert failed: #{Exception.message(e)}")
      catch
        kind, reason ->
          Logger.warning("[GameEvents] Mongo bulk insert crashed: #{kind} #{inspect(reason)}")
      end
    end

    messages
  end
end
