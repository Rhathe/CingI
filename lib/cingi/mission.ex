defmodule Cingi.Mission do
	alias Cingi.Mission
	alias Cingi.MissionReport
	use GenServer

	defstruct [
		key: "",

		report_pid: nil,
		supermission_pid: nil,
		submission_pids: [],
		headquarters_pid: nil,

		decoded_yaml: nil,
		cmd: nil,
		bash_process: nil,
		submissions: nil,
		submissions_num: nil,
		output: [],

		running: false,
		finished: false,

		exit_code: nil
	]

	# Client API

	def start_link(opts) do
		GenServer.start_link(__MODULE__, opts)
	end

	def run(pid, headquarters_pid \\ nil) do
		GenServer.cast(pid, {:run, headquarters_pid})
	end

	def send(pid, submission_pid, data) do
		GenServer.cast(pid, {submission_pid, :data, :out, data})
	end

	def initialized_submission(pid, submission_pid) do
		GenServer.cast(pid, {:init_submission, submission_pid})
	end

	def finish_submission(pid, submission_pid, result) do
		GenServer.cast(pid, {submission_pid, :result, result})
	end

	def run_bash_process(pid) do
		GenServer.cast(pid, :run_bash_process)
	end

	def run_submissions(pid) do
		GenServer.cast(pid, :run_submissions)
	end

	def pause(pid) do
		GenServer.call(pid, :pause)
	end

	def resume(pid) do
		GenServer.call(pid, :resume)
	end

	def get(pid) do
		GenServer.call(pid, :get)
	end

	# Server Callbacks

	def init(opts) do
		opts = case opts[:decoded_yaml] do
			nil -> opts
			_ -> construct_opts_from_decoded_yaml(opts)
		end

		mission = struct(Mission, opts)
		mission = %Mission{mission | submissions_num: case mission.submissions do
			%{} -> length(Map.keys(mission.submissions))
			[_|_] -> length(mission.submissions)
			_ -> 0
		end}

		case mission do
			%{cmd: nil, submissions: nil} -> raise "Must have cmd or submissions"
			_ -> :ok
		end

		mission_pid = mission.supermission_pid
		if mission_pid do Mission.initialized_submission(mission_pid, self()) end
		MissionReport.initialized_mission(mission.report_pid, self())

		{:ok, mission}
	end

	defp construct_opts_from_decoded_yaml(opts) do
		del = &Keyword.delete/2
		opts = del.(opts, :key) |> del.(:cmd) |> del.(:submissions)
		decoded_yaml = opts[:decoded_yaml]

		case decoded_yaml do
			%{} -> opts ++ construct_opts_from_map(opts)
			_ -> opts ++ [key: decoded_yaml, cmd: decoded_yaml]
		end
	end

	defp construct_opts_from_map(opts) do
		map = opts[:decoded_yaml]
		keys = Map.keys(map)
		first_key = Enum.at(keys, 0)
		first_val_map = case map[first_key] do
			%{} -> map[first_key]
			_ -> %{"missions" => map[first_key]}
		end

		opts ++ case length(keys) do
			0 -> raise "Empty map?"
			1 -> construct_map_opts(Map.merge(%{"name" => first_key}, first_val_map))
			_ -> construct_map_opts(map)
		end
	end

	defp construct_map_opts(map) do
		new_map = [key: map["name"]]
		submissions = map["missions"]

		new_map ++ cond do
			is_map(submissions) -> [submissions: submissions]
			is_list(submissions) -> [submissions: submissions]
			true -> [cmd: submissions]
		end
	end

	def handle_cast({:run, headquarters_pid}, mission) do
		cond do
			mission.cmd -> Mission.run_bash_process(self())
			mission.submissions -> Mission.run_submissions(self())
		end

		{:noreply, %Mission{mission |
			running: true,
			headquarters_pid: headquarters_pid
		}}
	end

	def handle_cast({pid, :data, :out, data}, mission) do
		handle_info({pid, :data, :out, data}, mission)
	end

	def handle_cast({pid, :result, result}, mission) do
		handle_info({pid, :result, result}, mission)
	end

	def handle_cast({:init_submission, pid}, mission) do
		submission_pids = mission.submission_pids ++ [pid]
		{:noreply, %Mission{mission | submission_pids: submission_pids}}
	end

	def handle_cast(:run_bash_process, mission) do
		proc = Porcelain.spawn("./priv/bin/wrapper.sh", [mission.cmd], out: {:send, self()})
		{:noreply, %Mission{mission | bash_process: proc}}
	end

	def handle_cast(:run_submissions, mission) do
		[running, remaining] = case mission.submissions do
			%{} -> [Enum.map(mission.submissions, fn({k, v}) -> %{k => v} end), %{}]
			[a|b] -> [[a], b]
			[] -> [[], []]
		end

		for submission <- running do
			opts = [decoded_yaml: submission, supermission_pid: self()]
			MissionReport.init_mission(mission.report_pid, opts)
		end

		{:noreply, %Mission{mission | submissions: remaining}}
	end

	def handle_call(:pause, _from, mission) do
		mission = %Mission{mission | running: false}
		{:reply, mission, mission}
	end

	def handle_call(:resume, _from, mission) do
		mission = %Mission{mission | running: true}
		{:reply, mission, mission}
	end

	def handle_call(:get, _from, mission) do
		{:reply, mission, mission}
	end

	def handle_info({_pid, :data, :out, data}, mission) do
		if mission.supermission_pid do Mission.send(mission.supermission_pid, self(), data) end
		{:noreply, %Mission{mission | output: mission.output ++ [data]}}
	end

	def handle_info({_pid, :result, result}, mission) do
		finished(mission, result)

		exit_codes = Enum.map(mission.submission_pids, fn m -> Mission.get(m).exit_code end)
		exit_code = case length(exit_codes) do
			0 -> result.status
			_ -> cond do
				length(exit_codes) != mission.submissions_num -> nil
				true -> Enum.at(exit_codes, 0)
			end
		end

		if is_nil(exit_code) do Mission.run_submissions(self()) end

		{:noreply, %Mission{mission |
			exit_code: exit_code,
			finished: true,
			running: false
		}}
	end

	defp finished(mission, result) do
		mission_pid = mission.supermission_pid
		if mission_pid do Mission.finish_submission(mission_pid, self(), result) end
	end
end
