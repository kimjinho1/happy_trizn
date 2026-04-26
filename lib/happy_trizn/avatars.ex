defmodule HappyTrizn.Avatars do
  @moduledoc """
  Avatar 업로드 / 삭제 헬퍼.

  저장 경로: `priv/static/uploads/avatars/<user_id>.<ext>` — Plug.Static 으로
  `/uploads/avatars/<user_id>.<ext>` 로 노출.

  멀티 ext (png/jpg) 지원 — 새로 올리면 기존 파일 (다른 ext 포함) 모두 삭제.
  """

  @app :happy_trizn
  @uploads_subdir "uploads/avatars"
  @allowed_exts ~w(.png .jpg .jpeg .webp)

  @doc "단일 origin path 의 file 을 user 의 avatar 로 install. /uploads/... URL 반환."
  def install(user_id, src_path, ext) when is_binary(user_id) and is_binary(src_path) do
    ext = String.downcase(ext)

    cond do
      ext not in @allowed_exts ->
        {:error, :invalid_ext}

      not File.exists?(src_path) ->
        {:error, :no_src}

      true ->
        # 이전 avatar 들 모두 삭제 (ext 바뀌었을 수 있음).
        delete_existing(user_id)

        dest_dir = uploads_dir()
        File.mkdir_p!(dest_dir)
        dest = Path.join(dest_dir, "#{user_id}#{ext}")
        File.cp!(src_path, dest)

        {:ok, "/#{@uploads_subdir}/#{user_id}#{ext}"}
    end
  end

  @doc "user 의 모든 avatar 파일 제거."
  def delete_existing(user_id) when is_binary(user_id) do
    dir = uploads_dir()

    case File.ls(dir) do
      {:ok, files} ->
        Enum.each(files, fn name ->
          if String.starts_with?(name, user_id <> "."),
            do: File.rm(Path.join(dir, name))
        end)

      _ ->
        :ok
    end
  end

  @doc "허용 확장자 목록 (MIME 까지 검증은 LiveView upload 단계에서)."
  def allowed_exts, do: @allowed_exts

  defp uploads_dir do
    Path.join(:code.priv_dir(@app) |> to_string(), "static/#{@uploads_subdir}")
  end
end
