defmodule CingiMissionTest do
	use ExUnit.Case
	alias Cingi.Mission
	doctest Mission

	test "creates mission" do
		pid = create_mission("echo")
		assert Mission.get(pid) == %Mission{cmd: "echo", output: [], running: false}
	end

	test "runs mission no args" do
		pid = create_mission("echo")
		Mission.run(pid)
		check_exit_code(pid)
		assert Mission.get(pid) == %Mission{cmd: "echo", output: ["\n"], running: true, exit_code: 0}
	end

	test "runs mission with args" do
		pid = create_mission("echo blah")
		Mission.run(pid)
		check_exit_code(pid)
		assert Mission.get(pid) == %Mission{cmd: "echo blah", output: ["blah\n"], running: true, exit_code: 0}
	end

	test "runs mission with args and ampersands" do
		pid = create_mission("echo blah && sleep 0.1 && echo blah2")
		Mission.run(pid)
		check_exit_code(pid)
		assert Mission.get(pid) == %Mission{
			cmd: "echo blah && sleep 0.1 && echo blah2",
			output: ["blah\n", "blah2\n"],
			running: true, exit_code: 0
		}
	end

	defp create_mission(cmd) do
		{:ok, pid} = Mission.start_link([cmd: cmd])
		pid
	end

	defp check_exit_code(pid) do
		mission = Mission.get(pid)
		case mission.exit_code do
			Null -> check_exit_code(pid)
			_ -> mission.exit_code
		end
	end
end
