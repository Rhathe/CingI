defmodule CingiHeadquartersTest do
	use ExUnit.Case
	alias Cingi.Headquarters
	alias Cingi.Mission
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

	defp create_mission_report(opts) do
		pid = get_paused()
		report_pid = Headquarters.create_report(pid, opts)
		hq = Headquarters.get(pid)
		mission_pid = Enum.at(hq.queued_missions, 0)

		[
			hq: hq,
			report: MissionReport.get(report_pid),
			mission: Mission.get(mission_pid),
			pid: pid,
			report_pid: report_pid,
			mission_pid: mission_pid
		]
	end

	test "can create mission report" do
		res = create_mission_report([string: "missions: echo 1"])
		assert %{"missions" => "echo 1"} = res[:report].mission_statements
		assert res[:report_pid] in res[:hq].mission_reports
	end

	test "creating mission report queued mission" do
		res = create_mission_report([string: "missions: echo 1"])
		assert length(res[:hq].queued_missions) == 1
		assert res[:mission].cmd == "echo 1"
	end

	test "runs queued missions" do
		res = create_mission_report([string: "missions: echo 1"])
		pid = res[:pid]
		Headquarters.resume(pid)
		hq = Headquarters.get(pid)
		assert length(hq.queued_missions) == 0
		assert length(hq.running_missions) == 1
		check_exit_code(res[:mission_pid])
		mission = Mission.get(res[:mission_pid])
		assert ["1\n"] = mission.output
	end

	test "runs submissions" do
		yaml = "missions:\n  - echo 1\n  - echo 2"
		res = create_mission_report([string: yaml])
		pid = res[:pid]
		Headquarters.resume(pid)
		check_exit_code(res[:mission_pid])

		hq = Headquarters.get(pid)
		assert length(hq.queued_missions) == 0
		assert length(hq.running_missions) == 3
		mission = Mission.get(res[:mission_pid])
		assert "1\n" in mission.output
		assert "2\n" in mission.output
	end

	defp get_paused() do
		{:ok, pid} = Headquarters.start_link()
		Headquarters.pause(pid)
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
