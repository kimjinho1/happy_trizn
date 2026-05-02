defmodule HappyTrizn.Games.Skribbl do
  @moduledoc """
  Skribbl — 그림 맞추기 멀티 (2~8인).

  ## 라운드 흐름

  1. **`:waiting`** — player join 대기. 2명 이상 시 1번째 player 의 `start_game`
     으로 라운드 시작.
  2. **`:choosing`** — drawer 가 3개 단어 중 1개 선택 (`choose_word` action).
     30초 안에 안 고르면 자동으로 첫 단어.
  3. **`:drawing`** — drawer 그림 + 다른 사람들 chat 으로 추측.
     각 round 80초. drawer 가 stroke action 으로 그림. 모든 사람이 맞추거나
     timer 0 → round 끝.
  4. **`:round_end`** — 점수 합산, 5초 후 다음 drawer.
  5. 모든 player 한 번씩 drawer → `:over` (전체 라운드 종료).

  ## state

      status, drawer_id, drawer_index, drawn_count (drawer 누적, 모든 player
      한 번씩 drawer 되면 :over),
      word, word_choices, word_revealed (모든 사람 맞춤 / timer 0 → 단어 공개),
      time_left_ms, strokes (현재 라운드 stroke list),
      players: %{player_id => %{nickname, score, guessed_at, was_drawer?}},
      messages (단어 검증 안 된 chat 만 broadcast)

  ## Actions

      "start_game" (waiting → choosing)
      "choose_word" (drawer, choosing → drawing)
      "stroke" (drawer, drawing — 점/선분 추가)
      "clear_canvas" (drawer, drawing — strokes 초기화)
      "guess" (any not-drawer, drawing — 단어 맞춤 시 점수)
  """

  @behaviour HappyTrizn.Games.GameBehaviour

  @tick_ms 100
  @drawing_ms 80_000
  @choosing_ms 30_000
  @round_end_ms 5_000
  # 게임당 총 라운드 수 — player 수와 무관. drawer 는 가장 적게 그린 사람 부터 round-robin.
  @total_rounds 5
  @max_players 8

  def total_rounds, do: @total_rounds

  # 한국어 단어 풀 — 모두가 알 만한 것만. 일상 / 인기 게임 / 유명 만화애니 /
  # 메인스트림 개발 용어 / 일상 활동.
  @word_pool ~w(
    사과 바나나 포도 수박 딸기 고양이 강아지 토끼 호랑이 사자
    자동차 비행기 배 기차 자전거 컴퓨터 키보드 마우스 모니터 핸드폰
    학교 병원 도서관 공원 영화관 식당 카페 은행 약국 시장
    의자 책상 침대 소파 거울 시계 책 연필 가방 우산
    축구 농구 야구 수영 달리기 등산 요리 청소 빨래 운전
    햄버거 피자 김밥 라면 떡볶이 치킨 짜장면 비빔밥 김치 된장
    봄 여름 가을 겨울 비 눈 바람 구름 태양 달
    빨강 파랑 노랑 초록 검정 하양 분홍 보라 주황 갈색
    의사 간호사 선생님 학생 경찰 소방관 가수 배우 화가 작가
    엄마 아빠 형 누나 동생 친구 연인 가족 이웃 손님

    롤 리그오브레전드 스타크래프트 오버워치 배틀그라운드 발로란트
    마인크래프트 메이플스토리 던전앤파이터 카트라이더 서든어택
    피파 로스트아크 디아블로 워크래프트 포트나이트 카운터스트라이크
    엘든링 젤다 마리오 포켓몬 동물의숲 어몽어스 테트리스

    진격의거인 원피스 나루토 드래곤볼 슬램덩크 짱구 도라에몽
    코난 데스노트 주술회전 귀멸의칼날 스파이패밀리 원펀맨 헌터헌터
    하이큐 에반게리온 아이언맨 스파이더맨 캡틴아메리카 헐크 토르
    배트맨 슈퍼맨 원더우먼

    개발자 코딩 깃허브 커밋 디버깅 빌드 배포
    리눅스 도커 자바스크립트 파이썬 자바 리액트 백엔드 프론트엔드
    데이터베이스 알고리즘 함수 변수 클래스

    아이돌 콘서트 콜라 노래방 PC방 한강 서울 부산 제주도
    여행 운동 다이어트 시험 알바 회식 출근 퇴근 야근 월급
  )

  def word_pool, do: @word_pool

  # ============================================================================
  # GameBehaviour
  # ============================================================================

  @impl true
  def meta do
    %{
      name: "캐치마인드",
      slug: "skribbl",
      mode: :multi,
      max_players: @max_players,
      min_players: 2,
      description: "그림 그리고 단어 맞추기 (한국어)",
      tick_interval_ms: @tick_ms,
      # 그리는 사람 끊김 시 라운드 보호 위해 길게 — 8초.
      grace_period_ms: 8000
    }
  end

  @impl true
  def init(_config) do
    {:ok,
     %{
       status: :waiting,
       drawer_id: nil,
       drawn_count: %{},
       word: nil,
       word_choices: [],
       word_revealed: false,
       time_left_ms: 0,
       strokes: [],
       players: %{},
       messages: [],
       round_no: 0,
       winner_id: nil
     }}
  end

  # ============================================================================
  # Player join / leave
  # ============================================================================

  @impl true
  def handle_player_join(player_id, meta, state) do
    cond do
      Map.has_key?(state.players, player_id) ->
        {:ok, state, []}

      map_size(state.players) >= @max_players ->
        {:reject, :full}

      true ->
        nickname = Map.get(meta, :nickname, "anon")

        player = %{
          nickname: nickname,
          score: 0,
          guessed_at: nil,
          was_drawer: false
        }

        new_players = Map.put(state.players, player_id, player)
        {:ok, %{state | players: new_players}, [{:player_joined, player_id}]}
    end
  end

  @impl true
  def handle_player_leave(player_id, _reason, state) do
    new_players = Map.delete(state.players, player_id)
    new_drawn = Map.delete(state.drawn_count, player_id)

    cond do
      # drawer 가 떠남 — round 종료, 다음 drawer.
      state.status in [:drawing, :choosing] and state.drawer_id == player_id ->
        ns = %{state | players: new_players, drawn_count: new_drawn}
        {:ok, end_round(ns, :drawer_left), [{:player_left, player_id}, {:drawer_left, player_id}]}

      # 0명 → :over.
      map_size(new_players) == 0 ->
        {:ok, %{state | players: new_players, drawn_count: new_drawn, status: :over},
         [{:player_left, player_id}]}

      # 게임 종료 후 한 명만 남음 — 다시 하기 가 min_players 2 로 거부됨. 자동 :waiting 리셋.
      state.status == :over and map_size(new_players) < 2 ->
        ns = %{state | players: new_players, drawn_count: new_drawn}
        {:ok, reset_to_waiting(ns), [{:player_left, player_id}]}

      true ->
        {:ok, %{state | players: new_players, drawn_count: new_drawn},
         [{:player_left, player_id}]}
    end
  end

  # 점수 / 라운드 / 단어 / strokes 다 초기화. nickname 유지.
  defp reset_to_waiting(state) do
    fresh_players =
      Enum.into(state.players, %{}, fn {pid, p} ->
        {pid, %{nickname: p.nickname, score: 0, guessed_at: nil, was_drawer: false}}
      end)

    %{
      state
      | status: :waiting,
        drawer_id: nil,
        drawn_count: %{},
        word: nil,
        word_choices: [],
        word_revealed: false,
        time_left_ms: 0,
        strokes: [],
        messages: [],
        round_no: 0,
        winner_id: nil,
        players: fresh_players
    }
  end

  # ============================================================================
  # Actions
  # ============================================================================

  @impl true
  def handle_input(player_id, %{"action" => "start_game"}, state) do
    cond do
      state.status not in [:waiting, :over] ->
        {:ok, state, []}

      not Map.has_key?(state.players, player_id) ->
        {:ok, state, []}

      # :over + 인원 부족 — modal 에서 "다시 하기" 누른 경우. modal 빠지게 :waiting 리셋.
      state.status == :over and map_size(state.players) < 2 ->
        {:ok, reset_to_waiting(state), [{:reset, player_id}]}

      map_size(state.players) < 2 ->
        {:ok, state, []}

      true ->
        # :over 에서 시작하면 점수 / drawer 카운트 리셋.
        reset_state =
          if state.status == :over do
            %{
              state
              | drawn_count: %{},
                round_no: 0,
                winner_id: nil,
                players:
                  Map.new(state.players, fn {id, p} ->
                    {id, %{p | score: 0, guessed_at: nil, was_drawer: false}}
                  end)
            }
          else
            state
          end

        start_choosing(reset_state)
    end
  end

  def handle_input(player_id, %{"action" => "choose_word", "word" => word}, state) do
    cond do
      state.status != :choosing ->
        {:ok, state, []}

      state.drawer_id != player_id ->
        {:ok, state, []}

      word not in state.word_choices ->
        {:ok, state, []}

      true ->
        new_state = %{state | status: :drawing, word: word, time_left_ms: @drawing_ms}

        {:ok, new_state,
         [
           {:word_chosen, %{drawer: player_id, length: String.length(word)}},
           {:strokes_cleared, %{}}
         ]}
    end
  end

  def handle_input(player_id, %{"action" => "stroke", "stroke" => stroke_data}, state) do
    cond do
      state.status != :drawing ->
        {:ok, state, []}

      state.drawer_id != player_id ->
        {:ok, state, []}

      not is_map(stroke_data) ->
        {:ok, state, []}

      true ->
        clean = sanitize_stroke(stroke_data)
        new_strokes = state.strokes ++ [clean]
        {:ok, %{state | strokes: new_strokes}, [{:stroke, clean}]}
    end
  end

  def handle_input(player_id, %{"action" => "clear_canvas"}, state) do
    if state.status == :drawing and state.drawer_id == player_id do
      {:ok, %{state | strokes: []}, [{:strokes_cleared, %{}}]}
    else
      {:ok, state, []}
    end
  end

  def handle_input(player_id, %{"action" => "guess", "text" => text}, state) do
    cond do
      state.status != :drawing ->
        push_message(state, player_id, text)

      state.drawer_id == player_id ->
        # drawer 는 추측 / 채팅 못 함 (정답 누설 방지).
        {:ok, state, []}

      already_guessed?(state, player_id) ->
        {:ok, state, []}

      correct_guess?(text, state.word) ->
        award_correct(state, player_id)

      true ->
        push_message(state, player_id, text)
    end
  end

  def handle_input(_, _, state), do: {:ok, state, []}

  # ============================================================================
  # Tick (timer)
  # ============================================================================

  @impl true
  def tick(%{status: status} = state) when status in [:choosing, :drawing, :round_end] do
    new_remaining = state.time_left_ms - @tick_ms

    cond do
      new_remaining <= 0 and state.status == :choosing ->
        first = List.first(state.word_choices) || pick_words() |> hd()

        new_state = %{state | status: :drawing, word: first, time_left_ms: @drawing_ms}

        {:ok, new_state,
         [{:word_chosen, %{drawer: state.drawer_id, length: String.length(first), auto: true}}]}

      new_remaining <= 0 and state.status == :drawing ->
        ended = end_round(state, :timeout)
        {:ok, ended, [{:round_end, %{reason: :timeout, word: state.word}}]}

      new_remaining <= 0 and state.status == :round_end ->
        next_round(state)

      # 1초 boundary 마다만 broadcast — pubsub 폭주 방지.
      true ->
        old_sec = div(state.time_left_ms, 1000)
        new_sec = div(new_remaining, 1000)
        broadcasts = if old_sec != new_sec, do: [{:tick, new_remaining}], else: []
        {:ok, %{state | time_left_ms: new_remaining}, broadcasts}
    end
  end

  def tick(state), do: {:ok, state, []}

  # ============================================================================
  # Game over
  # ============================================================================

  @impl true
  def game_over?(%{status: :over} = state) do
    public_players =
      Map.new(state.players, fn {id, p} ->
        {id, %{nickname: p.nickname, score: p.score}}
      end)

    {:yes, %{winner: state.winner_id, players: public_players}}
  end

  def game_over?(_), do: :no

  @impl true
  def terminate(_, _), do: :ok

  # Sprint 5b — 그리는 / 라운드 진행 중 만 카운트. waiting / over X.
  def playing?(%{status: status}) when status in [:choosing, :drawing, :round_end], do: true
  def playing?(_), do: false

  # ============================================================================
  # Round transitions
  # ============================================================================

  defp start_choosing(state) do
    drawer_id = pick_next_drawer(state)
    word_choices = pick_words()

    new_state = %{
      state
      | status: :choosing,
        drawer_id: drawer_id,
        word: nil,
        word_choices: word_choices,
        word_revealed: false,
        time_left_ms: @choosing_ms,
        strokes: [],
        round_no: state.round_no + 1,
        players: Map.new(state.players, fn {id, p} -> {id, %{p | guessed_at: nil}} end)
    }

    {:ok, new_state,
     [
       {:round_start, %{drawer: drawer_id, round_no: new_state.round_no}},
       {:word_choices, %{drawer: drawer_id, choices: word_choices}}
     ]}
  end

  defp end_round(state, _reason) do
    # drawer bonus = 맞춘 사람당 +50.
    guessed_count = state.players |> Map.values() |> Enum.count(& &1.guessed_at)
    drawer_bonus = guessed_count * 50

    new_drawn_count =
      if state.drawer_id,
        do: Map.update(state.drawn_count, state.drawer_id, 1, &(&1 + 1)),
        else: state.drawn_count

    new_players =
      if state.drawer_id && Map.has_key?(state.players, state.drawer_id) do
        Map.update!(state.players, state.drawer_id, fn p ->
          %{p | score: p.score + drawer_bonus, was_drawer: true}
        end)
      else
        state.players
      end

    %{
      state
      | status: :round_end,
        time_left_ms: @round_end_ms,
        word_revealed: true,
        players: new_players,
        drawn_count: new_drawn_count
    }
  end

  defp next_round(state) do
    cond do
      # 총 N 라운드 끝났거나 player 모자라 → :over.
      state.round_no >= @total_rounds or map_size(state.players) < 2 ->
        winner = highest_scorer(state.players)
        new_state = %{state | status: :over, winner_id: winner}
        {:ok, new_state, [{:game_finished, %{winner: winner}}]}

      true ->
        start_choosing(state)
    end
  end

  # 가장 적게 그린 사람부터 round-robin. 동률 시 player_id 알파벳 순.
  # → 2명 게임 5라운드 = p1, p2, p1, p2, p1 (3:2 분배).
  defp pick_next_drawer(state) do
    state.players
    |> Map.keys()
    |> Enum.sort()
    |> Enum.min_by(&Map.get(state.drawn_count, &1, 0), fn -> nil end)
  end

  defp pick_words do
    @word_pool |> Enum.take_random(3)
  end

  defp highest_scorer(players) when map_size(players) == 0, do: nil

  defp highest_scorer(players) do
    {id, _} = Enum.max_by(players, fn {_, p} -> p.score end)
    id
  end

  # ============================================================================
  # Guessing
  # ============================================================================

  defp correct_guess?(text, word) when is_binary(text) and is_binary(word) do
    String.trim(text) == String.trim(word)
  end

  defp correct_guess?(_, _), do: false

  defp already_guessed?(state, player_id) do
    case state.players[player_id] do
      %{guessed_at: at} when not is_nil(at) -> true
      _ -> false
    end
  end

  # 점수: 빨리 맞출수록 더 큼. 남은 time / total = 0..1 → 50~150 점.
  defp award_correct(state, player_id) do
    ratio = state.time_left_ms / @drawing_ms
    points = round(50 + 100 * ratio)
    now = DateTime.utc_now() |> DateTime.truncate(:millisecond)

    new_players =
      Map.update!(state.players, player_id, fn p ->
        %{p | guessed_at: now, score: p.score + points}
      end)

    new_state = %{state | players: new_players}

    non_drawer_ids = new_players |> Map.keys() |> Enum.reject(&(&1 == state.drawer_id))

    all_guessed? =
      non_drawer_ids != [] and
        Enum.all?(non_drawer_ids, fn id -> new_players[id].guessed_at end)

    broadcasts = [
      {:correct_guess, %{player: player_id, points: points, score: new_players[player_id].score}}
    ]

    if all_guessed? do
      ended = end_round(new_state, :all_guessed)

      {:ok, ended, broadcasts ++ [{:round_end, %{reason: :all_guessed, word: state.word}}]}
    else
      {:ok, new_state, broadcasts}
    end
  end

  defp push_message(state, player_id, text) when is_binary(text) do
    text = String.slice(String.trim(text), 0, 200)

    if text == "" do
      {:ok, state, []}
    else
      msg = %{
        player: player_id,
        nickname: get_in(state.players, [player_id, :nickname]) || "anon",
        text: text,
        ts: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      new_messages = [msg | state.messages] |> Enum.take(50)
      {:ok, %{state | messages: new_messages}, [{:message, msg}]}
    end
  end

  defp push_message(state, _, _), do: {:ok, state, []}

  # ============================================================================
  # Stroke sanitization
  # ============================================================================

  defp sanitize_stroke(stroke) do
    %{
      "from" => sanitize_point(stroke["from"]),
      "to" => sanitize_point(stroke["to"]),
      "color" => sanitize_color(stroke["color"]),
      "size" => sanitize_size(stroke["size"])
    }
  end

  defp sanitize_point(%{"x" => x, "y" => y}) when is_number(x) and is_number(y) do
    %{"x" => clamp_num(x, 0, 2000), "y" => clamp_num(y, 0, 2000)}
  end

  defp sanitize_point(_), do: %{"x" => 0, "y" => 0}

  defp sanitize_color("#" <> hex = c) when byte_size(c) in [4, 7] do
    if String.match?(hex, ~r/^[0-9a-fA-F]+$/), do: c, else: "#000000"
  end

  defp sanitize_color(_), do: "#000000"

  defp sanitize_size(s) when is_integer(s), do: clamp_int(s, 1, 30)
  defp sanitize_size(_), do: 4

  defp clamp_num(n, lo, hi), do: n |> max(lo) |> min(hi)
  defp clamp_int(n, lo, hi), do: n |> max(lo) |> min(hi)
end
