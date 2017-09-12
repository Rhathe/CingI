defmodule CingiOutpostTest do
	use ExUnit.Case
	alias Cingi.Outpost
	alias Cingi.Branch
	doctest Outpost

	test "creates outpost" do
		{:ok, pid} = Outpost.start_link()
		assert %{
			name: nil,
			is_setup: false,
			setup_steps: nil,
			branch_pid: nil,
			node: :"nonode@nohost",
		} = Outpost.get(pid)
	end

	test "alternates includes outpost" do
		{:ok, pid} = Outpost.start_link()
		assert %{nil: ^pid} = Outpost.get(pid).alternates |> Agent.get(&(&1))
	end

	test "alternates updates with new outposts" do
		{:ok, pid1} = Outpost.start_link()
		{:ok, pid2} = Outpost.start_link(original: pid1)

		a1 = Outpost.get pid1
		a2 = Outpost.get pid2

		assert pid1 != pid2
		assert a1.alternates == a2.alternates
		assert %{nil: ^pid2} = a1.alternates |> Agent.get(&(&1))
	end

	test "alternates gets outpost on same branch" do
		{:ok, bpid} = Branch.start_link()
		{:ok, pid1} = Outpost.start_link(branch_pid: bpid)
		{:ok, pid2} = Outpost.start_link(original: pid1, branch_pid: bpid)

		outpost1 = Outpost.get_version_on_branch pid1, bpid
		outpost2 = Outpost.get_version_on_branch pid2, bpid

		assert pid1 != pid2
		assert pid2 == outpost1
		assert pid2 == outpost2
	end

	test "alternates gets outpost on different branch" do
		{:ok, bpid1} = Branch.start_link()
		{:ok, bpid2} = Branch.start_link()
		{:ok, pid1} = Outpost.start_link(branch_pid: bpid1)
		{:ok, pid2} = Outpost.create_version_on_branch(pid1, bpid2)
		assert pid1 != pid2

		outpost1 = Outpost.get_version_on_branch pid1, bpid1
		outpost2 = Outpost.get_version_on_branch pid2, bpid1

		assert pid1 == outpost1
		assert pid1 == outpost2

		outpost1 = Outpost.get_version_on_branch pid1, bpid2
		outpost2 = Outpost.get_version_on_branch pid2, bpid2

		assert pid2 == outpost1
		assert pid2 == outpost2
	end

	@tag distributed: true
	test "distributed outposts" do
		count = 3

		DistributedEnv.start(count)
		assert length(Node.list()) === count

		nodes = [:"slave1@127.0.0.1", :"slave2@127.0.0.1", :"slave3@127.0.0.1"]
		[node1, node2, node3] = nodes
		{:ok, bpid1} = :rpc.block_call(node1, Branch, :start_link, [[name: :testb]])
		{:ok, bpid2} = :rpc.block_call(node2, Branch, :start_link, [[name: :testb]])
		{:ok, bpid3} = :rpc.block_call(node3, Branch, :start_link, [[name: :testb]])

		:rpc.block_call(node1, Outpost, :start_link, [[name: {:global, :test}, branch_pid: bpid1]])

		original = Outpost.get {:global, :test}

		assert %{
			name: {:global, :test},
			node: :"slave1@127.0.0.1",
			branch_pid: ^bpid1,
		} = original

		[first, second, third] = nodes
			|> Enum.map(&(:rpc.block_call(&1, Branch, :get, [:testb])))
			|> Enum.map(&(:rpc.block_call(&1.node, Outpost, :get_version_on_branch, [{:global, :test}, &1.pid])))

		# Assert that the outpost is only showing up on the first node
		assert original == Outpost.get first
		assert nil == second
		assert nil == third

		# Assert that the second outpost is a clone of the first on the second node,
		# and that they know that they are alternates of each other
		{:ok, second} = :rpc.block_call(node2, Outpost, :create_version_on_branch, [{:global, :test}, bpid2])

		assert %{
			name: {:global, :test},
			node: :"slave2@127.0.0.1",
			branch_pid: ^bpid2,
		} = Outpost.get second

		assert original.alternates == Outpost.get(second).alternates

		alts = {:global, :test}
			|> Outpost.get_alternates
			|> Map.values

		assert length(alts) == 2
		assert first in alts
		assert second in alts

		# Assert that node3 still does not have an associated outpost
		third = :rpc.block_call(node3, Outpost, :get_version_on_branch, [{:global, :test}, bpid3])
		assert nil == third

		DistributedEnv.stop()
		assert length(Node.list()) === 0
	end
end
