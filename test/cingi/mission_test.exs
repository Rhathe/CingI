defmodule CingiMissionTest do
	use ExUnit.Case
	alias Cingi.Mission
	doctest Mission

	test "creates mission" do
		pid = mission_with_cmd("echo")
		assert %{
			cmd: "echo",
			output: [],
			input_file: "$IN",
			submissions_num: 0,
			running: false,
		} = Mission.get(pid)
	end

	test "creates empty mission fails" do
		Process.flag :trap_exit, true
		{:error, {%RuntimeError{message: "Must have cmd or submissions, got nil"}, _}}  = Mission.start_link([])
	end

	test "constructs with yaml command" do
		{:ok, pid} = Mission.start_link([decoded_yaml: "echo 1"])
		mission = Mission.get(pid)
		assert mission.key == "echo_1"
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

	test "constructs with yaml map and just command, key is missions" do
		{:ok, pid} = Mission.start_link([decoded_yaml: %{
			"missions" => "echo 1"
		}])
		mission = Mission.get(pid)
		assert mission.key == "echo_1"
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
		assert mission.key == ""
		assert mission.cmd == nil
		assert mission.submissions == %{"missions" => "echo 1"}
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
end
