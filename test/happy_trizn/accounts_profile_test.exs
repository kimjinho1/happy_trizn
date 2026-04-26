defmodule HappyTrizn.Accounts.ProfileTest do
  use HappyTrizn.DataCase, async: true

  alias HappyTrizn.Accounts

  defp create_user(opts \\ []) do
    n = System.unique_integer([:positive])

    {:ok, u} =
      Accounts.register_user(%{
        email: "p#{n}@trizn.kr",
        nickname: "p#{n}",
        password: "hello12345"
      })

    u = Map.merge(u, Map.new(opts))
    u
  end

  describe "update_profile/2" do
    test "닉네임 변경 + avatar_url 저장" do
      u = create_user()

      assert {:ok, updated} =
               Accounts.update_profile(u, %{
                 "nickname" => "newnick_#{u.id |> binary_part(0, 8)}",
                 "avatar_url" => "/uploads/avatars/#{u.id}.png"
               })

      assert updated.nickname =~ "newnick_"
      assert updated.avatar_url =~ "/uploads/avatars/"
    end

    test "닉네임 길이 < 2 거부" do
      u = create_user()
      assert {:error, cs} = Accounts.update_profile(u, %{"nickname" => "a"})
      assert {_, _} = cs.errors[:nickname]
    end

    test "닉네임 한국어 OK" do
      u = create_user()
      n = System.unique_integer([:positive])
      assert {:ok, updated} = Accounts.update_profile(u, %{"nickname" => "유저#{n}"})
      assert updated.nickname =~ "유저"
    end

    test "공백 / 특수문자 거부" do
      u = create_user()
      assert {:error, cs} = Accounts.update_profile(u, %{"nickname" => "no spaces"})
      assert {_, _} = cs.errors[:nickname]
    end

    test "다른 사용자 닉네임 사용 불가 (unique)" do
      u1 = create_user()
      u2 = create_user()
      assert {:error, cs} = Accounts.update_profile(u2, %{"nickname" => u1.nickname})
      assert {_, _} = cs.errors[:nickname]
    end

    test "avatar_url nil 으로 삭제" do
      u = create_user()
      {:ok, with_avatar} = Accounts.update_profile(u, %{"avatar_url" => "/uploads/avatars/x.png"})
      assert with_avatar.avatar_url

      {:ok, cleared} = Accounts.update_profile(with_avatar, %{"avatar_url" => nil})
      assert is_nil(cleared.avatar_url)
    end
  end
end
