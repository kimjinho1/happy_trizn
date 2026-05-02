defmodule HappyTrizn.Games.GameBehaviour do
  @moduledoc """
  모든 게임 모듈이 구현해야 하는 behaviour.

  Sprint 3 에서 Tetris/Bomberman/Skribbl/Snake.io/2048/Minesweeper/Pac-Man
  각각 이 인터페이스를 구현. 방마다 GenServer 1개가 spawn 되고 callback 들이
  state 를 관리.

  ## 호스트 disconnect 정책

  `handle_player_leave/3` 의 reason 으로 `:disconnect` / `:quit` / `:kick` 분기.
  게임별 정책:
  - Tetris 1v1: 남은 1명 자동 승리, GenServer terminate
  - Bomberman/Snake.io: 다음 join 순서 사람에게 호스트 권한 이전
  - Skribbl: 그리는 사람이면 다음 차례 즉시 진행
  - 싱글 게임 (2048/Minesweeper/Pac-Man): N/A
  """

  @type state :: map()
  @type player_id :: String.t()
  @type input :: map()
  @type broadcast :: list()

  @doc "방 시작 시 1회. config = name/max_players/seed 등."
  @callback init(config :: map()) :: {:ok, state()}

  @doc """
  플레이어 입력 처리. broadcast 는 PubSub 으로 다른 플레이어에게 전송할
  메시지 리스트.
  """
  @callback handle_input(player_id(), input(), state()) ::
              {:ok, state(), broadcast()}

  @doc "플레이어 입장. {:reject, reason} 으로 거부 가능 (방 가득참 등)."
  @callback handle_player_join(player_id(), meta :: map(), state()) ::
              {:ok, state(), broadcast()} | {:reject, atom()}

  @doc "플레이어 이탈. reason 따라 게임별 분기."
  @callback handle_player_leave(player_id(), :quit | :disconnect | :kick, state()) ::
              {:ok, state(), broadcast()}

  @doc "주기적 tick (실시간 게임용). 60fps 또는 게임별 간격."
  @callback tick(state()) :: {:ok, state(), broadcast()}

  @doc "게임 종료 조건 체크. {:yes, results} 면 GenServer terminate."
  @callback game_over?(state()) :: {:yes, results :: map()} | :no

  @doc "GenServer terminate 시 cleanup (영구 기록 저장 등)."
  @callback terminate(reason :: term(), state()) :: :ok

  @doc """
  게임 메타데이터. GameRegistry 가 부팅 시 수집하고 LobbyLive 가 게임 선택
  화면 만들 때 사용.

  필수 키:
  - `:name` — display 이름 (예: "Tetris")
  - `:slug` — 식별자 (예: "tetris", router/registry 사용)
  - `:mode` — `:multi` | `:single`
  - `:max_players` — 기본값 (방 생성 시 override 가능)
  - `:min_players` — 게임 시작 가능한 최소 인원 (멀티만)
  - `:description` — 한 줄 설명
  """
  @callback meta() :: %{
              required(:name) => String.t(),
              required(:slug) => String.t(),
              required(:mode) => :multi | :single,
              required(:max_players) => integer(),
              optional(:min_players) => integer(),
              optional(:description) => String.t(),
              optional(:tick_interval_ms) => non_neg_integer(),
              optional(:grace_period_ms) => non_neg_integer()
            }

  # 옵셔널 callback 들
  @optional_callbacks tick: 1, terminate: 2
end
