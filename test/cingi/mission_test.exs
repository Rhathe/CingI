defmodule CingiMissionTest do
	use ExUnit.Case
	alias Cingi.Mission
	doctest Mission

	test "creates mission" do
		pid = mission_with_cmd("echo")
		assert %{
			cmd: "echo",
			output: [],
			input_file: nil,
			submissions_num: 0,
			running: false
		} = Mission.get(pid)
	end

	test "creates empty mission fails" do
		Process.flag :trap_exit, true
		{:error, {%RuntimeError{message: "Must have cmd or submissions, got nil"}, _}}  = Mission.start_link([])
	end

	test "runs mission with appropriate running/finished flag" do
		pid = mission_with_cmd("ncat -l -i 1 9000")
		Mission.run(pid)
		assert %{
			cmd: "ncat -l -i 1 9000",
			output: [],
			finished: false,
			running: true,
			exit_code: nil
		} = Mission.get(pid)

		Porcelain.spawn("bash", [ "-c", "echo -n blah | ncat localhost 9000"])
		check_exit_code(pid)
		assert %{
			cmd: "ncat -l -i 1 9000",
			output: [[data: "blah", type: :out, timestamp: _, pid: []]],
			finished: true,
			running: false,
			exit_code: 0
		} = Mission.get(pid)
	end

	test "runs mission no args" do
		pid = mission_with_cmd("echo")
		Mission.run(pid)
		check_exit_code(pid)
		assert %{
			cmd: "echo",
			output: [[data: "\n", type: :out, timestamp: _, pid: []]],
			finished: true,
			running: false,
			exit_code: 0
		} = Mission.get(pid)
	end

	test "runs mission with args" do
		pid = mission_with_cmd("echo blah")
		Mission.run(pid)
		check_exit_code(pid)
		assert %{
			cmd: "echo blah",
			output: [[data: "blah\n", type: :out, timestamp: _, pid: []]],
			finished: true,
			running: false,
			exit_code: 0
		} = Mission.get(pid)
	end

	test "runs mission with args and ampersands" do
		pid = mission_with_cmd("echo blah1 && sleep 0.1 && echo blah2")
		Mission.run(pid)
		check_exit_code(pid)
		assert %{
			cmd: "echo blah1 && sleep 0.1 && echo blah2",
			output: [
				[data: "blah1\n", type: :out, timestamp: _, pid: []],
				[data: "blah2\n", type: :out, timestamp: _, pid: []]
			],
			finished: true,
			running: false,
			exit_code: 0
		} = Mission.get(pid)
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
		assert mission.key == ""
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

	defp check_exit_code(pid) do
		mission = Mission.get(pid)
		case mission.exit_code do
			nil -> check_exit_code(pid)
			_ -> mission.exit_code
		end
	end
end
