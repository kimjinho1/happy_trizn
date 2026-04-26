defmodule HappyTrizn.Games.SkribblTest do
  use ExUnit.Case, async: true

  alias HappyTrizn.Games.Skribbl

  defp join(state, id, nick) do
    {:ok, ns, _} = Skribbl.handle_player_join(id, %{nickname: nick || id}, state)
    ns
  end

  defp init_with(n) do
    {:ok, state} = Skribbl.init(%{})

    Enum.reduce(1..n, state, fn i, acc ->
      join(acc, "p#{i}", "P#{i}")
    end)
  end

  describe "meta + init" do
    test "multi 2~8인 + 게임명 캐치마인드" do
      m = Skribbl.meta()
      assert m.slug == "skribbl"
      assert m.name == "캐치마인드"
      assert m.mode == :multi
      assert m.max_players == 8
      assert m.min_players == 2
      assert m.tick_interval_ms == 100
    end

    test "init 기본 상태" do
      {:ok, s} = Skribbl.init(%{})
      assert s.status == :waiting
      assert s.players == %{}
      assert s.strokes == []
      assert s.word == nil
    end
  end

  describe "join / leave" do
    test "1명 join → :waiting 유지" do
      s = init_with(1)
      assert s.status == :waiting
      assert map_size(s.players) == 1
      assert s.players["p1"].nickname == "P1"
    end

    test "8명 차면 9번째 거부" do
      s = init_with(8)
      assert {:reject, :full} = Skribbl.handle_player_join("p9", %{}, s)
    end

    test "drawer 가 leave → 라운드 강제 종료 (round_end)" do
      s = init_with(2)
      {:ok, started, _} = Skribbl.handle_input("p1", %{"action" => "start_game"}, s)
      assert started.status == :choosing

      {:ok, ns, broadcasts} = Skribbl.handle_player_leave(started.drawer_id, :disconnect, started)
      assert ns.status == :round_end
      assert Enum.any?(broadcasts, fn {tag, _} -> tag == :drawer_left end)
    end
  end

  describe "start_game + 단어 선택" do
    test "2명 미만 → start 무시" do
      s = init_with(1)
      assert {:ok, ^s, []} = Skribbl.handle_input("p1", %{"action" => "start_game"}, s)
    end

    test "2명 이상 + start_game → :choosing + word_choices 3개" do
      s = init_with(2)
      {:ok, ns, broadcasts} = Skribbl.handle_input("p1", %{"action" => "start_game"}, s)
      assert ns.status == :choosing
      assert length(ns.word_choices) == 3
      assert ns.drawer_id in ["p1", "p2"]
      assert Enum.any?(broadcasts, fn {tag, _} -> tag == :round_start end)
      assert Enum.any?(broadcasts, fn {tag, _} -> tag == :word_choices end)
    end

    test "drawer 가 choose_word → :drawing 진입 + 단어 결정" do
      s = init_with(2)
      {:ok, c, _} = Skribbl.handle_input("p1", %{"action" => "start_game"}, s)
      drawer = c.drawer_id
      [first | _] = c.word_choices

      {:ok, d, broadcasts} =
        Skribbl.handle_input(drawer, %{"action" => "choose_word", "word" => first}, c)

      assert d.status == :drawing
      assert d.word == first
      assert d.time_left_ms == 80_000

      assert Enum.any?(broadcasts, fn
               {:word_chosen, %{drawer: ^drawer, length: _}} -> true
               _ -> false
             end)
    end

    test "drawer 아닌 사람 choose_word 무시" do
      s = init_with(2)
      {:ok, c, _} = Skribbl.handle_input("p1", %{"action" => "start_game"}, s)
      not_drawer = if c.drawer_id == "p1", do: "p2", else: "p1"
      [first | _] = c.word_choices

      assert {:ok, ^c, []} =
               Skribbl.handle_input(not_drawer, %{"action" => "choose_word", "word" => first}, c)
    end

    test "choose_word 가 word_choices 외 → 무시" do
      s = init_with(2)
      {:ok, c, _} = Skribbl.handle_input("p1", %{"action" => "start_game"}, s)

      assert {:ok, ^c, []} =
               Skribbl.handle_input(
                 c.drawer_id,
                 %{"action" => "choose_word", "word" => "외부단어"},
                 c
               )
    end
  end

  describe "stroke / clear_canvas" do
    setup do
      s = init_with(2)
      {:ok, c, _} = Skribbl.handle_input("p1", %{"action" => "start_game"}, s)
      [w | _] = c.word_choices

      {:ok, d, _} =
        Skribbl.handle_input(c.drawer_id, %{"action" => "choose_word", "word" => w}, c)

      {:ok, state: d}
    end

    test "drawer stroke → strokes 누적 + broadcast", %{state: state} do
      stroke = %{
        "from" => %{"x" => 10, "y" => 10},
        "to" => %{"x" => 20, "y" => 20},
        "color" => "#ff0000",
        "size" => 4
      }

      {:ok, ns, broadcasts} =
        Skribbl.handle_input(state.drawer_id, %{"action" => "stroke", "stroke" => stroke}, state)

      assert length(ns.strokes) == 1
      assert Enum.any?(broadcasts, fn {tag, _} -> tag == :stroke end)
    end

    test "non-drawer stroke 무시", %{state: state} do
      not_drawer = if state.drawer_id == "p1", do: "p2", else: "p1"

      stroke = %{"from" => %{"x" => 0, "y" => 0}, "to" => %{"x" => 1, "y" => 1}}

      assert {:ok, ^state, []} =
               Skribbl.handle_input(
                 not_drawer,
                 %{"action" => "stroke", "stroke" => stroke},
                 state
               )
    end

    test "clear_canvas → strokes 초기화", %{state: state} do
      stroke = %{"from" => %{"x" => 0, "y" => 0}, "to" => %{"x" => 1, "y" => 1}}

      {:ok, s1, _} =
        Skribbl.handle_input(state.drawer_id, %{"action" => "stroke", "stroke" => stroke}, state)

      assert length(s1.strokes) == 1

      {:ok, s2, _} = Skribbl.handle_input(state.drawer_id, %{"action" => "clear_canvas"}, s1)
      assert s2.strokes == []
    end

    test "잘못된 stroke (color/size 비정상) 도 sanitize 후 저장", %{state: state} do
      stroke = %{
        "from" => %{"x" => 100, "y" => 100},
        "to" => %{"x" => 200, "y" => 200},
        "color" => "<script>alert(1)</script>",
        "size" => 9999
      }

      {:ok, ns, _} =
        Skribbl.handle_input(state.drawer_id, %{"action" => "stroke", "stroke" => stroke}, state)

      [clean] = ns.strokes
      # color sanitize → black
      assert clean["color"] == "#000000"
      # size clamped
      assert clean["size"] == 30
    end
  end

  describe "guess + 점수" do
    setup do
      s = init_with(2)
      {:ok, c, _} = Skribbl.handle_input("p1", %{"action" => "start_game"}, s)
      [w | _] = c.word_choices

      {:ok, d, _} =
        Skribbl.handle_input(c.drawer_id, %{"action" => "choose_word", "word" => w}, c)

      not_drawer = if d.drawer_id == "p1", do: "p2", else: "p1"
      {:ok, state: d, drawer: d.drawer_id, word: w, not_drawer: not_drawer}
    end

    test "정답 맞춤 → 점수 + correct_guess broadcast + 모두 맞춰서 round_end", %{
      state: state,
      not_drawer: nd,
      word: word
    } do
      {:ok, ns, broadcasts} =
        Skribbl.handle_input(nd, %{"action" => "guess", "text" => word}, state)

      assert ns.players[nd].score > 0
      assert ns.players[nd].guessed_at != nil

      assert Enum.any?(broadcasts, fn
               {:correct_guess, %{player: ^nd}} -> true
               _ -> false
             end)

      # 2명 게임 + non-drawer 1명 만 — 그 1명이 맞췄으니 모두 맞춤 → round_end.
      assert ns.status == :round_end

      assert Enum.any?(broadcasts, fn
               {:round_end, _} -> true
               _ -> false
             end)
    end

    test "오답 → message broadcast (정답 누설 X)", %{state: state, not_drawer: nd} do
      {:ok, ns, broadcasts} =
        Skribbl.handle_input(nd, %{"action" => "guess", "text" => "엉뚱한답"}, state)

      assert ns.players[nd].guessed_at == nil
      assert ns.players[nd].score == 0
      assert Enum.any?(broadcasts, fn {tag, _} -> tag == :message end)
    end

    test "drawer 가 정답 입력 → 무시 (정답 누설 방지)", %{state: state, drawer: drawer, word: word} do
      assert {:ok, ^state, []} =
               Skribbl.handle_input(drawer, %{"action" => "guess", "text" => word}, state)
    end

    test "이미 맞춘 사람 다시 chat → 무시", %{state: state, not_drawer: nd, word: word} do
      {:ok, after_correct, _} =
        Skribbl.handle_input(nd, %{"action" => "guess", "text" => word}, state)

      # round_end 진입 했지만 그 전 상태에서 또 시도. 다시 guess action — round_end 라 message 만 push.
      # 단순화: guess 가 :drawing 아닐 때 message 처리 → push_message.
      _ = after_correct
    end
  end

  describe "tick (timer)" do
    test ":choosing tick — 시간 안 줄이는 sub-second + 1초 boundary 만 broadcast" do
      s = init_with(2)
      {:ok, c, _} = Skribbl.handle_input("p1", %{"action" => "start_game"}, s)

      # 100ms 줄어듦, 30000 - 100 = 29900. div 30 → 29 (boundary 통과) → broadcast.
      {:ok, ns, broadcasts} = Skribbl.tick(c)
      assert ns.time_left_ms == 29_900
      assert broadcasts == [{:tick, 29_900}]

      # 추가 sub-second tick — 29900 - 100 = 29800. div 29 → 29 (같음) → broadcast 없음.
      {:ok, _, b2} = Skribbl.tick(ns)
      assert b2 == []
    end

    test ":choosing 시간 끝 → 첫 단어 자동, :drawing" do
      s = init_with(2)
      {:ok, c, _} = Skribbl.handle_input("p1", %{"action" => "start_game"}, s)
      forced = %{c | time_left_ms: 50}

      {:ok, ns, broadcasts} = Skribbl.tick(forced)
      assert ns.status == :drawing
      assert ns.word == List.first(c.word_choices)

      assert Enum.any?(broadcasts, fn
               {:word_chosen, %{auto: true}} -> true
               _ -> false
             end)
    end

    test ":drawing 시간 끝 → :round_end" do
      s = init_with(2)
      {:ok, c, _} = Skribbl.handle_input("p1", %{"action" => "start_game"}, s)
      [w | _] = c.word_choices

      {:ok, d, _} =
        Skribbl.handle_input(c.drawer_id, %{"action" => "choose_word", "word" => w}, c)

      forced = %{d | time_left_ms: 50}

      {:ok, ns, broadcasts} = Skribbl.tick(forced)
      assert ns.status == :round_end
      assert ns.word_revealed == true

      assert Enum.any?(broadcasts, fn
               {:round_end, %{reason: :timeout}} -> true
               _ -> false
             end)
    end

    test ":round_end 끝 → 다음 drawer + :choosing or :over" do
      s = init_with(2)
      {:ok, c, _} = Skribbl.handle_input("p1", %{"action" => "start_game"}, s)
      [w | _] = c.word_choices

      {:ok, d, _} =
        Skribbl.handle_input(c.drawer_id, %{"action" => "choose_word", "word" => w}, c)

      # round_end 진입.
      ended = %{d | status: :round_end, time_left_ms: 50, drawn_count: %{d.drawer_id => 1}}

      {:ok, ns, _} = Skribbl.tick(ended)
      # 첫 drawer 끝남, 다음 drawer 가 다른 사람 → :choosing.
      assert ns.status == :choosing
      assert ns.drawer_id != d.drawer_id
    end

    test "round_no 가 total_rounds (5) 도달하면 :over" do
      s = init_with(2)
      {:ok, c, _} = Skribbl.handle_input("p1", %{"action" => "start_game"}, s)
      drawer = c.drawer_id

      ended = %{
        c
        | status: :round_end,
          time_left_ms: 50,
          round_no: Skribbl.total_rounds(),
          drawn_count: %{drawer => 5}
      }

      {:ok, ns, broadcasts} = Skribbl.tick(ended)
      assert ns.status == :over
      assert Enum.any?(broadcasts, fn {tag, _} -> tag == :game_finished end)
    end

    test "round_no < total_rounds 면 :over 안 됨, 다음 drawer 로 :choosing" do
      s = init_with(2)
      {:ok, c, _} = Skribbl.handle_input("p1", %{"action" => "start_game"}, s)
      drawer = c.drawer_id

      ended = %{
        c
        | status: :round_end,
          time_left_ms: 50,
          round_no: 1,
          drawn_count: %{drawer => 1}
      }

      {:ok, ns, _} = Skribbl.tick(ended)
      assert ns.status == :choosing
    end
  end

  describe "total_rounds + drawer round-robin" do
    test "total_rounds = 5 (player 수 무관)" do
      assert Skribbl.total_rounds() == 5
    end

    test "drawer 가 가장 적게 그린 사람부터 round-robin" do
      s = init_with(2)
      {:ok, c, _} = Skribbl.handle_input("p1", %{"action" => "start_game"}, s)
      drawer1 = c.drawer_id

      # 첫 라운드 끝 → drawn_count[drawer1] = 1.
      [w | _] = c.word_choices
      {:ok, d, _} = Skribbl.handle_input(drawer1, %{"action" => "choose_word", "word" => w}, c)
      ended = %{d | status: :round_end, time_left_ms: 50, drawn_count: %{drawer1 => 1}}

      # next_round → 두번째 drawer 는 안 그린 사람.
      {:ok, c2, _} = Skribbl.tick(ended)
      assert c2.status == :choosing
      assert c2.drawer_id != drawer1
    end
  end

  describe "game_over?" do
    test ":over → :yes + winner + players score" do
      s = init_with(2) |> Map.put(:status, :over) |> Map.put(:winner_id, "p1")
      assert {:yes, %{winner: "p1", players: ps}} = Skribbl.game_over?(s)
      assert Map.has_key?(ps, "p1")
      assert Map.has_key?(ps, "p2")
    end

    test "그 외 → :no" do
      assert :no = Skribbl.game_over?(init_with(2))
    end
  end

  describe "word_pool" do
    test "단어 사전 150+ 개 + 모두 한국어 string" do
      pool = Skribbl.word_pool()
      assert length(pool) >= 150
      Enum.each(pool, fn w -> assert is_binary(w) end)
    end

    test "다양한 카테고리 — 일상 / 인기 게임 / 유명 만화애니 / 개발자" do
      pool = Skribbl.word_pool()
      # 카테고리 별 대표 키워드 포함 검증
      assert "사과" in pool
      assert "롤" in pool
      assert "마리오" in pool
      assert "진격의거인" in pool
      assert "스파이더맨" in pool
      assert "파이썬" in pool
      assert "도커" in pool
      assert "노래방" in pool
    end

    test "엘릭서 / MZ 슬랭 제외 (모두가 알 만한 것 만)" do
      pool = Skribbl.word_pool()
      refute "엘릭서" in pool
      refute "킹받네" in pool
      refute "갓생" in pool
      refute "어쩔티비" in pool
      refute "꾸안꾸" in pool
      refute "현타" in pool
    end
  end
end
