defmodule HappyTriznWeb.GameMultiLive do
  @moduledoc """
  멀티 게임 진입점 — `/game/:game_type/:room_id`.

  - `Rooms.get!/1` 로 방 검증.
  - `GameSession.get_or_start_room/2` 로 GenServer 확보 후 player_join.
  - PubSub `game:<room_id>` subscribe → game_event 받아 socket assign 갱신.
  - keyboard input (Tetris): JS hook 이 phx-keyup → handle_event "input".
  - 화면 leave 시 `GameSession.player_leave/3` (LiveView terminate).
  """

  use HappyTriznWeb, :live_view

  require Logger
  alias HappyTrizn.Rooms
  alias HappyTrizn.Games.GameSession
  alias HappyTrizn.Games.Registry, as: GameRegistry
  alias HappyTrizn.UserGameSettings

  @impl true
  def mount(%{"game_type" => slug, "room_id" => room_id}, _session, socket) do
    nickname = socket.assigns[:current_nickname]
    user = socket.assigns[:current_user]

    Logger.info(
      "[game_multi] mount slug=#{slug} room=#{room_id} nickname=#{inspect(nickname)} user=#{inspect(user && user.id)}"
    )

    cond do
      is_nil(nickname) ->
        {:ok, socket |> put_flash(:error, "먼저 입장하세요.") |> redirect(to: ~p"/")}

      is_nil(user) ->
        {:ok, socket |> put_flash(:error, "게스트는 멀티 게임 입장 불가") |> redirect(to: ~p"/lobby")}

      not GameRegistry.valid_slug?(slug) ->
        {:ok, socket |> put_flash(:error, "없는 게임") |> redirect(to: ~p"/lobby")}

      true ->
        meta = GameRegistry.get_meta(slug)

        if meta.mode != :multi do
          {:ok,
           socket
           |> put_flash(:error, "이 게임은 싱글 — /play/#{slug}")
           |> redirect(to: ~p"/play/#{slug}")}
        else
          case Rooms.get(room_id) do
            nil ->
              {:ok, socket |> put_flash(:error, "방 없음") |> redirect(to: ~p"/lobby")}

            %{game_type: ^slug, status: status} = _room when status != "closed" ->
              # WebSocket connect 됐을 때만 GameSession 에 join — HTTP 첫 mount 는
              # 즉시 종료되는 임시 프로세스라 join → terminate → leave 사이클이 도는데,
              # 그 사이에 GameSession 이 player 0 명 → :stop 으로 종료돼버림 (호스트가
              # 만든 직후 다른 사용자가 들어오면 호스트가 안 보이는 원인).
              if connected?(socket) do
                join_connected(socket, slug, meta, room_id, nickname, user)
              else
                # HTTP 첫 mount — 화면 초기 렌더만, GameSession 건드리지 않음.
                # 실제 join 은 WS 가 붙은 후의 mount 에서.
                {:ok,
                 socket
                 |> assign(:slug, slug)
                 |> assign(:meta, meta)
                 |> assign(:room_id, room_id)
                 |> assign(:session_pid, nil)
                 |> assign(:player_id, socket.assigns.current_session.id)
                 |> assign(:nickname, nickname)
                 |> assign(:game_state, %{status: :waiting, players: %{}})
                 |> assign(:key_settings, UserGameSettings.get_for(user, slug))
                 |> assign(:settings_open, false)
                 |> assign(:result, nil)
                 |> assign(:joined, false)
                 |> assign(:game_messages, [])
                 |> assign(:page_title, meta.name)}
              end

            _ ->
              {:ok, socket |> put_flash(:error, "방 종료됨") |> redirect(to: ~p"/lobby")}
          end
        end
    end
  end

  defp join_connected(socket, slug, meta, room_id, nickname, user) do
    case GameSession.get_or_start_room(room_id, slug) do
      {:ok, pid} ->
        # player_id = session.id (각 브라우저/탭마다 별도 세션이라 같은 사용자가
        # 두 디바이스로 같은 방 들어와도 다른 player 로 인식. 사내 dev 테스트 시
        # 같은 계정 두 incognito 로 1v1 시뮬 가능).
        player_id = socket.assigns.current_session.id

        case GameSession.player_join(pid, player_id, %{
               nickname: nickname,
               user_id: user.id,
               avatar_url: user.avatar_url
             }) do
          :ok ->
            GameSession.subscribe_room(room_id)
            # 게임방 ephemeral chat — 방 단위 PubSub. 페이지 떠나면 history 휘발.
            # Skribbl 은 자체 추측/채팅 시스템 있어 별도 channel 안 씀.
            if slug in ["tetris", "bomberman", "snake_io"] do
              Phoenix.PubSub.subscribe(HappyTrizn.PubSub, "chat:game:" <> room_id)
            end

            key_settings = UserGameSettings.get_for(user, slug)
            initial_state = GameSession.get_state(pid)

            socket =
              socket
              |> assign(:slug, slug)
              |> assign(:meta, meta)
              |> assign(:room_id, room_id)
              |> assign(:session_pid, pid)
              |> assign(:player_id, player_id)
              |> assign(:nickname, nickname)
              |> assign(:game_state, initial_state)
              |> assign(:key_settings, key_settings)
              |> assign(:settings_open, false)
              |> assign(:result, nil)
              |> assign(:joined, true)
              |> assign(:game_messages, [])
              |> assign(:page_title, meta.name)

            # Skribbl 늦게 join 한 사람 — 현재까지 strokes 다시 그려야.
            socket =
              if slug == "skribbl" and is_list(Map.get(initial_state, :strokes)) do
                push_event(socket, "skribbl:strokes_replay", %{strokes: initial_state.strokes})
              else
                socket
              end

            {:ok, socket}

          {:reject, reason} ->
            {:ok, socket |> put_flash(:error, "입장 거부: #{reason}") |> redirect(to: ~p"/lobby")}
        end

      {:error, _} ->
        {:ok, socket |> put_flash(:error, "게임 세션 시작 실패") |> redirect(to: ~p"/lobby")}
    end
  end

  # ============================================================================
  # Input
  # ============================================================================

  @impl true
  def handle_event("input", payload, socket) do
    GameSession.handle_input(socket.assigns.session_pid, socket.assigns.player_id, payload)
    {:noreply, socket}
  end

  def handle_event("start_practice", _, socket) do
    GameSession.handle_input(socket.assigns.session_pid, socket.assigns.player_id, %{
      "action" => "start_practice"
    })

    {:noreply, socket}
  end

  def handle_event("restart", _, socket) do
    GameSession.handle_input(socket.assigns.session_pid, socket.assigns.player_id, %{
      "action" => "restart"
    })

    {:noreply, assign(socket, :result, nil)}
  end

  # ============================================================================
  # Skribbl events
  # ============================================================================

  def handle_event("skribbl_start_game", _, socket) do
    skribbl_input(socket, %{"action" => "start_game"})
    {:noreply, socket}
  end

  def handle_event("skribbl_choose_word", %{"word" => word}, socket) do
    skribbl_input(socket, %{"action" => "choose_word", "word" => word})
    {:noreply, socket}
  end

  def handle_event("skribbl_stroke", %{"stroke" => stroke}, socket) do
    skribbl_input(socket, %{"action" => "stroke", "stroke" => stroke})
    {:noreply, socket}
  end

  def handle_event("skribbl_clear", _, socket) do
    skribbl_input(socket, %{"action" => "clear_canvas"})
    {:noreply, socket}
  end

  def handle_event("skribbl_chat", %{"text" => text}, socket) do
    skribbl_input(socket, %{"action" => "guess", "text" => text})

    # 입력창 비움 — morphdom 은 typed input value 안 건드림. ChatReset hook 이 받음.
    {:noreply, push_event(socket, "chat:reset_input", %{})}
  end

  # ============================================================================
  # Bomberman events
  # ============================================================================

  def handle_event("bomberman_input", payload, socket) do
    GameSession.handle_input(socket.assigns.session_pid, socket.assigns.player_id, payload)
    {:noreply, socket}
  end

  def handle_event("bomberman_start", _, socket) do
    GameSession.handle_input(socket.assigns.session_pid, socket.assigns.player_id, %{
      "action" => "start_game"
    })

    {:noreply, socket}
  end

  # ============================================================================
  # Snake.io events
  # ============================================================================

  def handle_event("snake_set_dir", %{"dir" => dir}, socket) when is_binary(dir) do
    GameSession.handle_input(socket.assigns.session_pid, socket.assigns.player_id, %{
      "action" => "set_dir",
      "dir" => dir
    })

    {:noreply, socket}
  end

  # ============================================================================
  # 게임방 ephemeral chat (Tetris / Bomberman 전용 — Skribbl 은 자체 채팅).
  # PubSub 만 사용. 영속 X. 방 떠나면 history 휘발.
  # ============================================================================

  def handle_event("game_chat", %{"text" => text}, socket) when is_binary(text) do
    text = String.trim(text)

    if text == "" or socket.assigns.slug not in ["tetris", "bomberman", "snake_io"] do
      {:noreply, push_event(socket, "chat:reset_input", %{})}
    else
      # 너무 긴 메시지 차단 (200자).
      text = String.slice(text, 0, 200)

      msg = %{
        nickname: socket.assigns.nickname,
        player_id: socket.assigns.player_id,
        text: text,
        ts: System.system_time(:millisecond)
      }

      Phoenix.PubSub.broadcast(
        HappyTrizn.PubSub,
        "chat:game:" <> socket.assigns.room_id,
        {:game_chat, msg}
      )

      {:noreply, push_event(socket, "chat:reset_input", %{})}
    end
  end

  # ============================================================================
  # 옵션 모달 (game LiveView 그대로 유지, 새 페이지/탭 안 옮김)
  # ============================================================================

  def handle_event("open_settings", _, socket) do
    {:noreply, assign(socket, :settings_open, true)}
  end

  def handle_event("close_settings", _, socket) do
    {:noreply, assign(socket, :settings_open, false)}
  end

  def handle_event("modal_save_binding", %{"action" => action, "keys" => keys_str}, socket) do
    user = socket.assigns[:current_user]

    if is_nil(user) do
      {:noreply, put_flash(socket, :error, "게스트는 옵션 저장 불가")}
    else
      keys = UserGameSettings.parse_keys_input(keys_str)
      new_bindings = Map.put(socket.assigns.key_settings.bindings, action, keys)

      case UserGameSettings.upsert(user, socket.assigns.slug, %{
             key_bindings: new_bindings,
             options: socket.assigns.key_settings.options
           }) do
        {:ok, _} ->
          new_settings = UserGameSettings.get_for(user, socket.assigns.slug)

          # 단일 키 저장은 모달 안 닫음 — 사용자가 여러 액션 연속 저장 가능.
          {:noreply, socket |> assign(:key_settings, new_settings) |> put_flash(:info, "저장됨")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "저장 실패")}
      end
    end
  end

  def handle_event("modal_save_options", params, socket) do
    user = socket.assigns[:current_user]

    if is_nil(user) do
      {:noreply, put_flash(socket, :error, "게스트는 옵션 저장 불가")}
    else
      raw = Map.get(params, "options", %{})
      base = socket.assigns.key_settings.options

      new_options =
        Enum.reduce(raw, base, fn {k, v}, acc ->
          Map.put(acc, k, UserGameSettings.normalize_option_value(k, v))
        end)

      case UserGameSettings.upsert(user, socket.assigns.slug, %{
             key_bindings: socket.assigns.key_settings.bindings,
             options: new_options
           }) do
        {:ok, _} ->
          new_settings = UserGameSettings.get_for(user, socket.assigns.slug)

          {:noreply,
           socket
           |> assign(:key_settings, new_settings)
           |> assign(:settings_open, false)
           |> put_flash(:info, "저장됨")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "저장 실패")}
      end
    end
  end

  def handle_event("modal_reset", _, socket) do
    user = socket.assigns[:current_user]

    if is_nil(user) do
      {:noreply, put_flash(socket, :error, "게스트는 reset 불가")}
    else
      :ok = UserGameSettings.reset(user, socket.assigns.slug)
      new_settings = UserGameSettings.get_for(user, socket.assigns.slug)
      # reset 도 모달 유지 — 변경 사항 확인 후 사용자가 직접 닫음.
      {:noreply, socket |> assign(:key_settings, new_settings) |> put_flash(:info, "초기화 완료")}
    end
  end

  def handle_event("key", %{"key" => key}, socket) do
    if action = key_to_action(socket.assigns.slug, key) do
      GameSession.handle_input(socket.assigns.session_pid, socket.assigns.player_id, %{
        "action" => action
      })
    end

    {:noreply, socket}
  end

  defp skribbl_input(socket, payload) do
    GameSession.handle_input(socket.assigns.session_pid, socket.assigns.player_id, payload)
  end

  # Tetris 기본 키 바인딩 (server-side fallback — JS DAS/ARR 훅이 우선).
  # 사용자별 커스텀 바인딩은 user_game_settings 에 저장 후 JS hook 으로 주입.
  defp key_to_action("tetris", "ArrowLeft"), do: "left"
  defp key_to_action("tetris", "ArrowRight"), do: "right"
  defp key_to_action("tetris", "ArrowUp"), do: "rotate_cw"
  defp key_to_action("tetris", "ArrowDown"), do: "soft_drop"
  defp key_to_action("tetris", " "), do: "hard_drop"
  defp key_to_action("tetris", "Spacebar"), do: "hard_drop"
  defp key_to_action("tetris", "Space"), do: "hard_drop"
  defp key_to_action("tetris", "space"), do: "hard_drop"
  defp key_to_action("tetris", "z"), do: "rotate_ccw"
  defp key_to_action("tetris", "Z"), do: "rotate_ccw"
  defp key_to_action("tetris", "x"), do: "rotate_cw"
  defp key_to_action("tetris", "X"), do: "rotate_cw"
  defp key_to_action("tetris", "Control"), do: "rotate_ccw"
  defp key_to_action("tetris", "a"), do: "rotate_180"
  defp key_to_action("tetris", "A"), do: "rotate_180"
  defp key_to_action("tetris", "Shift"), do: "hold"
  defp key_to_action("tetris", "c"), do: "hold"
  defp key_to_action("tetris", "C"), do: "hold"
  defp key_to_action("tetris", "j"), do: "left"
  defp key_to_action("tetris", "l"), do: "right"
  defp key_to_action("tetris", "k"), do: "soft_drop"
  defp key_to_action("tetris", "i"), do: "rotate_cw"
  defp key_to_action(_, _), do: nil

  # ============================================================================
  # PubSub from GameSession
  # ============================================================================

  @impl true
  def handle_info({:game_event, {:player_state, pid, player_state}}, socket) do
    # payload 에 새 player state 포함 — GenServer.call(get_state) 안 해도 됨.
    # 매 50ms tick + 매 input 마다 GenServer call 하면 mailbox 폭주 → freeze.
    game_state = socket.assigns.game_state
    new_players = Map.put(game_state.players || %{}, pid, player_state)
    new_game_state = %{game_state | players: new_players}
    {:noreply, assign(socket, :game_state, new_game_state)}
  end

  def handle_info({:game_event, {:winner, w}}, socket) do
    new_socket = refresh_state(socket)
    {:noreply, assign(new_socket, result: %{winner: w})}
  end

  def handle_info({:game_event, {:game_over, results}}, socket) do
    socket = sfx(socket, sfx_for_game_over(results, socket.assigns.player_id))
    {:noreply, socket |> refresh_state() |> assign(result: results)}
  end

  def handle_info({:game_event, {:restart, _}}, socket) do
    # 라운드 시작 — result 클리어, 보드 갱신.
    {:noreply, socket |> refresh_state() |> assign(:result, nil)}
  end

  def handle_info({:game_event, {:top_out, pid}}, socket) do
    socket = if pid == socket.assigns.player_id, do: sfx(socket, "top_out"), else: socket
    {:noreply, refresh_state(socket)}
  end

  def handle_info({:game_event, {:line_clear, %{player: pid, lines: lines, b2b: b2b}}}, socket) do
    socket =
      cond do
        pid != socket.assigns.player_id -> socket
        b2b and lines >= 2 -> sfx(socket, "b2b")
        lines == 4 -> sfx(socket, "tetris")
        lines >= 1 -> sfx(socket, "line_clear")
        true -> socket
      end

    {:noreply, refresh_state(socket)}
  end

  def handle_info({:game_event, {:garbage_sent, %{to: to}}}, socket) do
    socket = if to == socket.assigns.player_id, do: sfx(socket, "garbage"), else: socket
    {:noreply, refresh_state(socket)}
  end

  def handle_info({:game_event, {:countdown_start, _}}, socket) do
    {:noreply, sfx(socket, "countdown") |> refresh_state()}
  end

  def handle_info({:game_event, {:countdown_tick, ms}}, socket) when is_integer(ms) do
    # 1초마다 (1000ms 경계) "초읽기" tick 사운드. 마지막 0 도달 시 game_over 가 :tetris.
    socket =
      cond do
        ms <= 0 -> socket
        rem(ms, 1000) == 0 -> sfx(socket, "countdown")
        true -> socket
      end

    {:noreply, refresh_state(socket)}
  end

  def handle_info({:game_event, {:rotated, pid}}, socket) do
    socket = if pid == socket.assigns.player_id, do: sfx(socket, "rotate"), else: socket
    {:noreply, refresh_state(socket)}
  end

  def handle_info({:game_event, {:locked, pid}}, socket) do
    socket = if pid == socket.assigns.player_id, do: sfx(socket, "lock"), else: socket
    {:noreply, refresh_state(socket)}
  end

  # ============================================================================
  # Skribbl events
  # ============================================================================

  def handle_info({:game_event, {:stroke, stroke}}, socket) do
    {:noreply, push_event(socket, "skribbl:stroke", stroke)}
  end

  def handle_info({:game_event, {:strokes_cleared, _}}, socket) do
    {:noreply, push_event(socket, "skribbl:clear", %{})}
  end

  def handle_info({:game_event, {:round_start, _}}, socket) do
    {:noreply, refresh_state(socket) |> push_event("skribbl:clear", %{})}
  end

  def handle_info({:game_event, {:word_chosen, _}}, socket) do
    {:noreply, refresh_state(socket)}
  end

  def handle_info({:game_event, {:word_choices, %{drawer: drawer, choices: choices}}}, socket) do
    # word_choices 는 drawer 만 보면 됨 — 모든 client refresh, render 가 drawer 일 때만 표시.
    socket =
      if drawer == socket.assigns.player_id do
        # 단어 선택 modal 즉시 보이게 — refresh + assign 처리.
        new_state =
          socket.assigns.game_state
          |> Map.put(:word_choices, choices)
          |> Map.put(:drawer_id, drawer)

        assign(socket, :game_state, new_state)
      else
        refresh_state(socket)
      end

    {:noreply, socket}
  end

  def handle_info({:game_event, {:correct_guess, _}}, socket) do
    {:noreply, refresh_state(socket)}
  end

  def handle_info({:game_event, {:round_end, _}}, socket) do
    {:noreply, refresh_state(socket)}
  end

  def handle_info({:game_event, {:tick, ms}}, socket) when is_integer(ms) do
    # time_left_ms 만 갱신 — get_state 안 함.
    new_state = Map.put(socket.assigns.game_state, :time_left_ms, ms)
    {:noreply, assign(socket, :game_state, new_state)}
  end

  def handle_info({:game_event, {:message, _}}, socket) do
    {:noreply, refresh_state(socket)}
  end

  def handle_info({:game_event, {:game_finished, _}}, socket) do
    {:noreply, refresh_state(socket)}
  end

  def handle_info({:game_event, {:player_joined, _}}, socket) do
    {:noreply, refresh_state(socket)}
  end

  def handle_info({:game_event, {:player_left, _}}, socket) do
    {:noreply, refresh_state(socket)}
  end

  def handle_info({:game_event, {:drawer_left, _}}, socket) do
    {:noreply, refresh_state(socket)}
  end

  # Snake.io 매 tick payload — GenServer.call 회피. canvas 라 DOM diff 부담 X.
  def handle_info({:game_event, {:snake_state, payload}}, socket) do
    new_state =
      socket.assigns.game_state
      |> Map.put(:players, payload.players)
      |> Map.put(:food, payload.food)
      |> Map.put(:tick_no, payload.tick_no)

    {:noreply, assign(socket, :game_state, new_state)}
  end

  def handle_info({:game_event, _other}, socket), do: {:noreply, refresh_state(socket)}

  # 게임방 채팅 — 최근 50개만 유지.
  def handle_info({:game_chat, msg}, socket) do
    msgs = [msg | socket.assigns[:game_messages] || []] |> Enum.take(50)

    {:noreply,
     socket
     |> assign(:game_messages, msgs)
     |> push_event("chat_message_added", %{})}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  defp sfx_for_game_over(%{winner: w}, me) when is_binary(w) and w == me, do: "tetris"
  defp sfx_for_game_over(_, _), do: "top_out"

  defp sfx(socket, event) when is_binary(event) do
    Phoenix.LiveView.push_event(socket, "tetris:sfx", %{event: event})
  end

  defp refresh_state(socket) do
    pid = socket.assigns[:session_pid]

    if pid && Process.alive?(pid) do
      try do
        # 5초 timeout — GenServer 가 다른 호출 처리 중이어도 LiveView 안 멈춤.
        assign(socket, game_state: GenServer.call(pid, :get_state, 5_000))
      catch
        :exit, _ ->
          # GameSession busy / dead — 기존 game_state 유지.
          socket
      end
    else
      socket
    end
  end

  # ============================================================================
  # Terminate (LiveView 떠날 때 player_leave)
  # ============================================================================

  @impl true
  def terminate(_reason, socket) do
    # joined: true 인 경우만 leave — HTTP 첫 mount 는 join 안 했으니 leave 도 안 함.
    if socket.assigns[:joined] && socket.assigns[:session_pid] do
      pid = socket.assigns.session_pid

      if Process.alive?(pid) do
        GameSession.player_leave(pid, socket.assigns.player_id, :disconnect)
      end
    end

    :ok
  end

  # ============================================================================
  # Render
  # ============================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={"game-multi-#{@slug}-#{@room_id}"}
      phx-hook={if @slug == "tetris", do: "TetrisInput", else: nil}
      phx-window-keyup={if @slug == "tetris", do: nil, else: "key"}
      data-das={@key_settings.das}
      data-arr={@key_settings.arr}
      data-key-bindings={Jason.encode!(@key_settings.bindings)}
      class="min-h-screen p-3 sm:p-6 max-w-6xl mx-auto"
    >
      <%= if @slug == "tetris" do %>
        <div
          id="tetris-sound"
          phx-hook="TetrisSound"
          data-sound-volume={@key_settings.options["sound_volume"] || 16}
          data-sound-rotate={to_string(@key_settings.options["sound_rotate"] != false)}
          data-sound-lock={to_string(@key_settings.options["sound_lock"] != false)}
          data-sound-line-clear={to_string(@key_settings.options["sound_line_clear"] != false)}
          data-sound-tetris={to_string(@key_settings.options["sound_tetris"] != false)}
          data-sound-b2b={to_string(@key_settings.options["sound_b2b"] != false)}
          data-sound-garbage={to_string(@key_settings.options["sound_garbage"] != false)}
          data-sound-top-out={to_string(@key_settings.options["sound_top_out"] != false)}
          data-sound-countdown={to_string(@key_settings.options["sound_countdown"] != false)}
          class="hidden"
        >
        </div>
      <% end %>
      <header class="flex items-center gap-3 mb-4 flex-wrap">
        <div>
          <h1 class="text-2xl font-bold">{@meta.name}</h1>
          <p class="text-xs text-base-content/60">방: <code>{@room_id}</code></p>
        </div>
        <button
          phx-click="open_settings"
          class="btn btn-ghost btn-sm"
          title="옵션 모달 — 게임 유지"
          type="button"
        >
          ⚙️ 옵션
        </button>
      </header>
      
    <!-- 공용 result panel 은 Tetris 전용 — Skribbl/Bomberman 은 자체 game_over_modal 사용 -->
      <%= if @result && @result != %{} && @slug == "tetris" do %>
        <.game_over_panel result={@result} player_id={@player_id} />
      <% end %>

      <%= if @slug == "tetris" do %>
        <.tetris_status_banner game_state={@game_state} player_id={@player_id} />
      <% end %>

      <.game_view
        slug={@slug}
        state={@game_state}
        player_id={@player_id}
        options={@key_settings.options}
        key_settings={@key_settings}
        nickname={@nickname}
        messages={@game_messages}
      />

      <div class="mt-4 text-xs text-base-content/50">
        <%= if @slug == "tetris" do %>
          키: ← → 이동, ↑/X 회전CW, Z/Ctrl 회전CCW, A 180회전, ↓ 소프트드롭, Space 하드드롭, Shift/C 홀드. 옵션에서 변경 가능.
        <% end %>
      </div>

      <%= if @settings_open do %>
        <.settings_modal slug={@slug} settings={@key_settings} />
      <% end %>
    </div>
    """
  end

  attr :slug, :string, required: true
  attr :settings, :map, required: true

  defp settings_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 z-40 flex items-center justify-center bg-black/50">
      <div
        id="settings-modal-box"
        class="bg-base-100 rounded-lg shadow-xl max-w-2xl w-full max-h-[90vh] overflow-y-auto p-6"
        phx-click-away="close_settings"
      >
        <header class="flex items-center justify-between mb-4">
          <h2 class="text-xl font-bold">⚙️ {String.upcase(@slug)} 옵션</h2>
          <button phx-click="close_settings" class="btn btn-sm btn-ghost" type="button">✕</button>
        </header>

        <p class="text-xs text-base-content/60 mb-4">
          저장 즉시 반영. 게임 그대로 진행 중.
        </p>

        <%= if map_size(@settings.bindings) > 0 do %>
          <section class="mb-6">
            <h3 class="font-semibold mb-2">키 바인딩</h3>
            <p class="text-xs text-base-content/60 mb-2">
              콤마(,)로 여러 키 등록. 예: <code>ArrowLeft, j</code>
            </p>
            <div class="space-y-2">
              <%= for action <- @settings.bindings |> Map.keys() |> Enum.sort() do %>
                <form phx-submit="modal_save_binding" class="flex items-center gap-2">
                  <label class="w-28 text-sm">{action}</label>
                  <input type="hidden" name="action" value={action} />
                  <input
                    type="text"
                    name="keys"
                    value={HappyTrizn.UserGameSettings.display_keys(@settings.bindings[action] || [])}
                    class="input input-bordered input-sm flex-1"
                  />
                  <button type="submit" class="btn btn-sm btn-primary">저장</button>
                </form>
              <% end %>
            </div>
          </section>
        <% end %>

        <%= if map_size(@settings.options) > 0 do %>
          <section class="mb-4">
            <h3 class="font-semibold mb-2">게임 설정</h3>
            <form phx-submit="modal_save_options" class="space-y-2">
              <%= for {k, v} <- @settings.options |> Enum.sort_by(&elem(&1, 0)) do %>
                <label class="flex items-center gap-2">
                  <span class="w-32 text-sm">{k}</span>
                  <%= cond do %>
                    <% is_boolean(v) -> %>
                      <input type="hidden" name={"options[#{k}]"} value="false" />
                      <input
                        type="checkbox"
                        name={"options[#{k}]"}
                        value="true"
                        checked={v}
                        class="checkbox checkbox-sm"
                      />
                    <% true -> %>
                      <input
                        type="text"
                        name={"options[#{k}]"}
                        value={to_string(v)}
                        class="input input-bordered input-sm flex-1"
                      />
                  <% end %>
                </label>
              <% end %>
              <div class="flex gap-2 pt-2">
                <button type="submit" class="btn btn-primary btn-sm">옵션 저장</button>
                <button
                  type="button"
                  phx-click="modal_reset"
                  class="btn btn-ghost btn-sm"
                  data-confirm="정말 초기화?"
                >
                  초기화
                </button>
              </div>
            </form>
          </section>
        <% end %>
      </div>
    </div>
    """
  end

  attr :game_state, :map, required: true
  attr :player_id, :string, required: true

  defp tetris_status_banner(assigns) do
    status = Map.get(assigns.game_state, :status)
    countdown = Map.get(assigns.game_state, :countdown_ms)
    me_alone? = map_size(assigns.game_state.players) == 1
    in_room? = Map.has_key?(assigns.game_state.players, assigns.player_id)

    assigns =
      assign(assigns,
        status: status,
        countdown: countdown,
        me_alone?: me_alone?,
        in_room?: in_room?
      )

    ~H"""
    <%= cond do %>
      <% @status == :countdown -> %>
        <div class="alert alert-warning mb-4 text-center text-2xl font-bold">
          시작까지 {countdown_seconds(@countdown)}…
        </div>
      <% @status == :waiting and @me_alone? and @in_room? -> %>
        <div class="alert alert-info mb-4 flex items-center justify-between">
          <span>혼자 있어요. 상대 기다리는 동안 연습하기 가능.</span>
          <button phx-click="start_practice" class="btn btn-sm btn-primary">🎯 스프린트 (연습)</button>
        </div>
      <% @status == :practice -> %>
        <div class="alert alert-success mb-4 text-sm">
          연습 중. 상대 입장 시 자동으로 멀티 게임 시작 (3-2-1 카운트다운).
        </div>
      <% true -> %>
        {[]}
    <% end %>
    """
  end

  defp countdown_seconds(ms) when is_integer(ms) and ms > 0, do: div(ms - 1, 1000) + 1
  defp countdown_seconds(_), do: 0

  defp game_view(%{slug: "tetris"} = assigns) do
    me_id = assigns.player_id
    state = assigns.state

    me = Map.get(state.players, me_id)

    opponents =
      state.players
      |> Enum.reject(fn {id, _} -> id == me_id end)
      |> Enum.sort_by(fn {id, _} -> id end)
      |> Enum.map(fn {_, p} -> p end)

    ghost? = Map.get(assigns.options, "ghost", true)
    grid = Map.get(assigns.options, "grid", "standard")
    skin = Map.get(assigns.options, "block_skin", "default_jstris")
    renderer = Map.get(assigns.options, "tetris_renderer", "dom")

    assigns =
      assign(assigns,
        me: me,
        opponents: opponents,
        ghost?: ghost?,
        grid: grid,
        skin: skin,
        renderer: renderer
      )

    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-[auto_1fr] gap-4">
      <!-- 왼쪽: 내 보드 (full size, w-fit — 콘텐츠 너비만큼만) -->
      <div class="w-fit">
        <h3 class="font-semibold mb-2">나 — {@nickname}</h3>
        <%= if @me do %>
          <div class="flex gap-2 items-start">
            <!-- 홀드 -->
            <div class="flex flex-col gap-2">
              <.piece_preview
                label="홀드"
                piece={@me.hold}
                dim={Map.get(@me, :hold_used, false)}
                skin={@skin}
              />
              <%= if Map.get(@me, :lock_delay_ms) do %>
                <div class="text-xs text-warning">잠금 {@me.lock_delay_ms}ms</div>
              <% end %>
            </div>
            <!-- 보드 — DOM 또는 Canvas (옵션) -->
            <%= if @renderer == "canvas" do %>
              <.tetris_canvas
                board={with_ghost_and_current(@me, @ghost?)}
                grid={@grid}
                pending={@me.pending_garbage}
                skin={@skin}
              />
            <% else %>
              <.tetris_board
                board={with_ghost_and_current(@me, @ghost?)}
                grid={@grid}
                pending={@me.pending_garbage}
                skin={@skin}
              />
            <% end %>
            <!-- 다음 큐 -->
            <.next_queue nexts={Map.get(@me, :nexts, [@me.next])} skin={@skin} />
          </div>
          <div class="text-sm mt-2 space-y-1">
            <div>점수: <strong>{@me.score}</strong></div>
            <div>라인: {@me.lines} · 레벨: {@me.level}</div>
            <div>
              받을 가비지:
              <span class={if @me.pending_garbage > 0, do: "text-error font-bold", else: ""}>
                {@me.pending_garbage}
              </span>
            </div>
            <!-- jstris 식 live HUD — PPS / APM / VS / KPP / pieces. -->
            <div class="grid grid-cols-3 gap-1 text-xs bg-base-200 p-2 rounded mt-2">
              <div class="text-center" title="Pieces Per Second">
                <div class="text-base-content/60">PPS</div>
                <div class="font-bold text-base">{Map.get(@me, :pps, 0.0)}</div>
              </div>
              <div class="text-center" title="Attack Per Minute">
                <div class="text-base-content/60">APM</div>
                <div class="font-bold text-base">{Map.get(@me, :apm, 0.0)}</div>
              </div>
              <div class="text-center" title="VS = APM + PPS×100">
                <div class="text-base-content/60">VS</div>
                <div class="font-bold text-base">{Map.get(@me, :vs, 0.0)}</div>
              </div>
              <div class="text-center" title="Keys Per Piece">
                <div class="text-base-content/60">KPP</div>
                <div class="font-bold">{Map.get(@me, :kpp, 0.0)}</div>
              </div>
              <div class="text-center" title="Pieces Placed">
                <div class="text-base-content/60">조각</div>
                <div class="font-bold">{Map.get(@me, :pieces_placed, 0)}</div>
              </div>
              <div class="text-center" title="Garbage Sent">
                <div class="text-base-content/60">보냄</div>
                <div class="font-bold">{Map.get(@me, :garbage_sent, 0)}</div>
              </div>
            </div>
            <div class="flex gap-2 flex-wrap">
              <%= if Map.get(@me, :combo, -1) >= 1 do %>
                <span class="badge badge-warning">콤보 ×{@me.combo}</span>
              <% end %>
              <%= if Map.get(@me, :b2b, false) do %>
                <span class="badge badge-info">B2B</span>
              <% end %>
              <%= if Map.get(@me, :finesse_violations, 0) > 0 do %>
                <span class="badge badge-error" title="불필요 입력 횟수 (낮을수록 효율적)">
                  Finesse −{@me.finesse_violations}
                </span>
              <% end %>
            </div>
            <%= if @me.top_out do %>
              <div class="text-error font-bold">탑아웃</div>
            <% end %>
          </div>
        <% else %>
          <div class="text-base-content/40">로딩...</div>
        <% end %>
      </div>

      <!-- 오른쪽: 상대 mini boards (위) + chat (아래) -->
      <div class="flex flex-col gap-3 min-w-0">
        <div>
          <h3 class="font-semibold mb-2 text-sm">
            상대 ({length(@opponents)}명)
          </h3>
          <%= if @opponents == [] do %>
            <div class="text-xs text-base-content/40 bg-base-200 rounded p-3">
              상대방 대기 중...
            </div>
          <% else %>
            <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-2">
              <%= for op <- @opponents do %>
                <.tetris_mini_board player={op} />
              <% end %>
            </div>
          <% end %>
        </div>

        <.game_room_chat messages={@messages} />
      </div>
    </div>
    """
  end

  # ===========================================================================
  # 상대 mini board — 10×20 board only, w-1.5 cells (~120px wide).
  # nickname overlay + top_out 시 X overlay.
  # ===========================================================================

  attr :player, :map, required: true

  defp tetris_mini_board(assigns) do
    visible =
      with_ghost_and_current(assigns.player, false)
      |> Enum.drop(2)
      |> Enum.take(20)

    pending = min(Map.get(assigns.player, :pending_garbage, 0), 20)
    nickname = Map.get(assigns.player, :nickname, "anon")
    top_out? = Map.get(assigns.player, :top_out, false)

    assigns =
      assign(assigns, visible: visible, pending: pending, nickname: nickname, top_out?: top_out?)

    ~H"""
    <div class="bg-base-200 rounded p-1 relative">
      <div class="text-xs font-semibold truncate text-center mb-1" title={@nickname}>
        {@nickname}
      </div>
      <div class="inline-flex bg-base-300 p-px gap-px relative justify-center">
        <!-- pending garbage bar — pending 있을 때만 -->
        <%= if @pending > 0 do %>
          <div class="flex flex-col-reverse w-1.5 bg-base-100 overflow-hidden">
            <%= for _ <- 1..@pending//1 do %>
              <div class="h-3 bg-error"></div>
            <% end %>
          </div>
        <% end %>
        <div>
          <%= for row <- @visible do %>
            <div class="flex">
              <%= for cell <- row do %>
                <div class={[
                  "w-3 h-3 border border-base-content/5",
                  cell_color(cell),
                  if(cell != nil, do: "tetris-filled-mini")
                ]}>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
        <%= if @top_out? do %>
          <div class="absolute inset-0 bg-base-300/80 flex items-center justify-center text-error font-bold text-2xl">
            ✕
          </div>
        <% end %>
      </div>
      <div class="text-[10px] text-center text-base-content/60 mt-1">
        {@player.score} pts · L{@player.lines}
      </div>
    </div>
    """
  end

  defp game_view(%{slug: "skribbl"} = assigns) do
    state = ensure_skribbl_state(assigns.state)
    me_id = assigns.player_id
    is_drawer? = state.drawer_id == me_id
    word_choices = if state.status == :choosing, do: Map.get(state, :word_choices, []), else: []
    me = Map.get(state.players, me_id) || %{}
    can_chat? = state.status not in [:waiting, :over] and is_nil(Map.get(me, :guessed_at))

    assigns =
      assign(assigns,
        state: state,
        is_drawer?: is_drawer?,
        word_choices: word_choices,
        me: me,
        can_chat?: can_chat?
      )

    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-[1fr_280px] gap-4">
      <div class="space-y-3">
        <.skribbl_status state={@state} is_drawer?={@is_drawer?} player_id={@player_id} />

        <div class="relative bg-base-200 rounded p-2">
          <canvas
            id="skribbl-canvas"
            phx-hook="SkribblCanvas"
            data-is-drawer={to_string(@is_drawer?)}
            width="800"
            height="500"
            class="w-full bg-white rounded shadow"
          >
          </canvas>

          <%= if @is_drawer? and @state.status == :drawing do %>
            <.skribbl_tools />
          <% end %>

          <%= if @state.status == :choosing and @is_drawer? do %>
            <.skribbl_word_chooser choices={@word_choices} />
          <% end %>
        </div>
      </div>

      <aside class="space-y-3">
        <.skribbl_scoreboard players={@state.players} drawer={@state.drawer_id} />
        <.skribbl_chat
          messages={Map.get(@state, :messages, [])}
          can_chat?={@can_chat?}
          status={@state.status}
        />
      </aside>
    </div>

    <%= if @state.status == :round_end do %>
      <.skribbl_round_end_modal state={@state} />
    <% end %>

    <%= if @state.status == :over do %>
      <.skribbl_game_over_modal state={@state} player_id={@player_id} />
    <% end %>
    """
  end

  defp game_view(%{slug: "bomberman"} = assigns) do
    state = ensure_bomberman_state(assigns.state)
    me_id = assigns.player_id
    me = Map.get(state.players, me_id) || %{}
    bindings = assigns.key_settings.bindings || %{}

    assigns = assign(assigns, state: state, me: me, bindings: bindings)

    ~H"""
    <div
      id="bomberman-input-host"
      phx-hook="BombermanInput"
      data-key-bindings={Jason.encode!(@bindings)}
      tabindex="0"
      class="outline-none"
    >
      <div class="grid grid-cols-1 lg:grid-cols-[1fr_260px] gap-4 lg:items-stretch">
        <div>
          <.bomberman_status state={@state} me={@me} />
          <.bomberman_grid state={@state} player_id={@player_id} />
        </div>

        <aside class="flex flex-col gap-3 min-h-0">
          <.bomberman_scoreboard players={@state.players} />
          <div class="bg-base-200 rounded p-3 text-xs space-y-1 shrink-0">
            <div class="font-semibold">조작</div>
            <div>이동: ← → ↑ ↓ / WASD</div>
            <div>폭탄: Space</div>
          </div>
          <.game_room_chat messages={@messages} height_class="flex-1 min-h-0" />
        </aside>
      </div>

      <%= if @state.status == :over do %>
        <.bomberman_game_over_modal state={@state} player_id={@player_id} />
      <% end %>
    </div>
    """
  end

  defp game_view(%{slug: "snake_io"} = assigns) do
    state = ensure_snake_state(assigns.state)
    me_id = assigns.player_id
    me = Map.get(state.players, me_id) || %{}
    bindings = assigns.key_settings.bindings || %{}
    grid_size = HappyTrizn.Games.SnakeIo.grid_size()

    # canvas 에 그릴 가벼운 payload — body 좌표 array, color, alive.
    # Jason 은 tuple 인코딩 불가 → {r,c} → [r,c] 로 변환.
    snakes_payload =
      Enum.map(state.players, fn {id, p} ->
        %{
          id: id,
          color: p.color,
          alive: p.alive,
          body: Enum.map(p.body, fn {r, c} -> [r, c] end),
          is_me: id == me_id
        }
      end)

    food_payload =
      state.food
      |> MapSet.to_list()
      |> Enum.map(fn {r, c} -> [r, c] end)

    assigns =
      assign(assigns,
        state: state,
        me: me,
        bindings: bindings,
        grid_size: grid_size,
        snakes_payload: snakes_payload,
        food_payload: food_payload
      )

    ~H"""
    <div
      id="snake-input-host"
      phx-hook="SnakeInput"
      data-key-bindings={Jason.encode!(@bindings)}
      tabindex="0"
      class="outline-none"
    >
      <div class="grid grid-cols-1 lg:grid-cols-[auto_260px] gap-4 justify-start">
        <div>
          <.snake_status state={@state} me={@me} />
          <div
            id="snake-canvas-host"
            phx-hook="SnakeCanvas"
            data-grid-size={@grid_size}
            data-tick-ms="80"
            data-snakes={Jason.encode!(@snakes_payload)}
            data-food={Jason.encode!(@food_payload)}
            data-me-id={@player_id}
            class="bg-slate-900 rounded-xl shadow-2xl ring-2 ring-slate-700 p-1 inline-block max-w-full"
          >
            <canvas
              id="snake-canvas"
              width="640"
              height="640"
              class="block max-w-full h-auto"
            >
            </canvas>
          </div>
        </div>

        <aside class="space-y-3">
          <.snake_scoreboard players={@state.players} player_id={@player_id} />
          <div class="bg-base-200 rounded p-3 text-xs space-y-1">
            <div class="font-semibold">조작</div>
            <div>방향: ← → ↑ ↓ / WASD</div>
            <div>180° 반대 방향 무시</div>
            <div>사망 시 3초 후 자동 부활</div>
          </div>
          <.game_room_chat messages={@messages} />
        </aside>
      </div>
    </div>
    """
  end

  defp game_view(assigns) do
    ~H"""
    <div class="card bg-base-200">
      <div class="card-body">
        <h3 class="card-title">{@slug}</h3>
        <p class="text-sm">이 게임은 Sprint 3 진행 중. 풀 구현 예정.</p>
        <pre class="text-xs bg-base-100 p-2 rounded overflow-auto max-h-64">{inspect(@state, pretty: true, limit: 50)}</pre>
      </div>
    </div>
    """
  end

  # ============================================================================
  # 게임방 ephemeral chat 패널 — Tetris / Bomberman 공용. 방 안에서만 살아있음.
  # ============================================================================

  attr :messages, :list, required: true

  attr :height_class, :string,
    default: "h-[280px]",
    doc:
      "채팅 패널 height. 기본 280px. Bomberman 처럼 게임 grid 가 큰 경우 'flex-1 min-h-0' 전달해서 sidebar 남은 height 꽉 차게."

  defp game_room_chat(assigns) do
    ~H"""
    <div class={["bg-base-200 rounded-lg flex flex-col", @height_class]}>
      <header class="px-3 py-2 border-b border-base-300 text-sm font-semibold flex items-center gap-2">
        💬 <span>게임방 채팅</span>
        <span class="text-xs font-normal text-base-content/50">방 닫히면 사라짐</span>
      </header>

      <div
        id="game-chat-scroll"
        phx-hook="ChatScroll"
        class="flex-1 min-h-0 overflow-y-auto px-3 py-2 flex flex-col-reverse gap-1 text-sm"
      >
        <%= if @messages == [] do %>
          <div class="text-xs text-base-content/40 text-center my-auto">아직 메시지 없음</div>
        <% else %>
          <%= for m <- @messages do %>
            <div class="leading-tight">
              <span class="font-semibold text-primary">{m.nickname}</span>
              <span class="text-base-content/50">:</span>
              <span class="break-words">{m.text}</span>
            </div>
          <% end %>
        <% end %>
      </div>

      <form
        id="game-chat-form"
        phx-submit="game_chat"
        phx-hook="ChatReset"
        class="border-t border-base-300 p-2 flex gap-1"
      >
        <input
          type="text"
          name="text"
          autocomplete="off"
          maxlength="200"
          placeholder="메시지..."
          class="input input-sm input-bordered flex-1"
        />
        <button type="submit" class="btn btn-sm btn-primary">전송</button>
      </form>
    </div>
    """
  end

  # ============================================================================
  # Snake.io UI helpers
  # ============================================================================

  defp ensure_snake_state(state) do
    state
    |> Map.put_new(:status, :playing)
    |> Map.put_new(:players, %{})
    |> Map.put_new(:food, MapSet.new())
    |> Map.put_new(:tick_no, 0)
    |> Map.put_new(:grid_size, HappyTrizn.Games.SnakeIo.grid_size())
  end

  attr :state, :map, required: true
  attr :me, :map, required: true

  defp snake_status(assigns) do
    ~H"""
    <div class="bg-base-200 rounded p-3 mb-3 flex items-center justify-between flex-wrap gap-2">
      <div class="flex items-center gap-3">
        <span class="badge badge-success">진행 중 (캐주얼)</span>
        <span class="text-sm">참가자 {map_size(@state.players)} / 16</span>
      </div>
      <%= if Map.get(@me, :alive) do %>
        <div class="flex items-center gap-2 text-sm">
          <span
            class="inline-block w-3 h-3 rounded"
            style={"background: #{Map.get(@me, :color, "#888")}"}
          >
          </span>
          <span>길이 {length(Map.get(@me, :body, []))}</span>
          <span>최고 {Map.get(@me, :best_length, 0)}</span>
          <span>kill {Map.get(@me, :kills, 0)}</span>
        </div>
      <% else %>
        <%= if Map.get(@me, :died_at_tick) do %>
          <span class="badge badge-error">사망 — 3초 후 부활</span>
        <% else %>
          <span class="badge">대기</span>
        <% end %>
      <% end %>
    </div>
    """
  end

  attr :players, :map, required: true
  attr :player_id, :string, required: true

  defp snake_scoreboard(assigns) do
    sorted =
      assigns.players
      |> Enum.sort_by(fn {_, p} -> -Map.get(p, :best_length, 0) end)

    assigns = assign(assigns, sorted: sorted)

    ~H"""
    <div class="bg-base-200 rounded p-3">
      <h3 class="font-semibold mb-2 text-sm">리더보드 (최대 길이)</h3>
      <ul class="space-y-1 text-sm max-h-72 overflow-y-auto">
        <%= for {id, p} <- @sorted do %>
          <li class={[
            "flex items-center justify-between gap-2",
            id == @player_id && "font-bold"
          ]}>
            <span class="flex items-center gap-2 truncate">
              <span class="inline-block w-3 h-3 rounded shrink-0" style={"background: #{p.color}"}>
              </span>
              <span class="truncate">{p.nickname}</span>
            </span>
            <span class="text-xs text-base-content/60">{p.best_length}</span>
          </li>
        <% end %>
      </ul>
    </div>
    """
  end

  # Bomberman placeholder state 보강 — HTTP 첫 mount 안전.
  defp ensure_bomberman_state(state) do
    state
    |> Map.put_new(:status, :waiting)
    |> Map.put_new(:players, %{})
    |> Map.put_new(:grid, [])
    |> Map.put_new(:bombs, %{})
    |> Map.put_new(:explosions, [])
    |> Map.put_new(:items, %{})
    |> Map.put_new(:winner_id, nil)
  end

  attr :state, :map, required: true
  attr :me, :map, required: true

  defp bomberman_status(assigns) do
    ~H"""
    <div class="bg-base-200 rounded p-3 mb-3 flex items-center justify-between">
      <div>
        <%= case @state.status do %>
          <% :waiting -> %>
            <span class="text-sm">대기 중 — 2명 이상 시 시작 가능</span>
            <%= if map_size(@state.players) >= 2 do %>
              <button phx-click="bomberman_start" class="btn btn-primary btn-sm ml-3">💣 시작</button>
            <% end %>
          <% :playing -> %>
            <span class="text-sm font-semibold">게임 중</span>
          <% :over -> %>
            <span class="text-sm">게임 종료</span>
        <% end %>
      </div>
      <%= if Map.get(@me, :alive) do %>
        <div class="text-xs space-x-3">
          <span>💣 {Map.get(@me, :bomb_max, 1)}</span>
          <span>🔥 {Map.get(@me, :bomb_range, 2)}</span>
          {if Map.get(@me, :kick?), do: "🦵"}
        </div>
      <% else %>
        <%= if @state.status == :playing do %>
          <span class="badge badge-error">사망</span>
        <% end %>
      <% end %>
    </div>
    """
  end

  attr :state, :map, required: true
  attr :player_id, :string, required: true

  defp bomberman_grid(assigns) do
    rows = HappyTrizn.Games.Bomberman.rows()
    cols = HappyTrizn.Games.Bomberman.cols()
    grid = assigns.state.grid

    explosion_set =
      assigns.state.explosions
      |> Enum.flat_map(fn e -> e.cells end)
      |> MapSet.new()

    # 안정적 player index — sorted player_id 기준.
    player_index =
      assigns.state.players
      |> Map.keys()
      |> Enum.sort()
      |> Enum.with_index()
      |> Map.new()

    assigns =
      assign(assigns,
        rows: rows,
        cols: cols,
        grid: grid,
        explosion_set: explosion_set,
        player_index: player_index
      )

    ~H"""
    <div class="inline-block bg-gradient-to-br from-slate-800 to-slate-900 p-2 rounded-xl shadow-2xl ring-2 ring-slate-700">
      <%= for r <- 0..(@rows - 1) do %>
        <div class="flex">
          <%= for c <- 0..(@cols - 1) do %>
            <div class={[
              "w-7 h-7 sm:w-12 sm:h-12 flex items-center justify-center text-base sm:text-2xl transition-all",
              bomberman_cell_class(@grid, r, c, @explosion_set)
            ]}>
              {Phoenix.HTML.raw(bomberman_cell_content(@state, r, c, @player_index))}
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp bomberman_cell_class(grid, r, c, explosion_set) do
    base = bomberman_terrain_class(Enum.at(Enum.at(grid, r) || [], c))

    if MapSet.member?(explosion_set, {r, c}),
      do:
        "bg-gradient-to-br from-orange-400 via-red-500 to-yellow-300 animate-pulse shadow-lg shadow-red-500/50",
      else: base
  end

  defp bomberman_terrain_class(:wall),
    do: "bg-gradient-to-br from-slate-600 to-slate-800 border border-slate-900 shadow-inner"

  defp bomberman_terrain_class(:block),
    do: "bg-gradient-to-br from-amber-600 to-amber-800 border border-amber-950 shadow-md"

  defp bomberman_terrain_class(:empty),
    do: "bg-gradient-to-br from-emerald-900/40 to-slate-900/40 border border-slate-700/50"

  defp bomberman_terrain_class(_), do: "bg-base-100"

  defp bomberman_cell_content(state, r, c, player_index) do
    cond do
      bomb = Map.get(state.bombs, {r, c}) ->
        bomb_visual(bomb)

      item = Map.get(state.items, {r, c}) ->
        item_visual(item)

      pair = bomberman_player_pair_at(state, r, c) ->
        {pid, p} = pair
        player_visual(p, Map.get(player_index, pid, 0))

      true ->
        ""
    end
  end

  defp bomberman_player_pair_at(state, r, c) do
    state.players
    |> Enum.find(fn {_, p} -> p.alive and p.row == r and p.col == c end)
  end

  # 폭탄 — fuse 가까울 수록 빠르게 깜빡.
  defp bomb_visual(bomb) do
    pulse =
      cond do
        bomb.fuse_ms < 1000 -> "animate-bounce"
        bomb.fuse_ms < 2000 -> "animate-pulse"
        true -> ""
      end

    ~s|<span class="#{pulse} drop-shadow-[0_0_6px_rgba(255,80,80,0.9)]">💣</span>|
  end

  # 아이템 — 둥둥 떠다니는 효과 + 색 별 글로우.
  defp item_visual(:bomb_up),
    do: ~s|<span class="animate-bounce drop-shadow-[0_0_8px_rgba(239,68,68,0.9)]">💥</span>|

  defp item_visual(:range_up),
    do: ~s|<span class="animate-bounce drop-shadow-[0_0_8px_rgba(251,146,60,0.9)]">🔥</span>|

  defp item_visual(:speed_up),
    do: ~s|<span class="animate-bounce drop-shadow-[0_0_8px_rgba(34,197,94,0.9)]">⚡</span>|

  defp item_visual(:kick),
    do: ~s|<span class="animate-bounce drop-shadow-[0_0_8px_rgba(168,85,247,0.9)]">🦵</span>|

  defp item_visual(_),
    do: ~s|<span>?</span>|

  # Player — 인덱스별 다른 아바타 + 컬러 ring.
  @player_avatars {"🤺", "🦸", "🥷", "🧙"}
  @player_rings {
    "ring-2 ring-red-400 drop-shadow-[0_0_6px_rgba(248,113,113,0.9)]",
    "ring-2 ring-blue-400 drop-shadow-[0_0_6px_rgba(96,165,250,0.9)]",
    "ring-2 ring-emerald-400 drop-shadow-[0_0_6px_rgba(52,211,153,0.9)]",
    "ring-2 ring-yellow-400 drop-shadow-[0_0_6px_rgba(250,204,21,0.9)]"
  }

  defp player_visual(p, idx) do
    ring = elem(@player_rings, rem(idx, 4))
    avatar_url = Map.get(p, :avatar_url)

    if is_binary(avatar_url) and avatar_url != "" do
      # 사용자 업로드 사진 — 둥글게 자른 img.
      ~s|<img src="#{avatar_url}" alt="" class="w-9 h-9 rounded-full object-cover #{ring}" />|
    else
      # fallback — 인덱스별 emoji.
      avatar = elem(@player_avatars, rem(idx, 4))

      ~s|<span class="inline-flex items-center justify-center w-9 h-9 rounded-full bg-base-100/80 #{ring}">#{avatar}</span>|
    end
  end

  attr :players, :map, required: true

  defp bomberman_scoreboard(assigns) do
    sorted = assigns.players |> Enum.sort_by(fn {_, p} -> not p.alive end)
    assigns = assign(assigns, sorted: sorted)

    ~H"""
    <div class="bg-base-200 rounded p-3">
      <h3 class="font-semibold mb-2 text-sm">참가자</h3>
      <ul class="space-y-1 text-sm">
        <%= for {_, p} <- @sorted do %>
          <li class="flex items-center justify-between">
            <span class="font-mono">{p.nickname}</span>
            <span>
              <%= if p.alive do %>
                <span class="badge badge-success badge-xs">생존</span>
              <% else %>
                <span class="badge badge-error badge-xs">탈락</span>
              <% end %>
            </span>
          </li>
        <% end %>
      </ul>
    </div>
    """
  end

  attr :state, :map, required: true
  attr :player_id, :string, required: true

  defp bomberman_game_over_modal(assigns) do
    winner_id = assigns.state.winner_id
    winner = winner_id && Map.get(assigns.state.players, winner_id)
    me_won? = winner_id == assigns.player_id

    # Bomberman.bomberman_ranking 와 같은 로직 — game_view 에는 raw state 만 있음.
    ranking =
      assigns.state.players
      |> Enum.map(fn {id, p} ->
        %{
          player_id: id,
          nickname: Map.get(p, :nickname, "anon"),
          alive: p.alive,
          dead_at: Map.get(p, :dead_at),
          is_winner: id == winner_id
        }
      end)
      |> Enum.sort_by(fn e ->
        cond do
          e.is_winner -> {0, 0}
          e.alive -> {1, 0}
          is_nil(e.dead_at) -> {2, 0}
          true -> {3, -e.dead_at}
        end
      end)
      |> Enum.with_index(1)
      |> Enum.map(fn {e, rank} -> Map.put(e, :rank, rank) end)

    assigns = assign(assigns, winner: winner, me_won?: me_won?, ranking: ranking)

    ~H"""
    <div class="fixed inset-0 z-40 flex items-center justify-center bg-black/60 p-4">
      <div class={[
        "rounded-xl shadow-2xl max-w-md w-full p-6 border-4",
        if(@me_won?, do: "bg-success/30 border-success", else: "bg-base-100 border-base-300")
      ]}>
        <div class="text-center mb-4">
          <div class="text-5xl mb-2">{if @me_won?, do: "🏆", else: "💥"}</div>
          <div class="text-2xl font-bold">
            <%= cond do %>
              <% @me_won? -> %>
                승리!
              <% @winner -> %>
                {@winner.nickname} 우승
              <% true -> %>
                무승부
            <% end %>
          </div>
        </div>

        <%= if @ranking != [] do %>
          <div class="mb-4">
            <div class="font-semibold text-base-content/70 mb-2 text-center">최종 순위</div>
            <div class="space-y-1 text-sm">
              <%= for entry <- @ranking do %>
                <div class={[
                  "flex items-center gap-2 px-3 py-1.5 rounded",
                  entry.player_id == @player_id && "bg-primary/20 ring-1 ring-primary",
                  entry.player_id != @player_id && "bg-base-200"
                ]}>
                  <span class="font-bold w-6 text-center">
                    {rank_emoji(entry.rank)}
                  </span>
                  <span class="flex-1 truncate font-medium">{entry.nickname}</span>
                  <span class="text-xs text-base-content/60">
                    {if entry.alive, do: "생존", else: "💥"}
                  </span>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>

        <button phx-click="bomberman_start" class="btn btn-primary w-full">
          🔄 다시 하기
        </button>
      </div>
    </div>
    """
  end

  attr :state, :map, required: true
  attr :is_drawer?, :boolean, required: true
  attr :player_id, :string, required: true

  defp skribbl_status(assigns) do
    seconds = max(div(Map.get(assigns.state, :time_left_ms, 0) || 0, 1000), 0)
    drawer = Map.get(assigns.state.players, assigns.state.drawer_id) || %{}
    drawer_nick = Map.get(drawer, :nickname, "—")

    word_display =
      cond do
        assigns.state.status in [:drawing] and assigns.is_drawer? -> assigns.state.word
        assigns.state.status in [:drawing] -> word_blanks(assigns.state.word)
        assigns.state.status == :round_end -> "정답: #{assigns.state.word}"
        true -> nil
      end

    assigns =
      assign(assigns, seconds: seconds, drawer_nick: drawer_nick, word_display: word_display)

    ~H"""
    <div class="flex items-center justify-between bg-base-200 rounded p-3">
      <div>
        <div class="text-xs text-base-content/60">
          상태 · 라운드 {Map.get(@state, :round_no, 0)} / {HappyTrizn.Games.Skribbl.total_rounds()}
        </div>
        <div class="font-semibold">
          <%= case @state.status do %>
            <% :waiting -> %>
              대기 중 — 2명 이상 시 시작 가능
            <% :choosing -> %>
              {@drawer_nick} 가 단어 고르는 중
            <% :drawing -> %>
              {@drawer_nick} 그리는 중
            <% :round_end -> %>
              라운드 종료
            <% :over -> %>
              게임 종료
          <% end %>
        </div>
      </div>

      <%= if @word_display do %>
        <div class="text-center">
          <div class="text-xs text-base-content/60">단어</div>
          <div class="font-mono text-lg tracking-widest">{@word_display}</div>
        </div>
      <% end %>

      <div class="text-right">
        <div class="text-xs text-base-content/60">남은 시간</div>
        <div class={["font-bold text-lg", @seconds <= 10 && "text-error"]}>
          {@seconds}초
        </div>
      </div>
    </div>

    <div class="flex items-center justify-between gap-3">
      <p class="text-xs text-base-content/50 italic">
        💡 점수: 빨리 맞출수록 50~150점, 그림 그린 사람도 맞춘 사람당 +50점.
        총 {HappyTrizn.Games.Skribbl.total_rounds()} 라운드.
      </p>

      <%= if @state.status in [:waiting, :over] and map_size(@state.players) >= 2 do %>
        <button phx-click="skribbl_start_game" class="btn btn-primary btn-sm">
          🎨 게임 시작
        </button>
      <% end %>
    </div>
    """
  end

  defp skribbl_tools(assigns) do
    colors = ~w(#000000 #ff4444 #4488ff #44cc44 #ffaa22 #aa55ff #ffffff)
    sizes = [2, 4, 8, 14]
    assigns = assign(assigns, colors: colors, sizes: sizes)

    ~H"""
    <div class="absolute top-2 left-2 bg-base-100 rounded shadow p-1 flex gap-1">
      <%= for c <- @colors do %>
        <button
          type="button"
          data-skribbl-color={c}
          class="w-6 h-6 rounded border border-base-content/30"
          style={"background-color: #{c}"}
        >
        </button>
      <% end %>
      <span class="border-l border-base-300 mx-1"></span>
      <%= for s <- @sizes do %>
        <button type="button" data-skribbl-size={s} class="btn btn-xs btn-ghost">
          {s}
        </button>
      <% end %>
      <button type="button" phx-click="skribbl_clear" class="btn btn-xs btn-ghost ml-1">
        🗑️
      </button>
    </div>
    """
  end

  attr :choices, :list, required: true

  defp skribbl_word_chooser(assigns) do
    ~H"""
    <div class="absolute inset-0 flex items-center justify-center bg-black/50 rounded">
      <div class="bg-base-100 rounded-lg shadow-xl p-6 max-w-md w-full">
        <h3 class="text-lg font-bold mb-3">단어 선택</h3>
        <p class="text-sm text-base-content/60 mb-4">3개 중 하나 골라서 그려줘.</p>
        <div class="flex gap-2">
          <%= for w <- @choices do %>
            <button
              phx-click="skribbl_choose_word"
              phx-value-word={w}
              class="btn btn-primary flex-1"
            >
              {w}
            </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :players, :map, required: true
  attr :drawer, :string, default: nil

  defp skribbl_scoreboard(assigns) do
    sorted =
      assigns.players
      |> Enum.sort_by(fn {_, p} -> -p.score end)

    assigns = assign(assigns, sorted: sorted)

    ~H"""
    <div class="bg-base-200 rounded p-3">
      <h3 class="font-semibold mb-2 text-sm">참가자 + 점수</h3>
      <ul class="space-y-1">
        <%= for {{id, p}, idx} <- Enum.with_index(@sorted) do %>
          <li class="flex items-center justify-between text-sm">
            <span class="flex items-center gap-1">
              <span class="text-base-content/60">{idx + 1}.</span>
              <span class="font-mono">{p.nickname}</span>
              <%= if id == @drawer do %>
                <span class="badge badge-xs badge-primary">그림</span>
              <% end %>
              <%= if Map.get(p, :guessed_at) do %>
                <span class="badge badge-xs badge-success">정답</span>
              <% end %>
            </span>
            <strong>{p.score}</strong>
          </li>
        <% end %>
      </ul>
    </div>
    """
  end

  attr :messages, :list, required: true
  attr :can_chat?, :boolean, required: true
  attr :status, :atom, required: true

  defp skribbl_chat(assigns) do
    ~H"""
    <div class="bg-base-200 rounded p-3 flex flex-col" style="height: 510px;">
      <h3 class="font-semibold mb-2 text-sm">채팅 / 추측</h3>

      <div class="flex-1 min-h-0 overflow-y-auto space-y-1 mb-2 text-xs">
        <%= for m <- Enum.reverse(@messages) do %>
          <div>
            <span class="font-mono text-base-content/70">{m.nickname}:</span>
            {m.text}
          </div>
        <% end %>
      </div>

      <form
        id="skribbl-chat-form"
        phx-hook="ChatReset"
        phx-submit="skribbl_chat"
        class="flex gap-1"
      >
        <input
          type="text"
          name="text"
          placeholder={if @status == :drawing, do: "추측 입력...", else: "채팅..."}
          maxlength="200"
          autocomplete="off"
          class="input input-bordered input-sm flex-1"
          disabled={not @can_chat?}
          value=""
        />
        <button type="submit" class="btn btn-sm btn-primary" disabled={not @can_chat?}>전송</button>
      </form>
    </div>
    """
  end

  attr :state, :map, required: true

  defp skribbl_round_end_modal(assigns) do
    seconds = max(div(assigns.state.time_left_ms || 0, 1000), 0)
    word = assigns.state.word

    guessed =
      assigns.state.players
      |> Enum.filter(fn {_, p} -> p.guessed_at end)
      |> Enum.map(fn {_, p} -> p end)
      |> Enum.sort_by(& &1.guessed_at, DateTime)

    assigns = assign(assigns, seconds: seconds, word: word, guessed: guessed)

    ~H"""
    <div class="fixed inset-0 z-40 flex items-center justify-center bg-black/60 p-4">
      <div class="bg-base-100 rounded-xl shadow-2xl max-w-md w-full p-6 border-4 border-info">
        <div class="text-center mb-3">
          <div class="text-3xl mb-1">📢</div>
          <div class="text-lg font-semibold">정답 공개</div>
          <div class="text-3xl font-bold mt-2 text-success font-mono">{@word}</div>
        </div>

        <div class="mb-4">
          <div class="text-sm font-semibold text-base-content/70 mb-1">맞춘 사람</div>
          <%= if @guessed == [] do %>
            <p class="text-base-content/50 text-sm">아무도 못 맞춤 😅</p>
          <% else %>
            <ol class="space-y-1 text-sm">
              <%= for {p, idx} <- Enum.with_index(@guessed) do %>
                <li class="flex justify-between">
                  <span>
                    <span class="badge badge-sm">#{idx + 1}</span>
                    <span class="font-mono ml-2">{p.nickname}</span>
                  </span>
                  <strong>{p.score}점</strong>
                </li>
              <% end %>
            </ol>
          <% end %>
        </div>

        <div class="text-center text-xs text-base-content/60">
          다음 라운드 시작까지 <strong>{@seconds}초</strong>
        </div>
      </div>
    </div>
    """
  end

  attr :state, :map, required: true
  attr :player_id, :string, required: true

  defp skribbl_game_over_modal(assigns) do
    winner_id = assigns.state.winner_id
    winner = winner_id && Map.get(assigns.state.players, winner_id)
    me_won? = winner_id == assigns.player_id

    # 점수 내림차순. {player_id, public_player} → ranking entry.
    ranking =
      assigns.state.players
      |> Enum.sort_by(fn {_, p} -> -p.score end)
      |> Enum.with_index(1)
      |> Enum.map(fn {{id, p}, rank} ->
        %{
          rank: rank,
          player_id: id,
          nickname: Map.get(p, :nickname, "anon"),
          score: p.score,
          is_winner: id == winner_id
        }
      end)

    assigns = assign(assigns, winner: winner, me_won?: me_won?, ranking: ranking)

    ~H"""
    <div class="fixed inset-0 z-40 flex items-center justify-center bg-black/60 p-4">
      <div class={[
        "rounded-xl shadow-2xl max-w-md w-full p-6 border-4",
        if(@me_won?, do: "bg-success/30 border-success", else: "bg-base-100 border-base-300")
      ]}>
        <div class="text-center mb-4">
          <div class="text-5xl mb-2">{if @me_won?, do: "🏆", else: "🎉"}</div>
          <div class="text-2xl font-bold">
            <%= cond do %>
              <% @me_won? -> %>
                승리!
              <% @winner -> %>
                {@winner.nickname} 우승
              <% true -> %>
                게임 종료
            <% end %>
          </div>
        </div>

        <div class="mb-4">
          <div class="font-semibold text-base-content/70 mb-2 text-center">최종 순위</div>
          <div class="space-y-1 text-sm">
            <%= for entry <- @ranking do %>
              <div class={[
                "flex items-center gap-2 px-3 py-1.5 rounded",
                entry.player_id == @player_id && "bg-primary/20 ring-1 ring-primary",
                entry.player_id != @player_id && "bg-base-200"
              ]}>
                <span class="font-bold w-6 text-center">
                  {rank_emoji(entry.rank)}
                </span>
                <span class="flex-1 truncate font-medium">{entry.nickname}</span>
                <span class="text-xs font-bold">{entry.score}점</span>
              </div>
            <% end %>
          </div>
        </div>

        <button phx-click="skribbl_start_game" class="btn btn-primary w-full">
          🔄 다시 하기
        </button>
      </div>
    </div>
    """
  end

  defp word_blanks(nil), do: ""

  defp word_blanks(word) when is_binary(word) do
    String.graphemes(word) |> Enum.map(fn _ -> "_" end) |> Enum.join(" ")
  end

  # HTTP 첫 mount 의 placeholder %{status: :waiting, players: %{}} 보강.
  # Skribbl 의 모든 필드 default — render crash 방지.
  defp ensure_skribbl_state(state) do
    state
    |> Map.put_new(:status, :waiting)
    |> Map.put_new(:players, %{})
    |> Map.put_new(:drawer_id, nil)
    |> Map.put_new(:word, nil)
    |> Map.put_new(:word_choices, [])
    |> Map.put_new(:word_revealed, false)
    |> Map.put_new(:time_left_ms, 0)
    |> Map.put_new(:strokes, [])
    |> Map.put_new(:messages, [])
    |> Map.put_new(:round_no, 0)
    |> Map.put_new(:winner_id, nil)
  end

  attr :label, :string, required: true
  attr :piece, :atom, default: nil
  attr :dim, :boolean, default: false
  attr :skin, :string, default: "default_jstris"

  defp piece_preview(assigns) do
    ~H"""
    <div class={["bg-base-200 p-1 sm:p-2 rounded text-center min-w-[60px] sm:min-w-[80px]", @dim && "opacity-40"]}>
      <div class="text-xs text-base-content/60 mb-1">{@label}</div>
      <%= if @piece do %>
        <div class="grid grid-cols-4 gap-px">
          <%= for {r, c} <- piece_preview_cells(@piece) do %>
            <div
              class={["w-3 h-3", cell_color(@piece, @skin)]}
              style={"grid-row: #{r + 1}; grid-column: #{c + 1};"}
            >
            </div>
          <% end %>
        </div>
      <% else %>
        <div class="h-8"></div>
      <% end %>
    </div>
    """
  end

  defp piece_preview_cells(type) do
    HappyTrizn.Games.Tetris.Piece.cells(type, 0)
  end

  attr :nexts, :list, required: true
  attr :skin, :string, default: "default_jstris"

  defp next_queue(assigns) do
    ~H"""
    <div class="flex flex-col gap-2 bg-base-200 p-2 rounded min-w-[64px] sm:min-w-[80px]">
      <div class="text-xs text-base-content/60 text-center">다음</div>
      <%= for piece <- @nexts || [] do %>
        <div class="bg-base-300/60 rounded p-1.5 flex justify-center">
          <div class="grid grid-cols-4 gap-px">
            <%= for {r, c} <- piece_preview_cells(piece) do %>
              <div
                class={["w-3 h-3", cell_color(piece, @skin)]}
                style={"grid-row: #{r + 1}; grid-column: #{c + 1};"}
              >
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # 1. board, 2. ghost (옵션 켜졌고 origin != landing 시), 3. current piece — 순으로 overlay.
  defp with_ghost_and_current(%{board: board, current: cur, top_out: false} = p, ghost?) do
    board
    |> maybe_overlay_ghost(p, ghost?)
    |> overlay_cells(
      HappyTrizn.Games.Tetris.Piece.absolute_cells(cur.type, cur.rotation, cur.origin),
      cur.type
    )
  end

  defp with_ghost_and_current(%{board: board}, _), do: board

  defp maybe_overlay_ghost(board, _, false), do: board

  defp maybe_overlay_ghost(board, %{current: cur} = _p, true) do
    landing =
      HappyTrizn.Games.Tetris.Board.hard_drop_position(board, cur.type, cur.rotation, cur.origin)

    if landing == cur.origin do
      board
    else
      cells = HappyTrizn.Games.Tetris.Piece.absolute_cells(cur.type, cur.rotation, landing)
      # ghost 셀은 piece type 을 들고 다님 — 색은 같지만 opacity 낮춰 표시.
      overlay_cells(board, cells, {:ghost, cur.type})
    end
  end

  defp overlay_cells(board, cells, value) do
    Enum.reduce(cells, board, fn {r, c}, acc ->
      if r >= 0 and r < length(acc) do
        row = Enum.at(acc, r) |> List.replace_at(c, value)
        List.replace_at(acc, r, row)
      else
        acc
      end
    end)
  end

  # 22x10 board → 20x10 (visible) 만 표시. grid 옵션: none / standard / partial / vertical / full.
  # pending: 사용자가 받을 garbage 수 (board 좌측에 빨간 spoiler bar 로 표시).
  attr :board, :list, required: true
  attr :grid, :string, default: "standard"
  attr :pending, :integer, default: 0

  # Sprint 3j — Canvas renderer (opt-in via tetris_renderer 옵션).
  # board encoded JSON → data attr → JS hook 이 redraw.
  defp tetris_canvas(assigns) do
    encoded = encode_board_for_canvas(assigns.board) |> Jason.encode!()
    pending_capped = min(assigns.pending, 20)
    skin = Map.get(assigns, :skin, "default_jstris")
    grid = Map.get(assigns, :grid, "standard")

    assigns =
      assign(assigns,
        encoded: encoded,
        pending_capped: pending_capped,
        skin: skin,
        grid: grid
      )

    ~H"""
    <div class="inline-flex bg-base-300 p-1 gap-px">
      <%= if @pending_capped > 0 do %>
        <div class="flex flex-col-reverse w-1.5 bg-base-100 overflow-hidden">
          <%= for _ <- 1..@pending_capped//1 do %>
            <div class="h-5 bg-error animate-pulse"></div>
          <% end %>
        </div>
      <% end %>
      <canvas
        id="tetris-canvas-me"
        phx-hook="TetrisCanvas"
        data-board={@encoded}
        data-skin={@skin}
        data-grid={@grid}
        data-cell-size="28"
        class="block"
      >
      </canvas>
    </div>
    """
  end

  # board cell 인코딩 — atom / tuple → BSON 호환 string. nil 그대로.
  defp encode_board_for_canvas(board) do
    Enum.map(board, fn row ->
      Enum.map(row, fn
        nil -> nil
        {:ghost, type} -> "g_#{type}"
        atom when is_atom(atom) -> Atom.to_string(atom)
        other -> other
      end)
    end)
  end

  defp tetris_board(assigns) do
    # board overflow 방어 — drop hidden 2 + take visible 20. board state 가
    # 어쩌다 길이 비정상이어도 UI 는 20×10 보장.
    visible = assigns.board |> Enum.drop(2) |> Enum.take(20)
    pending_capped = min(assigns.pending, 20)
    skin = Map.get(assigns, :skin, "default_jstris")
    assigns = assign(assigns, visible: visible, pending_capped: pending_capped, skin: skin)

    ~H"""
    <div class="inline-flex bg-base-300 p-1 gap-px">
      <!-- pending garbage spoiler bar — pending 있을 때만 노출, 없으면 좌측 빈공간 X. -->
      <%= if @pending_capped > 0 do %>
        <div class="flex flex-col-reverse w-1.5 bg-base-100 overflow-hidden">
          <%= for _ <- 1..@pending_capped//1 do %>
            <div class="h-5 bg-error animate-pulse"></div>
          <% end %>
        </div>
      <% end %>
      <div>
        <%= for row <- @visible do %>
          <div class="flex">
            <%= for cell <- row do %>
              <div class={[
                "w-6 h-6 sm:w-7 sm:h-7",
                cell_color(cell, @skin),
                grid_class(@grid),
                if(cell != nil, do: "tetris-filled")
              ]}>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # 빈 셀 bg = base-100 (어두운 배경). border 는 매우 연하게 — base-content/5
  # (jstris 처럼 은은한 격자, 눈에 거슬리지 않는 정도).
  defp grid_class("none"), do: ""
  defp grid_class("standard"), do: "border border-base-content/5"
  defp grid_class("partial"), do: "border-l border-t border-base-content/5"
  defp grid_class("vertical"), do: "border-l border-r border-base-content/5"
  defp grid_class("full"), do: "border border-base-content/10"
  defp grid_class(_), do: "border border-base-content/5"

  # Sprint 3j — Skin system. cell_color/1 은 default_jstris 팔레트, cell_color/2 는 skin 명시.
  # Tailwind 가 빌드 시 클래스 스캔하므로 모든 변형 명시적 작성 필요.

  defp cell_color(cell), do: cell_color(cell, "default_jstris")

  # 빈 셀 + 가비지 — skin 무관 공통.
  defp cell_color(nil, _), do: "bg-base-100"
  defp cell_color(:garbage, _), do: "bg-gray-500"

  # default_jstris (jstris 표준 색).
  defp cell_color(:i, "default_jstris"), do: "bg-cyan-400"
  defp cell_color(:o, "default_jstris"), do: "bg-yellow-400"
  defp cell_color(:t, "default_jstris"), do: "bg-purple-500"
  defp cell_color(:s, "default_jstris"), do: "bg-green-500"
  defp cell_color(:z, "default_jstris"), do: "bg-red-500"
  defp cell_color(:l, "default_jstris"), do: "bg-orange-500"
  defp cell_color(:j, "default_jstris"), do: "bg-blue-500"

  # vivid — 한 단계 더 진하게.
  defp cell_color(:i, "vivid"), do: "bg-cyan-600"
  defp cell_color(:o, "vivid"), do: "bg-yellow-500"
  defp cell_color(:t, "vivid"), do: "bg-purple-700"
  defp cell_color(:s, "vivid"), do: "bg-green-700"
  defp cell_color(:z, "vivid"), do: "bg-red-700"
  defp cell_color(:l, "vivid"), do: "bg-orange-600"
  defp cell_color(:j, "vivid"), do: "bg-blue-700"

  # monochrome — 회색 + 라이트/다크 단계.
  defp cell_color(:i, "monochrome"), do: "bg-slate-300"
  defp cell_color(:o, "monochrome"), do: "bg-slate-200"
  defp cell_color(:t, "monochrome"), do: "bg-slate-500"
  defp cell_color(:s, "monochrome"), do: "bg-slate-400"
  defp cell_color(:z, "monochrome"), do: "bg-slate-600"
  defp cell_color(:l, "monochrome"), do: "bg-slate-300"
  defp cell_color(:j, "monochrome"), do: "bg-slate-700"

  # neon — 네온/형광.
  defp cell_color(:i, "neon"), do: "bg-cyan-300"
  defp cell_color(:o, "neon"), do: "bg-yellow-300"
  defp cell_color(:t, "neon"), do: "bg-fuchsia-400"
  defp cell_color(:s, "neon"), do: "bg-lime-400"
  defp cell_color(:z, "neon"), do: "bg-rose-400"
  defp cell_color(:l, "neon"), do: "bg-amber-400"
  defp cell_color(:j, "neon"), do: "bg-indigo-400"

  # 알 수 없는 skin → default fallback.
  defp cell_color(piece, _) when piece in [:i, :o, :t, :s, :z, :l, :j],
    do: cell_color(piece, "default_jstris")

  # Ghost — skin 무관 (현재). 향후 skin 별 ghost 도 추가 가능.
  defp cell_color({:ghost, :i}, _), do: "bg-cyan-400/40 border-2 border-cyan-300"
  defp cell_color({:ghost, :o}, _), do: "bg-yellow-400/40 border-2 border-yellow-300"
  defp cell_color({:ghost, :t}, _), do: "bg-purple-500/40 border-2 border-purple-300"
  defp cell_color({:ghost, :s}, _), do: "bg-green-500/40 border-2 border-green-300"
  defp cell_color({:ghost, :z}, _), do: "bg-red-500/40 border-2 border-red-300"
  defp cell_color({:ghost, :l}, _), do: "bg-orange-500/40 border-2 border-orange-300"
  defp cell_color({:ghost, :j}, _), do: "bg-blue-500/40 border-2 border-blue-300"
  defp cell_color({:ghost, _}, _), do: "bg-base-200 border-2 border-base-content/60"

  defp cell_color(_, _), do: "bg-base-100"

  attr :result, :map, required: true
  attr :player_id, :string, required: true

  defp game_over_panel(assigns) do
    winner = Map.get(assigns.result, :winner)
    me_won? = is_binary(winner) and winner == assigns.player_id
    summary = Map.get(assigns.result, :winners_summary, [])
    ranking = Map.get(assigns.result, :ranking, [])

    assigns =
      assign(assigns, winner: winner, me_won?: me_won?, summary: summary, ranking: ranking)

    ~H"""
    <!-- Fullscreen popup overlay — 게임 끝났을 때 명확히 보이도록 화면 중앙에. -->
    <div class="fixed inset-0 z-40 flex items-center justify-center bg-black/60 p-4">
      <div class={[
        "rounded-xl shadow-2xl max-w-md w-full p-6 border-4",
        if(@me_won?,
          do: "bg-success/30 border-success",
          else: "bg-base-100 border-base-300"
        )
      ]}>
        <div class="text-center mb-4">
          <div class="text-5xl mb-2">
            <%= cond do %>
              <% @me_won? -> %>
                🏆
              <% is_binary(@winner) -> %>
                😢
              <% true -> %>
                💀
            <% end %>
          </div>
          <div class="text-2xl font-bold">
            <%= cond do %>
              <% @me_won? -> %>
                승리!
              <% is_binary(@winner) -> %>
                패배
              <% true -> %>
                게임 종료
            <% end %>
          </div>
        </div>

        <%= if @ranking != [] do %>
          <div class="mb-4">
            <div class="font-semibold text-base-content/70 mb-2 text-center">최종 순위</div>
            <div class="space-y-1 text-sm">
              <%= for entry <- @ranking do %>
                <div class={[
                  "flex items-center gap-2 px-3 py-1.5 rounded",
                  entry.player_id == @player_id && "bg-primary/20 ring-1 ring-primary",
                  entry.player_id != @player_id && "bg-base-200"
                ]}>
                  <span class="font-bold w-6 text-center">
                    {rank_emoji(entry.rank)}
                  </span>
                  <span class="flex-1 truncate font-medium">{entry.nickname}</span>
                  <span class="text-xs text-base-content/60">
                    {entry.score}pt · L{entry.lines}
                  </span>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>

        <%= if @summary != [] do %>
          <div class="mb-4">
            <div class="font-semibold text-base-content/70 mb-2 text-center text-xs">방 누적 우승</div>
            <div class="flex flex-wrap gap-1 justify-center">
              <%= for entry <- @summary do %>
                <span class="badge badge-sm">
                  {entry.nickname} · {entry.wins}회
                </span>
              <% end %>
            </div>
          </div>
        <% end %>

        <button phx-click="restart" class="btn btn-primary w-full">
          🔄 다시 하기
        </button>
      </div>
    </div>
    """
  end

  defp rank_emoji(1), do: "🥇"
  defp rank_emoji(2), do: "🥈"
  defp rank_emoji(3), do: "🥉"
  defp rank_emoji(n), do: "#{n}"
end
