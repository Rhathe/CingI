defmodule CingiMissionTest do
	use ExUnit.Case
	alias Cingi.Mission
	doctest Mission

	test "creates mission" do
		{:ok, pid} = Mission.start_link([mission_plan: "echo"])
		assert %{
			cmd: nil,
			mission_plan: "echo",
			output: [],
			input_file: "$IN",
			running: false,
		} = Mission.get(pid)
	end
end
