defmodule CingiHeadquartersTest do
	use ExUnit.Case
	alias Cingi.Headquarters
	alias Cingi.Branch
	doctest Headquarters

	test "creating mission report queued mission, but no plan yet" do
		res = Helper.create_mission_report([string: "missions: echo 1"])
		assert length(Headquarters.get(res[:hq_pid]).queued_missions) == 1
		assert nil == res[:mission].cmd
		assert nil == res[:mission].submissions
	end

	test "can resume" do
		res = Helper.create_mission_report([string: "missions: echo 1"])
		hpid = res[:hq_pid]
		assert length(Headquarters.get(hpid).queued_missions) == 1
		Headquarters.resume(hpid)
		Helper.wait_for_finished(res[:mission_pid])
		assert length(Headquarters.get(hpid).queued_missions) == 0
	end

	test "links branch" do
		res = Helper.create_mission_report([string: "missions: echo 1"])
		hpid = res[:hq_pid]
		bpid = res[:branch_pid]
		assert [^bpid] = Headquarters.get(hpid).branch_pids
		assert ^hpid = Branch.get(bpid).hq_pid

		{:ok, bpid2} = Branch.start_link()
		Headquarters.link_branch(hpid, bpid2)

		assert [^bpid, ^bpid2] = Headquarters.get(hpid).branch_pids
		assert ^hpid = Branch.get(bpid2).hq_pid
	end

	test "distributes parallel missions" do
		yaml = Enum.map [1,2,3,4], &("  s#{&1}: ncat -l -i 1 902#{&1}")
		yaml = ["missions:"] ++ yaml
		yaml = Enum.join yaml, "\n"

		res = Helper.create_mission_report([string: yaml])
		hpid = res[:hq_pid]
		bpid = res[:branch_pid]
		{:ok, bpid2} = Branch.start_link()
		Headquarters.link_branch(hpid, bpid2)
		Headquarters.resume(hpid)

		branch1 = Helper.wait_for_running_missions(bpid, 3)
		branch2 = Helper.wait_for_running_missions(bpid2, 2)
		assert length(branch1.started_missions) == 0
		assert length(branch1.running_missions) == 3
		assert length(branch2.started_missions) == 0
		assert length(branch2.running_missions) == 2

		Enum.map [1,2,3,4], &(Helper.wait_for_process("ncat -l -i 1 902#{&1}"))
		finish = &(Porcelain.exec("bash", [ "-c", "echo -n blah#{&1} | ncat localhost 902#{&1}"]))

		finish.(3)
		finish.(2)
		finish.(4)
		finish.(1)

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
end
