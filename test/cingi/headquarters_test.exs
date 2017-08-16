defmodule CingiHeadquartersTest do
	use ExUnit.Case
	alias Cingi.Headquarters
	alias Cingi.MissionReport
	doctest Headquarters

	test "creates headquarters" do
		{:ok, pid} = Headquarters.start_link()
		assert %{
			running: true,
			mission_reports: [],
			queued_missions: [],
			running_missions: [],
			finished_missions: []
		} = Headquarters.get(pid)
	end

	test "can pause headquarters" do
		pid = get_paused()
		assert %{running: false} = Headquarters.get(pid)
	end

	test "can create mission report" do
		pid = get_paused()
		report_pid = Headquarters.create_report(pid, [string: "missions: echo 1"])
		hq = Headquarters.get(pid)
		report = MissionReport.get(report_pid)
		assert %{"missions" => "echo 1"} = report.mission_statements
		assert report in hq.mission_reports
	end

	@docp """
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
	*/

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

	test "runs submissions" do
		{:ok, pid} = Mission.start_link([submissions: ["echo 1", "echo 2"]])
		Mission.run(pid)
		check_exit_code(pid)
		mission = Mission.get(pid)
		assert %Mission{mission | submission_pids: [], submissions: nil, output: []} == %Mission{running: true, exit_code: 0}
		assert "1\n" in mission.output
		assert "2\n" in mission.output
		assert "3\n" not in mission.output
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
	"""

	defp get_paused() do
		{:ok, pid} = Headquarters.start_link()
		Headquarters.pause(pid)
		pid
	end

	defp check_exit_code(pid) do
		mission = Cingi.Mission.get(pid)
		case mission.exit_code do
			nil -> check_exit_code(pid)
			_ -> mission.exit_code
		end
	end
end
