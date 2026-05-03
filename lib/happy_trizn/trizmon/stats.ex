defmodule HappyTrizn.Trizmon.Stats do
  @moduledoc """
  몬스터 stats 계산 (Sprint 5c-1).

  포켓몬 컨벤션 공식:
    HP = floor((2*base + IV + ev/4) * level / 100) + level + 10
    기타 = (floor((2*base + IV + ev/4) * level / 100) + 5) * nature_modifier

  spec: docs/TRIZMON_SPEC.md §4
  """

  alias HappyTrizn.Trizmon.Nature

  @doc """
  HP 계산.

      iex> HappyTrizn.Trizmon.Stats.hp(%{base: 45, iv: 31, ev: 0, level: 50})
      120
  """
  def hp(%{base: base, iv: iv, ev: ev, level: level}) do
    floor((2 * base + iv + div(ev, 4)) * level / 100) + level + 10
  end

  @doc """
  HP 외 stat (atk/def/spa/spd/spe) 계산. nature modifier 적용.

      iex> HappyTrizn.Trizmon.Stats.stat(%{base: 49, iv: 31, ev: 0, level: 50, nature: :hardy, stat: :atk})
      69
  """
  def stat(%{base: base, iv: iv, ev: ev, level: level, nature: nature, stat: stat_key})
      when stat_key in [:atk, :def, :spa, :spd, :spe] do
    raw = floor((2 * base + iv + div(ev, 4)) * level / 100) + 5
    floor(raw * Nature.modifier(nature, stat_key))
  end

  @doc """
  Instance map (DB row 구조) → 6 stat 한 번에. species 의 base + instance 의 IV/EV/level/nature.

  return: %{hp: int, atk: int, def: int, spa: int, spd: int, spe: int}
  """
  def all_stats(instance, species) do
    nature = parse_nature(instance.nature)

    %{
      hp:
        hp(%{
          base: species.base_hp,
          iv: instance.iv_hp,
          ev: instance.ev_hp,
          level: instance.level
        }),
      atk:
        stat(%{
          base: species.base_atk,
          iv: instance.iv_atk,
          ev: instance.ev_atk,
          level: instance.level,
          nature: nature,
          stat: :atk
        }),
      def:
        stat(%{
          base: species.base_def,
          iv: instance.iv_def,
          ev: instance.ev_def,
          level: instance.level,
          nature: nature,
          stat: :def
        }),
      spa:
        stat(%{
          base: species.base_spa,
          iv: instance.iv_spa,
          ev: instance.ev_spa,
          level: instance.level,
          nature: nature,
          stat: :spa
        }),
      spd:
        stat(%{
          base: species.base_spd,
          iv: instance.iv_spd,
          ev: instance.ev_spd,
          level: instance.level,
          nature: nature,
          stat: :spd
        }),
      spe:
        stat(%{
          base: species.base_spe,
          iv: instance.iv_spe,
          ev: instance.ev_spe,
          level: instance.level,
          nature: nature,
          stat: :spe
        })
    }
  end

  @doc "Instance row 의 nature 가 string 이면 atom 으로."
  def parse_nature(n) when is_atom(n), do: n
  def parse_nature(n) when is_binary(n), do: Nature.from_slug(n) || :hardy
  def parse_nature(_), do: :hardy

  @doc "랜덤 IV (0..31). 인스턴스 생성 시 6개 stat 모두."
  def random_ivs do
    %{
      iv_hp: :rand.uniform(32) - 1,
      iv_atk: :rand.uniform(32) - 1,
      iv_def: :rand.uniform(32) - 1,
      iv_spa: :rand.uniform(32) - 1,
      iv_spd: :rand.uniform(32) - 1,
      iv_spe: :rand.uniform(32) - 1
    }
  end
end
