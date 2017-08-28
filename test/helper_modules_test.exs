defmodule Helper do
	alias Cingi.Mission
	alias Cingi.Headquarters

	def check_exit_code(pid) do
		timing(fn () ->
			mission = Mission.get pid
			ec = mission.exit_code
			[ec, mission]
		end)
	end

	def wait_for_running_missions(pid, n) do
		timing(fn () ->
			hq = Headquarters.get(pid)
			[n <= length(hq.running_missions), hq]
		end)
	end

	def wait_for_finished_missions(pid, n) do
		timing(fn () ->
			hq = Headquarters.get(pid)
			[n <= length(hq.finished_missions), hq]
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
end
