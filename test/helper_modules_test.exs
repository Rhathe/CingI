defmodule Helper do
	alias Cingi.Branch
	alias Cingi.Headquarters
	alias Cingi.Mission
	alias Cingi.MissionReport

	def check_exit_code(pid) do
		timing(fn () ->
			mission = Mission.get pid
			ec = mission.exit_code
			[ec, mission]
		end)
	end

	def wait_for_finished(pid) do
		timing(fn () ->
			mission = Mission.get pid
			[mission.finished, mission]
		end)
	end

	def wait_for_queued(pid, n) do
		timing(fn () ->
			hq = Headquarters.get(pid)
			[n <= length(hq.queued_missions), hq]
		end)
	end

	def wait_for_running_missions(pid, n) do
		timing(fn () ->
			branch = Branch.get(pid)
			[n <= length(branch.running_missions), branch]
		end)
	end

	def wait_for_finished_missions(pid, n) do
		timing(fn () ->
			branch = Branch.get(pid)
			[n <= length(branch.finished_missions), branch]
		end)
	end

	def wait_for_submissions_finish(pid, n) do
		timing(fn () ->
			mission = Mission.get(pid)
			pids = Enum.map(mission.submission_holds, &(&1.pid))
			sum = length(Enum.filter(pids, &(not is_nil(Mission.get(&1).exit_code))))
			[n <= sum, mission]
		end)
	end

	def timing(fnc, limit \\ 5, start \\ nil) do
		start = start || Time.utc_now
		diff = Time.diff(Time.utc_now, start)

		ret = [diff > limit] ++ fnc.()
		case ret do
			[true, _, _] -> raise "Waiting exceeded #{limit} seconds"
			[false, false, _] -> timing(fnc, limit, start)
			[false, nil, _] -> timing(fnc, limit, start)
			[_, _, val] -> val
		end
	end

	def create_mission_report(opts) do
		{:ok, bpid} = Branch.start_link()
		{:ok, hpid} = Headquarters.start_link()
		Headquarters.pause(hpid)
		Headquarters.link_branch(hpid, bpid)

		report_pid = Branch.create_report(bpid, opts)
		hq = wait_for_queued(hpid, 1)
		mission_pid = Enum.at(hq.queued_missions, 0)

		[
			hq: hq,
			branch: Branch.get(bpid),
			report: MissionReport.get(report_pid),
			mission: Mission.get(mission_pid),

			hq_pid: hpid,
			branch_pid: bpid,
			report_pid: report_pid,
			mission_pid: mission_pid,
		]
	end

	def run_mission_report(plan) do
		res = Helper.create_mission_report([file: plan])
		Headquarters.resume(res[:hq_pid])
		mission = Helper.wait_for_finished(res[:mission_pid])
		output = mission.output
			|> Enum.map(&(&1[:data]))
			|> Enum.join("\n")
			|> String.split("\n", trim: true)
		[output: output]
	end
end
