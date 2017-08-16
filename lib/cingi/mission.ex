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
		submissions: nil,
		output: [],
		running: false,
		parallel: false,
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

	def finish_submission(pid, submission_pid, result) do
		GenServer.cast(pid, {submission_pid, :result, result})
	end

	def get(pid) do
		GenServer.call(pid, {:get})
	end

	# Server Callbacks

	def init(opts) do
		opts = case opts[:decoded_yaml] do
			nil -> opts
			_ -> construct_opts_from_decoded_yaml(opts)
		end

		mission = struct(Mission, opts)
		case mission do
			%{cmd: nil, submissions: nil} -> raise "Must have cmd or submissions"
			_ -> :ok
		end

		MissionReport.initialized_mission(mission.report_pid, {:mission_init, self(), mission})

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
		submission_pids = mission.submission_pids ++ cond do
			mission.cmd -> run_cmd(mission.cmd)
			mission.submissions -> run_submissions(mission)
		end

		{:noreply, %Mission{mission |
			running: true,
			headquarters_pid: headquarters_pid,
			submission_pids: submission_pids
		}}
	end

	def handle_cast({pid, :data, :out, data}, mission) do
		handle_info({pid, :data, :out, data}, mission)
	end

	def handle_cast({pid, :result, result}, mission) do
		handle_info({pid, :result, result}, mission)
	end

	def run_cmd(cmd) do
		Porcelain.spawn("bash", [ "-c", cmd], out: {:send, self()})
		[]
	end

	def run_submissions(mission) do
		Enum.map(mission.submissions, fn submission ->
			opts = [decoded_yaml: submission, supermission_pid: self()]
			MissionReport.init_mission(mission.report_pid, opts)
		end)
	end

	def handle_call({:get}, _from, mission) do
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
				nil in exit_codes -> nil
				true -> Enum.at(exit_codes, 0)
			end
		end
		{:noreply, %Mission{mission | exit_code: exit_code}}
	end

	defp finished(mission, result) do
		mission_pid = mission.supermission_pid
		if mission_pid do Mission.finish_submission(mission_pid, self(), result) end
	end
end
