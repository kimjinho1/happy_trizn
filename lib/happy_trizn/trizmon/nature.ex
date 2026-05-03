defmodule HappyTrizn.Trizmon.Nature do
  @moduledoc """
  성격 (nature) 25 종 — Sprint 5c-1.

  각 nature 가 stat 1개 +10% / 다른 stat 1개 -10% (HP 제외).
  이름 = 영문 atom (포켓몬 컨벤션). 한글 표시 = `display_name/1`.

  spec: docs/TRIZMON_SPEC.md §4 stats 계산
  """

  # {nature, increased_stat, decreased_stat}
  # neutral nature 는 increased == decreased 또는 둘 다 nil → mult 1.0.
  @natures [
    # neutral 5종
    {:hardy, nil, nil},
    {:docile, nil, nil},
    {:serious, nil, nil},
    {:bashful, nil, nil},
    {:quirky, nil, nil},

    # +atk
    {:lonely, :atk, :def},
    {:adamant, :atk, :spa},
    {:naughty, :atk, :spd},
    {:brave, :atk, :spe},

    # +def
    {:bold, :def, :atk},
    {:impish, :def, :spa},
    {:lax, :def, :spd},
    {:relaxed, :def, :spe},

    # +spa
    {:modest, :spa, :atk},
    {:mild, :spa, :def},
    {:rash, :spa, :spd},
    {:quiet, :spa, :spe},

    # +spd
    {:calm, :spd, :atk},
    {:gentle, :spd, :def},
    {:careful, :spd, :spa},
    {:sassy, :spd, :spe},

    # +spe
    {:timid, :spe, :atk},
    {:hasty, :spe, :def},
    {:jolly, :spe, :spa},
    {:naive, :spe, :spd}
  ]

  @display %{
    hardy: "노력",
    docile: "온순",
    serious: "성실",
    bashful: "수줍음",
    quirky: "변덕",
    lonely: "외로움",
    adamant: "고집",
    naughty: "장난",
    brave: "용감",
    bold: "대담",
    impish: "장난꾸러기",
    lax: "무사태평",
    relaxed: "느긋",
    modest: "조심",
    mild: "온화",
    rash: "촐랑",
    quiet: "냉정",
    calm: "차분",
    gentle: "얌전",
    careful: "신중",
    sassy: "건방",
    timid: "겁쟁이",
    hasty: "성급",
    jolly: "명랑",
    naive: "천진"
  }

  @doc "25 nature atom list."
  def all, do: Enum.map(@natures, fn {n, _, _} -> n end)

  @doc "nature 한글 표시."
  def display_name(nature) when is_atom(nature), do: Map.get(@display, nature, "?")

  @doc """
  특정 stat 의 nature modifier — 1.1 / 0.9 / 1.0.
  HP 는 항상 1.0.
  """
  def modifier(_nature, :hp), do: 1.0

  def modifier(nature, stat) when is_atom(nature) and is_atom(stat) do
    case Enum.find(@natures, fn {n, _, _} -> n == nature end) do
      nil -> 1.0
      {_, ^stat, _} -> 1.1
      {_, _, ^stat} -> 0.9
      _ -> 1.0
    end
  end

  @doc "string → atom."
  def from_slug(slug) when is_binary(slug) do
    case Enum.find(@natures, fn {n, _, _} -> Atom.to_string(n) == slug end) do
      nil -> nil
      {n, _, _} -> n
    end
  end

  def from_slug(_), do: nil

  @doc "랜덤 nature (인스턴스 생성 시)."
  def random, do: Enum.random(all())
end
