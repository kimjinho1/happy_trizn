defmodule HappyTrizn.Trizmon.Pokedex do
  @moduledoc """
  도감 entry 관리 (Sprint 5c-3d).

  trizmon_pokedex_entries table — 사용자 + 종 별 1 row. status :seen / :caught.
  잡기 성공 시 mark_caught (자동 first_seen_at 도 채움). 야생 인카운터 / 배틀
  시 mark_seen.

  spec: docs/TRIZMON_SPEC.md §12
  """

  import Ecto.Query

  alias HappyTrizn.Repo

  @table "trizmon_pokedex_entries"

  @doc """
  본 적 등록. 이미 있으면 noop (status 보존). 처음이면 :seen 으로 insert.
  """
  def mark_seen!(user_id, species_id) when is_binary(user_id) and is_integer(species_id) do
    uid_bin = dump_uuid!(user_id)

    if exists?(uid_bin, species_id) do
      :ok
    else
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.insert_all(@table, [
        %{
          user_id: uid_bin,
          species_id: species_id,
          status: "seen",
          first_seen_at: now,
          first_caught_at: nil
        }
      ])

      :ok
    end
  end

  @doc """
  잡기 성공 등록. 기존 entry 있으면 status :caught + first_caught_at 갱신.
  없으면 새 row (seen + caught 동시).
  """
  def mark_caught!(user_id, species_id) when is_binary(user_id) and is_integer(species_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    uid_bin = dump_uuid!(user_id)

    case Repo.one(
           from p in @table,
             where: p.user_id == ^uid_bin and p.species_id == ^species_id,
             select: %{status: p.status, first_caught_at: p.first_caught_at}
         ) do
      nil ->
        Repo.insert_all(@table, [
          %{
            user_id: uid_bin,
            species_id: species_id,
            status: "caught",
            first_seen_at: now,
            first_caught_at: now
          }
        ])

      %{status: "caught"} ->
        :ok

      _ ->
        Repo.update_all(
          from(p in @table,
            where: p.user_id == ^uid_bin and p.species_id == ^species_id
          ),
          set: [status: "caught", first_caught_at: now]
        )
    end

    :ok
  end

  @doc """
  사용자 도감 list. species 정보 join. 정렬 by species.id.

  return: [%{species_id, slug, name_ko, type1, type2, status, first_seen_at,
              first_caught_at, image_url}]
  """
  def list_for_user(user_id) when is_binary(user_id) do
    uid_bin = dump_uuid!(user_id)

    Repo.all(
      from p in @table,
        join: s in "trizmon_species",
        on: s.id == p.species_id,
        where: p.user_id == ^uid_bin,
        order_by: [asc: s.id],
        select: %{
          species_id: p.species_id,
          slug: s.slug,
          name_ko: s.name_ko,
          type1: s.type1,
          type2: s.type2,
          status: p.status,
          first_seen_at: p.first_seen_at,
          first_caught_at: p.first_caught_at,
          image_url: s.image_url
        }
    )
  end

  @doc "사용자 잡은 종 수 / 본 종 수."
  def stats_for_user(user_id) when is_binary(user_id) do
    uid_bin = dump_uuid!(user_id)

    Repo.one(
      from p in @table,
        where: p.user_id == ^uid_bin,
        select: %{
          seen_count: count(p.species_id),
          caught_count: count(fragment("CASE WHEN ? = 'caught' THEN 1 END", p.status))
        }
    )
  end

  defp exists?(uid_bin, species_id) when is_binary(uid_bin) do
    Repo.exists?(
      from p in @table,
        where: p.user_id == ^uid_bin and p.species_id == ^species_id
    )
  end

  # binary_id field — Repo.insert_all raw map 시 자동 cast X. UUID string → 16 byte
  # binary 로 dump 필요. ecto query (where) 는 자동 cast 되므로 read 는 OK.
  defp dump_uuid!(uuid) when is_binary(uuid) do
    case Ecto.UUID.dump(uuid) do
      {:ok, bin} -> bin
      :error -> raise "invalid uuid: #{inspect(uuid)}"
    end
  end
end
