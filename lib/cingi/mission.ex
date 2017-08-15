defmodule Cingi.Mission do
	alias Cingi.Mission
	alias Cingi.MissionReport
	use GenServer

	defstruct [
		key: "",

		mission_report_pid: nil,
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
		opts = cond do
			opts[:decoded_yaml] -> construct_opts_from_decoded_yaml(opts)
			true -> opts
		end

		mission = struct(Mission, opts)
		cond do
			mission.cmd -> :ok
			mission.submissions -> :ok
		end

		mr_pid = mission.mission_report_pid
		if mr_pid do
			MissionReport.initialized_mission(mr_pid, {:mission_init, self(), mission})
		end

		{:ok, mission}
	end

	defp construct_opts_from_decoded_yaml(opts) do
		opts = Keyword.delete(opts, :key)
		opts = Keyword.delete(opts, :cmd)
		opts = Keyword.delete(opts, :submissions)
		decoded_yaml = opts[:decoded_yaml]

		cond do
			is_map(decoded_yaml) -> opts ++ construct_opts_from_map(opts)
			true -> opts ++ [key: decoded_yaml, cmd: decoded_yaml]
		end
	end

	defp construct_opts_from_map(opts) do
		map = opts[:decoded_yaml]
		keys = Map.keys(map)
		first_key = Enum.at(keys, 0)
		first_val_map = cond do
			is_map(map[first_key]) -> map[first_key]
			true -> %{"missions" => map[first_key]}
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
		submission_pids = cond do
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
			{:ok, pid} = Mission.start_link([cmd: submission, supermission_pid: self()])
			Mission.run(pid)
			pid
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
		if mission.supermission_pid do Mission.finish_submission(mission.supermission_pid, self(), result) end
		exit_codes = Enum.map(mission.submission_pids, fn m -> Mission.get(m).exit_code end)
		exit_code = cond do
			length(exit_codes) == 0 -> result.status
			true -> cond do
				nil in exit_codes -> nil
				true -> Enum.at(exit_codes, 0)
			end
		end
		{:noreply, %Mission{mission | exit_code: exit_code}}
	end
end
