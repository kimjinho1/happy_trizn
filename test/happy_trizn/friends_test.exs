defmodule HappyTrizn.FriendsTest do
  use HappyTrizn.DataCase, async: false
  # Cachex 가 shared state 라 async: false

  alias HappyTrizn.Friends
  alias HappyTrizn.Friends.Friendship

  defp register!(suffix) do
    {:ok, u} =
      HappyTrizn.Accounts.register_user(%{
        email: "u#{suffix}@trizn.kr",
        nickname: "u#{suffix}",
        password: "hello12345"
      })

    u
  end

  setup do
    Cachex.clear(:recommendations_cache)
    {:ok, alice: register!(System.unique_integer([:positive])), bob: register!(System.unique_integer([:positive]))}
  end

  describe "send_request/2" do
    test "정상 요청 → pending row 생성", %{alice: alice, bob: bob} do
      assert {:ok, %Friendship{} = f} = Friends.send_request(alice, bob)
      assert f.status == "pending"
      assert f.requested_by == alice.id
    end

    test "canonical 정렬 (역순도 같은 row)", %{alice: alice, bob: bob} do
      {:ok, f1} = Friends.send_request(alice, bob)
      assert {:ok, :already_pending} = Friends.send_request(bob, alice)

      f_check = Friends.get_friendship_between(bob, alice)
      assert f_check.id == f1.id
    end

    test "자기 자신 거부", %{alice: alice} do
      assert {:error, :self} = Friends.send_request(alice, alice)
    end

    test "이미 accepted 면 already_accepted", %{alice: alice, bob: bob} do
      {:ok, f} = Friends.send_request(alice, bob)
      {:ok, _} = Friends.accept(bob, f)

      assert {:ok, :already_accepted} = Friends.send_request(alice, bob)
    end
  end

  describe "accept/2" do
    setup ctx do
      {:ok, f} = Friends.send_request(ctx.alice, ctx.bob)
      {:ok, friendship: f}
    end

    test "받은 사람만 수락 가능", %{alice: alice, bob: bob, friendship: f} do
      # 보낸 사람(alice) 은 수락 불가
      assert {:error, :not_acceptable_by_requester} = Friends.accept(alice, f)
      # 받은 사람(bob) 은 수락 OK
      assert {:ok, updated} = Friends.accept(bob, f)
      assert updated.status == "accepted"
    end

    test "수락 후 are_friends? = true", %{alice: alice, bob: bob, friendship: f} do
      {:ok, _} = Friends.accept(bob, f)
      assert Friends.are_friends?(alice, bob)
      assert Friends.are_friends?(bob, alice)
    end

    test "이미 accepted 면 idempotent", %{bob: bob, friendship: f} do
      {:ok, _} = Friends.accept(bob, f)
      reloaded = Friends.get_friendship(f.id)
      assert {:ok, _} = Friends.accept(bob, reloaded)
    end
  end

  describe "reject/2" do
    test "양쪽 다 거절 가능 (row 삭제)", %{alice: alice, bob: bob} do
      {:ok, f} = Friends.send_request(alice, bob)
      assert {:ok, _} = Friends.reject(bob, f)
      assert nil == Friends.get_friendship(f.id)
    end

    test "관계 없는 user 는 거부", %{alice: alice, bob: bob} do
      charlie = register!(System.unique_integer([:positive]))
      {:ok, f} = Friends.send_request(alice, bob)
      assert {:error, :not_party} = Friends.reject(charlie, f)
    end
  end

  describe "list_friends/1, list_pending_received/1, list_pending_sent/1" do
    test "list_friends 양방향", %{alice: alice, bob: bob} do
      {:ok, f} = Friends.send_request(alice, bob)
      {:ok, _} = Friends.accept(bob, f)

      assert [%{id: bob_id}] = Friends.list_friends(alice)
      assert bob_id == bob.id
      assert [%{id: alice_id}] = Friends.list_friends(bob)
      assert alice_id == alice.id
    end

    test "list_pending_received 는 받은 사람만 보임", %{alice: alice, bob: bob} do
      {:ok, _} = Friends.send_request(alice, bob)
      assert [_pending] = Friends.list_pending_received(bob)
      assert [] = Friends.list_pending_received(alice)
    end

    test "list_pending_sent 는 보낸 사람만 보임", %{alice: alice, bob: bob} do
      {:ok, _} = Friends.send_request(alice, bob)
      assert [_pending] = Friends.list_pending_sent(alice)
      assert [] = Friends.list_pending_sent(bob)
    end
  end

  describe "recommend/2" do
    test "친구 아닌 active 유저들 닉네임 순", %{alice: alice, bob: bob} do
      _charlie = register!("rec_c_#{System.unique_integer([:positive])}")
      _diana = register!("rec_d_#{System.unique_integer([:positive])}")

      result = Friends.recommend(alice, 10)
      assert is_list(result)
      assert Enum.any?(result, &(&1.id == bob.id))
      refute Enum.any?(result, &(&1.id == alice.id))
    end

    test "친구된 사람은 추천 안 함", %{alice: alice, bob: bob} do
      {:ok, f} = Friends.send_request(alice, bob)
      {:ok, _} = Friends.accept(bob, f)
      Cachex.clear(:recommendations_cache)

      result = Friends.recommend(alice, 10)
      refute Enum.any?(result, &(&1.id == bob.id))
    end

    test "limit 적용", %{alice: alice, bob: _bob} do
      for i <- 1..5, do: register!("rec_lim_#{i}_#{System.unique_integer([:positive])}")
      Cachex.clear(:recommendations_cache)

      result = Friends.recommend(alice, 3)
      assert length(result) <= 3
    end
  end

  describe "Friendship.canonical_pair/2" do
    test "정렬 보장" do
      assert {"a", "b"} = Friendship.canonical_pair("a", "b")
      assert {"a", "b"} = Friendship.canonical_pair("b", "a")
    end
  end

  describe "Friendship.changeset" do
    test "non-canonical 거부", %{alice: alice, bob: bob} do
      # alice.id > bob.id 인 경우만 fail. 둘 중 큰거를 user_a 에 넣음.
      {smaller, larger} = Friendship.canonical_pair(alice.id, bob.id)

      cs =
        Friendship.changeset(%Friendship{}, %{
          user_a_id: larger,
          user_b_id: smaller,
          status: "pending",
          requested_by: alice.id
        })

      refute cs.valid?
      assert "must be canonical (a < b)" in errors_on(cs).user_a_id
    end

    test "self friendship 거부", %{alice: alice} do
      cs =
        Friendship.changeset(%Friendship{}, %{
          user_a_id: alice.id,
          user_b_id: alice.id,
          status: "pending",
          requested_by: alice.id
        })

      refute cs.valid?
    end
  end
end
