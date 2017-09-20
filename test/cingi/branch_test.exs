defmodule CingiBranchTest do
	use ExUnit.Case
	alias Cingi.Branch
	alias Cingi.Headquarters
	alias Cingi.Outpost
	alias Cingi.Mission
	doctest Branch

	test "creates branch" do
		{:ok, pid} = Branch.start_link()
		assert %{
			running: true,
			mission_reports: [],
			started_missions: [],
			running_missions: [],
			finished_missions: []
		} = Branch.get(pid)
	end

	test "can create mission report" do
		res = Helper.create_mission_report([string: "missions: echo 1"])
		assert %{"missions" => "echo 1"} = res[:report].plan
		assert res[:report_pid] in res[:branch].mission_reports
	end

	test "runs queued missions" do
		res = Helper.create_mission_report([string: "missions: echo 1"])
		bpid = res[:branch_pid]
		mpid = res[:mission_pid]
		Headquarters.resume(res[:hq_pid])
		Helper.check_exit_code mpid

		branch = Helper.wait_for_finished_missions(bpid, 1)
		assert length(branch.started_missions) == 0
		assert length(branch.running_missions) == 0
		assert length(branch.finished_missions) == 1
		mission = Helper.check_exit_code(mpid)
		assert [[data: "1\n", type: :out, timestamp: _, field_agent_pid: _, pid: []]] = mission.output
	end

	test "runs missions with outputs" do
		cmd_1 = "  - echo -e \"match1\\nignored2\\nmatch3\""
		grep_cmd = "  - missions: grep match\n    input: $IN"

		res = Helper.create_mission_report([string: "\nmissions:\n#{cmd_1}\n#{grep_cmd}\n  - echo end"])
		Headquarters.resume(res[:hq_pid])
		mission = Helper.check_exit_code(res[:mission_pid])

		outputs = mission.output
			|> Enum.map(&(String.split(&1[:data], "\n", trim: true)))
			|> List.flatten

		assert ["match1", "ignored2", "match3", "match1", "match3", "end"] = outputs
	end

	test "runs sequential submissions" do
		cmd8000 = "ncat -l -i 1 8000"
		cmd8001 = "ncat -l -i 1 8001"

		yaml = "missions:\n  - #{cmd8000}\n  - #{cmd8001}"
		res = Helper.create_mission_report([string: yaml])
		Headquarters.resume(res[:hq_pid])
		bpid = res[:branch_pid]

		branch = Helper.wait_for_running_missions(bpid, 2)
		assert length(branch.started_missions) == 0
		assert length(branch.running_missions) == 2
		assert length(branch.finished_missions) == 0

		mission = Mission.get(res[:mission_pid])
		assert %{output: [], exit_code: nil, submission_holds: [sm1]} = mission
		submission1 = Mission.get(sm1.pid)

		assert %{cmd: ^cmd8000, running: true, finished: false} = submission1

		Helper.wait_for_process cmd8000
		Porcelain.exec("bash", [ "-c", "echo -n blah1 | ncat localhost 8000"])

		Helper.wait_for_finished_missions(bpid, 1)
		branch = Helper.wait_for_running_missions(bpid, 2)

		assert length(branch.started_missions) == 0
		assert length(branch.running_missions) == 2
		assert length(branch.finished_missions) == 1

		mission = Mission.get(res[:mission_pid])
		assert %{output: output, exit_code: nil, submission_holds: [sm1, sm2]} = mission
		sm1pid = sm1.pid
		assert [[data: "blah1", type: :out, timestamp: _, field_agent_pid: _, pid: [^sm1pid]]] = output

		submission1 = Mission.get(sm1.pid)
		submission2 = Mission.get(sm2.pid)

		assert %{cmd: ^cmd8000, running: false, finished: true} = submission1
		assert %{cmd: ^cmd8001, running: true, finished: false} = submission2

		Helper.wait_for_process cmd8001
		Porcelain.spawn("bash", [ "-c", "echo -n blah2 | ncat localhost 8001"])
		mission = Helper.check_exit_code(res[:mission_pid])

		sm1pid = sm1.pid
		sm2pid = sm2.pid
		assert %{output: output, exit_code: 0} = mission
		assert [
			[data: "blah1", type: :out, timestamp: _, field_agent_pid: _, pid: [^sm1pid]],
			[data: "blah2", type: :out, timestamp: _, field_agent_pid: _, pid: [^sm2pid]]
		] = output

		submission2 = Mission.get(sm2.pid)
		assert %{cmd: ^cmd8001, running: false, finished: true} = submission2

		branch = Helper.wait_for_finished_missions(bpid, 3)
		assert length(branch.started_missions) == 0
		assert length(branch.running_missions) == 0
		assert length(branch.finished_missions) == 3
	end

	test "runs parallel submissions" do
		yaml = Enum.map [1,2,3,4], &("  s#{&1}: ncat -l -i 1 900#{&1}")
		yaml = ["missions:"] ++ yaml
		yaml = Enum.join yaml, "\n"

		res = Helper.create_mission_report([string: yaml])
		Headquarters.resume(res[:hq_pid])

		branch = Helper.wait_for_running_missions(res[:branch_pid], 5)
		assert length(branch.started_missions) == 0
		assert length(branch.running_missions) == 5

		Enum.map [1,2,3,4], &(Helper.wait_for_process("ncat -l -i 1 900#{&1}"))
		finish = &(Porcelain.exec("bash", [ "-c", "echo -n blah#{&1} | ncat localhost 900#{&1}"]))

		finish.(3)
		Helper.wait_for_submissions_finish(res[:mission_pid], 1)
		finish.(2)
		Helper.wait_for_submissions_finish(res[:mission_pid], 2)
		finish.(4)
		Helper.wait_for_submissions_finish(res[:mission_pid], 3)
		finish.(1)
		Helper.wait_for_submissions_finish(res[:mission_pid], 4)

		mission = Helper.check_exit_code(res[:mission_pid])
		assert %{output: [
			[data: "blah3", type: :out, timestamp: _, field_agent_pid: _, pid: [pid1]],
			[data: "blah2", type: :out, timestamp: _, field_agent_pid: _, pid: [pid2]],
			[data: "blah4", type: :out, timestamp: _, field_agent_pid: _, pid: [pid3]],
			[data: "blah1", type: :out, timestamp: _, field_agent_pid: _, pid: [pid4]]
		], exit_code: 0} = mission

		pids = mission.submission_holds |> Enum.map(&(&1.pid))
		assert pid1 != pid2 != pid3 != pid4
		assert pid1 in pids
		assert pid2 in pids
		assert pid3 in pids
		assert pid4 in pids
	end

	test "runs example file" do
		res = Helper.create_mission_report([file: "test/mission_plans/example.yaml"])
		hpid = res[:hq_pid]
		Headquarters.resume(hpid)
		mission = Helper.check_exit_code(res[:mission_pid])
		output = mission.output |> Enum.map(&(&1[:data]))
		assert ["beginning\n", a, b, c, d, e, f, g, grepped, "end\n"] = output

		l1 = Enum.sort(["match 1\n", "ignored 2\n", "match 3\n", "ignored 4\n", "match 5\n", "ignored 6\n", "match 7\n"])
		l2 = Enum.sort([a, b, c, d, e, f, g])
		assert ^l1 = l2

		matches = grepped |> String.split("\n") |> Enum.sort
		assert length(matches) == 5
		match_check = Enum.sort(["match 1", "match 3", "match 5", "match 7", ""])
		assert ^match_check = matches
	end

	test "make sure inputs are passed correctly to nested missions" do
		res = Helper.create_mission_report([file: "test/mission_plans/nested.yaml"])
		Headquarters.resume(res[:hq_pid])
		mission = Helper.check_exit_code(res[:mission_pid])
		output = mission.output |> Enum.map(&(&1[:data]))

		assert [
			"blah1\n",
			"blah1\n",
			"1match1\n",
			"2match2\n",
			"1match3\n",
			"2match1\n",
			"ignored\n",
			"1match4\n",
			"2match5\n",
			"1match1\n2match2\n1match3\n2match1\n1match4\n2match5\n",
			"2match2\n2match1\n2match5\n",
			a,
			b,
		] = output

		sublist = [a, b]
		assert "2match1\n" in sublist
		assert "2match5\n" in sublist
	end

	test "generates correct outposts" do
		res = Helper.create_mission_report([file: "test/mission_plans/outposts/simple.yaml"])
		bpid = res[:branch_pid]
		mpid = res[:mission_pid]
		Headquarters.resume(res[:hq_pid])
		Helper.check_exit_code mpid

		opids = Branch.get(bpid).finished_missions
			|> Enum.map(&Mission.get_outpost/1)
			|> Enum.uniq

		assert length(opids) == 2
		outposts = opids |> Enum.map(&Outpost.get/1)

		assert %{
			alternates: _,
			node: :nonode@nohost,
		} = Enum.at(outposts, 0)
	end

	test "gets correct exit codes fails fast when necessary" do
		res = Helper.create_mission_report([file: "test/mission_plans/exits.yaml"])
		bpid = res[:branch_pid]
		mpid = res[:mission_pid]
		Headquarters.resume(res[:hq_pid])

		branch = Helper.wait_for_finished_missions(bpid, 12)
		assert length(branch.started_missions) == 0

		# non-fail fast ncat task, its parent,
		# the whole parallel mission, and the mission itself
		assert length(branch.running_missions) == 4

		# 1 sequential supermission
		# 2 submissions below that
		# 5 sequential missions
		# 1 fail fast parallel supermission
		# 2 fail fast parallel missions
		# 1 non-fail fast parallel mission
		assert length(branch.finished_missions) == 12

		Porcelain.exec("bash", [ "-c", "echo -n endncat | ncat localhost 9991"])
		Helper.check_exit_code mpid

		mission = Mission.get(mpid)
		assert 7 = mission.exit_code

		output = mission.output |>
			Enum.map(&(&1[:data]))

		assert [a, b, c, "endncat"] = output
		l1 = Enum.sort(["seq_continue\n", "Should still be in seq_continue\n", "seq_fail_fast\n"])
		assert ^l1 = Enum.sort([a, b, c])
	end
end
