defmodule CingiOutpostTest do
	use ExUnit.Case
	alias Cingi.Outpost
	doctest Outpost

	test "creates outpost" do
		{:ok, pid} = Outpost.start_link()
		assert %{
			name: nil,
			is_setup: false,
			setup_steps: nil,
			bash_process: nil,
			node: :"nonode@nohost",
		} = Outpost.get(pid)
	end

	test "alternates includes outpost" do
		{:ok, pid} = Outpost.start_link()
		assert [^pid] = Outpost.get(pid).alternates |> Agent.get(&(&1))
	end

	test "alternates updates with new outposts" do
		{:ok, pid1} = Outpost.start_link()
		{:ok, pid2} = Outpost.start_link(original: pid1)

		a1 = Outpost.get pid1
		a2 = Outpost.get pid2

		assert pid1 != pid2
		assert a1.alternates == a2.alternates
		assert [^pid1, ^pid2] = a1.alternates |> Agent.get(&(&1))
	end

	test "alternates gets outpost on same node" do
		{:ok, pid1} = Outpost.start_link()
		{:ok, pid2} = Outpost.start_link(original: pid1)

		outpost1 = Outpost.get_on_same_node pid1
		outpost2 = Outpost.get_on_same_node pid2

		assert pid1 != pid2
		assert pid1 == outpost1
		assert pid1 == outpost2
	end

	@tag distributed: true
	test "distributed outposts" do
		count = 3

		DistributedEnv.start(count)
		assert length(Node.list()) === count

		nodes = [:"slave1@127.0.0.1", :"slave2@127.0.0.1", :"slave3@127.0.0.1"]
		[node1, node2, node3] = nodes
		:rpc.block_call(node1, Outpost, :start_link, [[name: {:global, :test}]])

		original = Outpost.get {:global, :test}

		assert %{
			name: {:global, :test},
			node: :"slave1@127.0.0.1",
		} = original

		[first, second, third] = nodes
			|> Enum.map(&(:rpc.block_call(&1, Outpost, :get_on_same_node, [{:global, :test}])))

		# Assert that the outpost is only showing up on the first node
		assert original == Outpost.get first
		assert nil == second
		assert nil == third

		# Assert that the second outpost is a clone of the first on the second node,
		# and that they know that they are alternates of each other
		second = :rpc.block_call(node2, Outpost, :get_or_create_on_same_node, [{:global, :test}])
		assert %{
			name: {:global, :test},
			node: :"slave2@127.0.0.1",
		} = Outpost.get second

		assert original.alternates == Outpost.get(second).alternates

		alts = Outpost.get_alternates {:global, :test}
		assert length(alts) == 2
		assert first in alts
		assert second in alts

		# Assert that node3 still does not have an associated outpost
		third = :rpc.block_call(node3, Outpost, :get_on_same_node, [{:global, :test}])
		assert nil == third

		DistributedEnv.stop()
		assert length(Node.list()) === 0
	end
end
