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
		mission = wait_for_exit_code(res[:mission_pid])
		assert [[data: "1\n", type: :out, timestamp: _, pid: nil]] = mission.output
	end

	test "runs missions with outputs" do
		cmd_1 = "  - echo -e \"match1\\nignored2\\nmatch3\""
		grep_cmd = "  - missions: grep match\n    input: $IN"

		res = create_mission_report([string: "\nmissions:\n#{cmd_1}\n#{grep_cmd}\n  - echo end"])
		pid = res[:pid]
		Headquarters.resume(pid)
		mission = wait_for_exit_code(res[:mission_pid])
		assert [
			[data: "match1\nignored2\nmatch3\n", type: :out, timestamp: _, pid: _],
			[data: "match1\nmatch3\n", type: :out, timestamp: _, pid: _],
			[data: "end\n", type: :out, timestamp: _, pid: _],
		] = mission.output
	end

	test "runs sequential submissions" do
		yaml = "missions:\n  - ncat -l -i 1 8000\n  - ncat -l -i 1 8001"
		res = create_mission_report([string: yaml])
		pid = res[:pid]
		Headquarters.resume(pid)

		hq = wait_for_running_missions(pid, 2)
		assert length(hq.queued_missions) == 0
		assert length(hq.running_missions) == 2

		mission = Mission.get(res[:mission_pid])
		assert %{output: [], exit_code: nil, submission_pids: [sm1]} = mission
		submission1 = Mission.get(sm1)
		assert %{cmd: "ncat -l -i 1 8000", running: true, finished: false} = submission1

		Porcelain.spawn("bash", [ "-c", "echo -n blah1 | nc localhost 8000"])
		hq = wait_for_running_missions(pid, 3)
		assert length(hq.queued_missions) == 0
		assert length(hq.running_missions) == 3

		mission = Mission.get(res[:mission_pid])
		assert %{output: output, exit_code: nil, submission_pids: [sm1, sm2]} = mission
		assert [[data: "blah1", type: :out, timestamp: _, pid: ^sm1]] = output

		submission1 = Mission.get(sm1)
		submission2 = Mission.get(sm2)

		assert %{cmd: "ncat -l -i 1 8000", running: false, finished: true} = submission1
		assert %{cmd: "ncat -l -i 1 8001", running: true, finished: false} = submission2

		Porcelain.spawn("bash", [ "-c", "echo -n blah2 | nc localhost 8001"])
		mission = wait_for_exit_code(res[:mission_pid])

		assert %{output: output, exit_code: 0} = mission
		assert [
			[data: "blah1", type: :out, timestamp: _, pid: ^sm1],
			[data: "blah2", type: :out, timestamp: _, pid: ^sm2]
		] = output

		submission2 = Mission.get(sm2)
		assert %{cmd: "ncat -l -i 1 8001", running: false, finished: true} = submission2
	end

	test "runs parallel submissions" do
		yaml = Enum.map [1,2,3,4], &("  s#{&1}:\n    missions: ncat -l -i 1 900#{&1}")
		yaml = ["missions:"] ++ yaml
		yaml = Enum.join yaml, "\n"

		res = create_mission_report([string: yaml])
		pid = res[:pid]
		Headquarters.resume(pid)

		hq = wait_for_running_missions(pid, 5)
		assert length(hq.queued_missions) == 0
		assert length(hq.running_missions) == 5

		finish = &(Porcelain.spawn("bash", [ "-c", "echo -n blah#{&1} | nc localhost 900#{&1}"]))

		finish.(3)
		wait_for_submissions_finish(res[:mission_pid], 1)
		finish.(2)
		wait_for_submissions_finish(res[:mission_pid], 2)
		finish.(4)
		wait_for_submissions_finish(res[:mission_pid], 3)
		finish.(1)
		wait_for_submissions_finish(res[:mission_pid], 4)

		mission = wait_for_exit_code(res[:mission_pid])
		assert %{output: [
			[data: "blah3", type: :out, timestamp: _, pid: pid1],
			[data: "blah2", type: :out, timestamp: _, pid: pid2],
			[data: "blah4", type: :out, timestamp: _, pid: pid3],
			[data: "blah1", type: :out, timestamp: _, pid: pid4]
		], exit_code: 0} = mission

		assert pid1 != pid2 != pid3 != pid4
		assert pid1 in mission.submission_pids
		assert pid2 in mission.submission_pids
		assert pid3 in mission.submission_pids
		assert pid4 in mission.submission_pids
	end

	defp get_paused() do
		{:ok, pid} = Headquarters.start_link()
		Headquarters.pause(pid)
		pid
	end

	defp wait_for_exit_code(pid) do
		mission = Mission.get(pid)
		case mission.exit_code do
			nil -> wait_for_exit_code(pid)
			_ -> mission
		end
	end

	defp wait_for_running_missions(pid, n) do
		hq = Headquarters.get(pid)
		cond do
			n <= length(hq.running_missions) -> hq
			true -> wait_for_running_missions(pid, n)
		end
	end

	defp wait_for_submissions_finish(pid, n) do
		mission = Mission.get(pid)
		pids = mission.submission_pids
		sum = length(Enum.filter(pids, &(not is_nil(Mission.get(&1).exit_code))))
		cond do
			n <= sum -> mission
			true -> wait_for_submissions_finish(pid, n)
		end
	end
end
