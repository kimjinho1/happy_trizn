defmodule HappyTrizn.UserGameSettings do
  @moduledoc """
  사용자별 게임 옵션 (key bindings + options) 컨텍스트.

  - 등록자 → DB 저장 (`user_game_settings` table).
  - 게스트 (user=nil) → 기본값만, 클라이언트 localStorage 가 fallback.

  ## get_for/2 결과 shape

      %{
        bindings: %{"move_left" => ["ArrowLeft", "j"], ...},
        options: %{"ghost" => true, ...},
        das: 133,           # ms
        arr: 10,            # ms
        soft_drop: :medium  # tetris 만
      }
  """

  import Ecto.Query

  alias HappyTrizn.Repo
  alias HappyTrizn.UserGameSettings.Setting

  # ============================================================================
  # Defaults — 게임별
  # ============================================================================

  # slug ↔ settings game_type 정규화. 라우터/Registry 는 slug ("2048") 사용 하지만
  # DB schema 의 valid_game_types / defaults case 는 "games_2048" 키 사용. 모든
  # public API entry 에서 통일.
  @doc false
  def normalize_game_type("2048"), do: "games_2048"
  def normalize_game_type(slug), do: slug

  @doc """
  게임별 기본 key bindings + options 반환.

  새 게임 추가 시 case 절 확장. slug "2048" → "games_2048" 자동 정규화.
  """
  def defaults(game_type) when is_binary(game_type) do
    do_defaults(normalize_game_type(game_type))
  end

  defp do_defaults("bomberman") do
    %{
      bindings: %{
        "move_up" => ["ArrowUp", "w"],
        "move_down" => ["ArrowDown", "s"],
        "move_left" => ["ArrowLeft", "a"],
        "move_right" => ["ArrowRight", "d"],
        "place_bomb" => [" ", "x"],
        "kick" => ["k"],
        "punch" => ["p"]
      },
      options: %{
        "speed_sound" => true,
        "explosion_sound" => true,
        "grid_color" => "#1a1a1a",
        "skin" => "default"
      },
      das: 133,
      arr: 30,
      soft_drop_speed: "medium"
    }
  end

  defp do_defaults("skribbl") do
    %{
      bindings: %{
        "send_chat" => ["Enter"]
      },
      options: %{
        "chat_sound" => true,
        "dictionary" => "ko",
        "round_seconds" => 80,
        "default_pen_color" => "#000000"
      },
      das: 133,
      arr: 10,
      soft_drop_speed: "medium"
    }
  end

  defp do_defaults("snake_io") do
    %{
      bindings: %{
        "move_up" => ["ArrowUp", "w", "k"],
        "move_down" => ["ArrowDown", "s", "j"],
        "move_left" => ["ArrowLeft", "a", "h"],
        "move_right" => ["ArrowRight", "d", "l"],
        "boost" => [" "]
      },
      options: %{
        "color" => "random",
        "minimap" => true
      },
      das: 0,
      arr: 0,
      soft_drop_speed: "medium"
    }
  end

  defp do_defaults("games_2048") do
    %{
      bindings: %{
        "move_up" => ["ArrowUp", "w", "k"],
        "move_down" => ["ArrowDown", "s", "j"],
        "move_left" => ["ArrowLeft", "a", "h"],
        "move_right" => ["ArrowRight", "d", "l"]
      },
      options: %{
        "board_size" => 4,
        "theme" => "light"
      },
      das: 0,
      arr: 0,
      soft_drop_speed: "medium"
    }
  end

  defp do_defaults("minesweeper") do
    %{
      bindings: %{
        # Sprint 4f — keyboard cursor 이동 + reveal/flag. game_live 가
        # bindings 을 읽어 key → action mapping. 사용자 옵션에서 변경 가능.
        "move_up" => ["ArrowUp", "w", "k"],
        "move_down" => ["ArrowDown", "s", "j"],
        "move_left" => ["ArrowLeft", "a", "h"],
        "move_right" => ["ArrowRight", "d", "l"],
        "reveal" => ["click", " ", "Enter"],
        "flag" => ["right_click", "f", "F"]
      },
      options: %{
        "difficulty" => "medium",
        "show_timer" => true,
        # custom 난이도일 때만 사용. 다른 난이도는 프리셋이 우선.
        "custom_rows" => 10,
        "custom_cols" => 10,
        "custom_mines" => 12
      },
      das: 0,
      arr: 0,
      soft_drop_speed: "medium"
    }
  end

  defp do_defaults("pacman") do
    %{
      bindings: %{
        "move_up" => ["ArrowUp", "w"],
        "move_down" => ["ArrowDown", "s"],
        "move_left" => ["ArrowLeft", "a"],
        "move_right" => ["ArrowRight", "d"]
      },
      options: %{
        "sound_eat" => true,
        "sound_death" => true,
        "sound_intro" => true,
        # Sprint 4f-4 — tick interval (ms). 작을수록 빠름. 기본 125 (Pac-Man module 의 @tick_ms 와 일치).
        # 50~300 범위. modal options form 에서 변경.
        "tick_ms" => 125
      },
      das: 0,
      arr: 0,
      soft_drop_speed: "medium"
    }
  end

  defp do_defaults("tetris") do
    %{
      bindings: %{
        "move_left" => ["ArrowLeft", "j"],
        "move_right" => ["ArrowRight", "l"],
        "soft_drop" => ["ArrowDown", "k"],
        "hard_drop" => [" "],
        "rotate_cw" => ["ArrowUp", "x"],
        "rotate_ccw" => ["z", "Control"],
        "rotate_180" => ["a"],
        "hold" => ["Shift", "c"],
        "pause" => ["Escape"]
      },
      options: %{
        "das" => 133,
        "arr" => 10,
        "soft_drop_speed" => "medium",
        "grid" => "standard",
        "ghost" => true,
        # Sprint 3j — block_skin: 색 팔레트 (default_jstris / vivid / monochrome / neon).
        # tetris_renderer: "dom" (HEEx 셀, 기본) | "canvas" (HTML5 canvas, 빠름).
        "block_skin" => "default_jstris",
        "tetris_renderer" => "dom",
        "block_color" => "#5c5c5c",
        # 효과음 마스터 볼륨 (0~100). 각 효과음 on/off (rotate / lock / line_clear /
        # tetris / b2b / garbage / top_out / countdown).
        "sound_volume" => 16,
        "sound_rotate" => true,
        "sound_lock" => true,
        "sound_line_clear" => true,
        "sound_tetris" => true,
        "sound_b2b" => true,
        "sound_garbage" => true,
        "sound_top_out" => true,
        "sound_countdown" => true,
        "sound_finesse" => false
      },
      das: 133,
      arr: 10,
      soft_drop_speed: "medium"
    }
  end

  defp do_defaults(_game_type) do
    %{bindings: %{}, options: %{}, das: 133, arr: 10, soft_drop_speed: "medium"}
  end

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  사용자 (또는 nil) 의 game_type 옵션 반환.

  - user nil (게스트) → 기본값.
  - row 없음 → 기본값.
  - row 있음 → defaults 와 merge (새 옵션 추가 시 안전).

  Returns map with :bindings, :options, :das, :arr.
  """
  def get_for(nil, game_type), do: defaults(game_type)

  def get_for(%{id: user_id}, game_type) do
    game_type = normalize_game_type(game_type)
    base = defaults(game_type)

    case Repo.get_by(Setting, user_id: user_id, game_type: game_type) do
      nil ->
        base

      %Setting{key_bindings: kb, options: opts} ->
        merged_bindings =
          base.bindings
          |> Map.merge(kb || %{})
          |> normalize_bindings()

        merged_options = Map.merge(base.options, opts || %{})

        %{
          bindings: merged_bindings,
          options: merged_options,
          das: get_int(merged_options, "das", base.das),
          arr: get_int(merged_options, "arr", base.arr),
          soft_drop_speed: Map.get(merged_options, "soft_drop_speed", base.soft_drop_speed)
        }
    end
  end

  # 저장된 키 list 의 친화 표기 ("Space"/"space" 등) 를 KeyboardEvent.key 정규형 (" ") 으로 변환.
  # 과거 parse_key 도입 전에 저장된 row 도 안전하게 매칭.
  defp normalize_bindings(bindings) when is_map(bindings) do
    Map.new(bindings, fn {action, keys} ->
      {action, normalize_key_list(keys)}
    end)
  end

  defp normalize_key_list(keys) when is_list(keys), do: Enum.map(keys, &normalize_key/1)
  defp normalize_key_list(_), do: []

  defp normalize_key("Space"), do: " "
  defp normalize_key("space"), do: " "
  defp normalize_key("SPACE"), do: " "
  defp normalize_key("Tab"), do: "\t"
  defp normalize_key(k), do: k

  # ============================================================================
  # Public helpers for forms (display + parse)
  # ============================================================================

  @doc "키 list → UI 친화 표시 문자열 (\" \" → \"Space\")."
  def display_keys(keys) when is_list(keys) do
    keys |> Enum.map(&display_key/1) |> Enum.join(", ")
  end

  def display_keys(_), do: ""

  def display_key(" "), do: "Space"
  def display_key("\t"), do: "Tab"
  def display_key(k), do: k

  @doc "사용자 입력 키 문자열 → KeyboardEvent.key 정규형 (\"Space\" → \" \")."
  def parse_key("Space"), do: " "
  def parse_key("space"), do: " "
  def parse_key("Tab"), do: "\t"
  def parse_key(""), do: ""
  def parse_key(k), do: k

  @doc "콤마 분리 + trim + parse + 빈 값 제거."
  def parse_keys_input(str) when is_binary(str) do
    str
    |> String.split(",", trim: true)
    |> Enum.map(&(&1 |> String.trim() |> parse_key()))
    |> Enum.reject(&(&1 == ""))
  end

  def parse_keys_input(_), do: []

  @doc "옵션 값 정규화 (boolean/integer 변환)."
  def normalize_option_value(_k, "true"), do: true
  def normalize_option_value(_k, "false"), do: false

  def normalize_option_value(k, v)
      when k in ~w(das arr sound_volume round_seconds board_size custom_rows custom_cols custom_mines) and
             is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      :error -> v
    end
  end

  def normalize_option_value(_, v), do: v

  @doc """
  Upsert 사용자 옵션. (등록자 only)

  attrs = %{key_bindings: %{...}, options: %{...}}
  """
  def upsert(%{id: user_id}, game_type, attrs) do
    game_type = normalize_game_type(game_type)

    # 신규 row 는 game_type 미설정 상태로 만들어 changeset 의 validate_inclusion 이 실행되도록.
    # (validate_change 는 cast 시 변경된 field 에만 동작 — 미리 채워두면 검증 누락.)
    setting =
      Repo.get_by(Setting, user_id: user_id, game_type: game_type) ||
        %Setting{}

    full_attrs =
      %{user_id: user_id, game_type: game_type}
      |> Map.merge(attrs)

    setting
    |> Setting.changeset(full_attrs)
    |> Repo.insert_or_update()
  end

  def upsert(nil, _, _), do: {:error, :guest_not_allowed}

  @doc "사용자의 게임 row 삭제 (옵션 초기화)."
  def reset(%{id: user_id}, game_type) do
    game_type = normalize_game_type(game_type)

    from(s in Setting, where: s.user_id == ^user_id and s.game_type == ^game_type)
    |> Repo.delete_all()

    :ok
  end

  @doc "사용자의 모든 옵션 row 가져오기."
  def list_for_user(%{id: user_id}) do
    from(s in Setting, where: s.user_id == ^user_id, order_by: s.game_type)
    |> Repo.all()
  end

  def list_for_user(nil), do: []

  # ============================================================================
  # Helpers
  # ============================================================================

  defp get_int(map, key, default) do
    case Map.get(map, key) do
      v when is_integer(v) ->
        v

      v when is_binary(v) ->
        case Integer.parse(v) do
          {n, _} -> n
          :error -> default
        end

      _ ->
        default
    end
  end
end
