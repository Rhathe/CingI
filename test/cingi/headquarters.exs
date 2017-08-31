defmodule CingiHeadquartersTest do
	use ExUnit.Case
	alias Cingi.Headquarters
	alias Cingi.Branch
	doctest Headquarters

	test "creating mission report queued mission" do
		res = Helper.create_mission_report([string: "missions: echo 1"])
		assert length(Headquarters.get(res[:hq_pid]).queued_missions) == 1
		assert res[:mission].cmd == "echo 1"
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
end
