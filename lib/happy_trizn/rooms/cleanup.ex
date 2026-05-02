defmodule HappyTrizn.Rooms.Cleanup do
  @moduledoc """
  Orphan room sweeper (Sprint 4l).

  주기적으로 DB 의 open/playing 상태 방을 순회하면서 GameSession GenServer 가
  존재하지 않는 "버려진" 방을 강제 close.

  Orphan 발생 경로:
    - 호스트가 방 생성 후 게임방 진입 X (lobby 에서 그냥 떠남) — DB row 만 open,
      GameSession spawn 0
    - GameSession crash 후 close_by_id race / 일시 DB 오류로 status 갱신 실패
    - app 재배포 (운영 docker compose restart) 직후 — 모든 GameSession 메모리만
      살았다가 사라지지만 DB row 는 그대로 open

  Boot 시 1회 즉시 sweep + 이후 @sweep_interval_ms 주기 sweep.
  방 생성 직후 mount 까지 짧은 lag 견디기 위해 inserted_at 기준 @grace_seconds 미만
  방은 보존.
  """

  use GenServer

  require Logger

  alias HappyTrizn.Games.GameSession
  alias HappyTrizn.Rooms

  # 5분 주기.
  @default_sweep_interval_ms 5 * 60 * 1000
  # 방 생성 후 호스트 mount 시간 — 5분 안에 입장 안 하면 orphan.
  @default_grace_seconds 5 * 60

  # ============================================================================
  # Public API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "수동 sweep — 테스트 / admin 디버깅 용. {:closed_count, n} 반환."
  def sweep_now(opts \\ []) do
    GenServer.call(__MODULE__, {:sweep, opts}, 30_000)
  end

  # ============================================================================
  # GenServer callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval_ms, @default_sweep_interval_ms)
    grace_s = Keyword.get(opts, :grace_seconds, @default_grace_seconds)
    enabled = Keyword.get(opts, :enabled, true)

    state = %{interval_ms: interval, grace_seconds: grace_s, enabled: enabled}

    if enabled do
      # boot 직후 즉시 1회 sweep — 재배포 직후 stale rows 정리.
      send(self(), :sweep)
    end

    {:ok, state}
  end

  @impl true
  def handle_call({:sweep, opts}, _from, state) do
    grace_s = Keyword.get(opts, :grace_seconds, state.grace_seconds)
    closed = sweep_orphans(grace_s)
    {:reply, {:closed_count, closed}, state}
  end

  @impl true
  def handle_info(:sweep, state) do
    if state.enabled do
      _ = sweep_orphans(state.grace_seconds)
      Process.send_after(self(), :sweep, state.interval_ms)
    end

    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  # ============================================================================
  # Sweep logic
  # ============================================================================

  defp sweep_orphans(grace_seconds) do
    now = DateTime.utc_now()

    Rooms.list_alive()
    |> Enum.reduce(0, fn room, acc ->
      cond do
        # 1) GameSession 이 살아있으면 정상 — skip.
        GameSession.whereis_room(room.id) != nil ->
          acc

        # 2) 방 생성된 지 grace_seconds 초 미만 — 호스트 mount 시간 보장.
        DateTime.diff(now, room.inserted_at) < grace_seconds ->
          acc

        true ->
          case Rooms.close_by_id(room.id) do
            {:ok, _} ->
              Logger.info(
                "[rooms.cleanup] orphan room closed id=#{room.id} game_type=#{room.game_type} age_s=#{DateTime.diff(now, room.inserted_at)}"
              )

              acc + 1

            {:error, reason} ->
              Logger.warning(
                "[rooms.cleanup] failed to close orphan room id=#{room.id} reason=#{inspect(reason)}"
              )

              acc
          end
      end
    end)
  end
end
