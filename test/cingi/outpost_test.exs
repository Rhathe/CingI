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
end
