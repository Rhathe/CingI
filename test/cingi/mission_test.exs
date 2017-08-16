defmodule CingiMissionTest do
	use ExUnit.Case
	alias Cingi.Mission
	doctest Mission

	test "creates mission" do
		pid = mission_with_cmd("echo")
		assert Mission.get(pid) == %Mission{cmd: "echo", output: [], running: false}
	end

	test "creates empty mission fails" do
		Process.flag :trap_exit, true
		{:error, {%RuntimeError{message: "Must have cmd or submissions"}, _}}  = Mission.start_link([])
	end

	test "runs mission no args" do
		pid = mission_with_cmd("echo")
		Mission.run(pid)
		check_exit_code(pid)
		assert Mission.get(pid) == %Mission{cmd: "echo", output: ["\n"], running: true, exit_code: 0}
	end

	test "runs mission with args" do
		pid = mission_with_cmd("echo blah")
		Mission.run(pid)
		check_exit_code(pid)
		assert Mission.get(pid) == %Mission{cmd: "echo blah", output: ["blah\n"], running: true, exit_code: 0}
	end

	test "runs mission with args and ampersands" do
		pid = mission_with_cmd("echo blah && sleep 0.1 && echo blah2")
		Mission.run(pid)
		check_exit_code(pid)
		assert Mission.get(pid) == %Mission{
			cmd: "echo blah && sleep 0.1 && echo blah2",
			output: ["blah\n", "blah2\n"],
			running: true, exit_code: 0
		}
	end

	test "constructs with yaml command" do
		{:ok, pid} = Mission.start_link([decoded_yaml: "echo 1"])
		mission = Mission.get(pid)
		assert mission.key == "echo 1"
		assert mission.cmd == "echo 1"
		assert mission.submissions == nil
	end

	test "constructs with yaml map" do
		{:ok, pid} = Mission.start_link([decoded_yaml: %{
			"name" => "mission_1",
			"missions" => "echo 1",
		}])
		mission = Mission.get(pid)
		assert mission.key == "mission_1"
		assert mission.cmd == "echo 1"
		assert mission.submissions == nil
	end

	test "constructs with yaml map and just command" do
		{:ok, pid} = Mission.start_link([decoded_yaml: %{
			"any_key" => "echo 1"
		}])
		mission = Mission.get(pid)
		assert mission.key == "any_key"
		assert mission.cmd == "echo 1"
		assert mission.submissions == nil
	end

	test "constructs with yaml map and just submissions" do
		{:ok, pid} = Mission.start_link([decoded_yaml: %{
			"any_key" => ["echo 1", "echo 2"]
		}])
		mission = Mission.get(pid)
		assert mission.key == "any_key"
		assert mission.cmd == nil
		assert mission.submissions == ["echo 1", "echo 2"]
	end

	test "constructs with yaml map and just command, key is missions" do
		{:ok, pid} = Mission.start_link([decoded_yaml: %{
			"missions" => "echo 1"
		}])
		mission = Mission.get(pid)
		assert mission.key == "missions"
		assert mission.cmd == "echo 1"
		assert mission.submissions == nil
	end

	test "constructs with yaml map and just command, keys are missions" do
		{:ok, pid} = Mission.start_link([decoded_yaml: %{
			"missions" => %{
				"missions" => "echo 1"
			}
		}])
		mission = Mission.get(pid)
		assert mission.key == "missions"
		assert mission.cmd == "echo 1"
		assert mission.submissions == nil
	end

	test "constructs with yaml map and array of commands" do
		{:ok, pid} = Mission.start_link([decoded_yaml: %{
			"name" => "mission_1",
			"missions" => ["echo 1", "echo 2"],
		}])
		mission = Mission.get(pid)
		assert mission.key == "mission_1"
		assert mission.cmd == nil
		assert mission.submissions == ["echo 1", "echo 2"]
	end

	test "constructs with yaml map and map of commands" do
		{:ok, pid} = Mission.start_link([decoded_yaml: %{
			"name" => "mission_1",
			"missions" => %{
				"submission 1" => "echo 1",
				"submission 2" => %{
					"name" => "new submission 2",
					"missions" => "echo 2"
				}
			},
		}])
		mission = Mission.get(pid)
		assert mission.key == "mission_1"
		assert mission.cmd == nil
		assert mission.submissions == %{
			"submission 1" => "echo 1",
			"submission 2" => %{
				"name" => "new submission 2",
				"missions" => "echo 2"
			}
		}
	end

	defp mission_with_cmd(cmd) do
		{:ok, pid} = Mission.start_link([cmd: cmd])
		pid
	end

	defp check_exit_code(pid) do
		mission = Mission.get(pid)
		case mission.exit_code do
			nil -> check_exit_code(pid)
			_ -> mission.exit_code
		end
	end
end
