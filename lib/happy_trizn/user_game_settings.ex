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

  @doc """
  게임별 기본 key bindings + options 반환.

  새 게임 추가 시 case 절 확장.
  """
  def defaults("bomberman") do
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

  def defaults("skribbl") do
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

  def defaults("snake_io") do
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

  def defaults("games_2048") do
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

  def defaults("minesweeper") do
    %{
      bindings: %{
        "reveal" => ["click"],
        "flag" => ["right_click", "f"]
      },
      options: %{
        "difficulty" => "medium",
        "show_timer" => true
      },
      das: 0,
      arr: 0,
      soft_drop_speed: "medium"
    }
  end

  def defaults("pacman") do
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
        "sound_intro" => true
      },
      das: 0,
      arr: 0,
      soft_drop_speed: "medium"
    }
  end

  def defaults("tetris") do
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
        "block_skin" => "default_jstris",
        "block_color" => "#5c5c5c",
        "sound_volume" => 16,
        "sound_start" => true,
        "sound_rotate" => true,
        "sound_finesse" => false,
        "sound_join" => true,
        "sound_message" => true
      },
      das: 133,
      arr: 10,
      soft_drop_speed: "medium"
    }
  end

  def defaults(_game_type) do
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
    base = defaults(game_type)

    case Repo.get_by(Setting, user_id: user_id, game_type: game_type) do
      nil ->
        base

      %Setting{key_bindings: kb, options: opts} ->
        merged_bindings = Map.merge(base.bindings, kb || %{})
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

  @doc """
  Upsert 사용자 옵션. (등록자 only)

  attrs = %{key_bindings: %{...}, options: %{...}}
  """
  def upsert(%{id: user_id}, game_type, attrs) do
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
