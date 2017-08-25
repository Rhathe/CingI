defmodule Cingi.Mission do
	alias Cingi.Mission
	alias Cingi.MissionReport
	alias Cingi.FieldAgent
	use GenServer

	defstruct [
		key: "",

		report_pid: nil,
		prev_mission_pid: nil,
		supermission_pid: nil,
		submission_pids: [],
		finished_submission_pids: [],
		field_agent_pid: nil,

		decoded_yaml: nil,
		cmd: nil,
		bash_process: nil,
		submissions: nil,
		submissions_num: nil,

		input_file: "$IN", # Get input by default
		output: [],

		listen_for_api: false, # Enable to listen in the output for any cingi api calls
		output_with_stderr: false, # Stderr will be printed to ouput if false, redirected to output if true
		fail_fast: true,
		running: false,
		finished: false,

		exit_code: nil
	]

	# Client API

	def start_link(opts) do
		GenServer.start_link(__MODULE__, opts)
	end

	def send(pid, data) do
		GenServer.cast(pid, {:data_and_metadata, data})
	end

	def initialized_submission(pid, submission_pid) do
		GenServer.cast(pid, {:init_submission, submission_pid})
	end

	def send_result(pid, result, prev_mpid) do
		GenServer.cast(pid, {:finished, result, prev_mpid})
	end

	def run_submissions(pid, prev_pid \\ nil) do
		GenServer.cast(pid, {:run_submissions, prev_pid})
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

	def get_outpost(pid) do
		GenServer.call(pid, :get_outpost)
	end

	def get_outpost_plan(pid) do
		GenServer.call(pid, :get_outpost_plan)
	end

	def set_as_running(pid, field_agent_pid) do
		GenServer.call(pid, {:set_as_running, field_agent_pid})
	end

	def get_output(pid, output_key) do
		case pid do
			nil -> []
			_ -> GenServer.call(pid, {:get_output, output_key})
		end
	end

	# Server Callbacks

	def init(opts) do
		opts = case opts[:decoded_yaml] do
			nil -> opts
			_ -> construct_opts_from_decoded_yaml(opts)
		end

		mission = struct(Mission, opts)
		mission = %Mission{mission |
			submissions_num: case mission.submissions do
				%{} -> length(Map.keys(mission.submissions))
				[_|_] -> length(mission.submissions)
				_ -> 0
			end,
			key: case mission.key do
				"" -> construct_key(mission.cmd)
				_ -> mission.key
			end,
		}

		case mission do
			%{cmd: nil, submissions: nil} ->
				raise "Must have cmd or submissions, got #{inspect(opts[:decoded_yaml])}"
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
			%{} -> construct_opts_from_map(opts)
			_ -> opts ++ [cmd: decoded_yaml]
		end
	end

	defp construct_opts_from_map(opts) do
		map = opts[:decoded_yaml]
		keys = Map.keys(map)

		opts ++ case length(keys) do
			0 -> raise "Empty map?"
			_ -> construct_map_opts(map)
		end
	end

	defp construct_key(name) do
		name = name || ""
		name = String.replace(name, ~r/ /, "_")
		name = String.replace(name, ~r/[^_a-zA-Z0-9]/, "")
		String.downcase(name)
	end

	defp construct_map_opts(map) do
		new_map = [
			key: construct_key(map["name"]),
			input_file: case Map.has_key?(map, "input") do
				false -> "$IN"
				true -> map["input"]
			end,
		]

		submissions = map["missions"]
		new_map ++ cond do
			is_map(submissions) -> [submissions: submissions, fail_fast: map["fail_fast"] || false]
			is_list(submissions) -> [submissions: submissions]
			true -> [cmd: submissions]
		end
	end

	#########
	# CASTS #
	#########

	def handle_cast({:finished, result, prev_mpid}, mission) do
		# Add prev_mpid to finished submissions
		sub_pids = mission.finished_submission_pids
		sub_pids = case prev_mpid do
			nil -> sub_pids
			x -> sub_pids ++ [x]
		end

		exit_codes = sub_pids
			|> Enum.map(&(Mission.get(&1).exit_code))
			|> Enum.filter(&(&1))

		# Check if a failure should trigger a fail_fast behavior
		check = length(exit_codes) > 0
			and Enum.max(exit_codes) > 0
			and mission.fail_fast

		# If a fail_fast situation is warranted,
		# Send kill signal to all submissions
		if (check) do
			mission.submission_pids
				|> Enum.map(&Mission.get/1)
				|> Enum.map(&(FieldAgent.stop(&1.field_agent_pid)))
		end

		exit_code = case length(exit_codes) do
			0 -> result.status
			_ -> cond do
				check -> Enum.max(exit_codes)
				length(exit_codes) != mission.submissions_num -> nil
				true -> Enum.max(exit_codes)
			end
		end

		# If a nil exit code, then submissions have not finished and more should be queued up
		# Else tell the field agent that the mission is finished
		[finished, running] = case {exit_code, mission.finished} do
			{nil, _} ->
				Mission.run_submissions(self(), prev_mpid)
				[false, true]
			{0, true} ->
				raise "Got a finished message but already finished"
			{_, true} ->
				[true, false]
			_ ->
				FieldAgent.mission_has_finished(mission.field_agent_pid, result)
				[true, false]
		end

		{:noreply, %Mission{mission |
			exit_code: exit_code,
			finished: finished,
			running: running,
			finished_submission_pids: sub_pids,
		}}
	end

	def handle_cast({:data_and_metadata, data}, mission) do
		if mission.supermission_pid do
			pids = [self()] ++ data[:pid]
			new_data = Keyword.delete(data, :pid)
			Mission.send(mission.supermission_pid, new_data ++ [pid: pids])
		else
			MissionReport.send_data(mission.report_pid, data)
		end

		{:noreply, %Mission{mission | output: mission.output ++ [data]}}
	end

	def handle_cast({:init_submission, pid}, mission) do
		submission_pids = mission.submission_pids ++ [pid]
		{:noreply, %Mission{mission | submission_pids: submission_pids}}
	end

	def handle_cast({:run_submissions, prev_pid}, mission) do
		[running, remaining] = case mission.submissions do
			%{} -> [Enum.map(mission.submissions, &convert_parallel_mission/1), %{}]
			[a|b] -> [[a], b]
			[] -> [[], []]
		end

		for submission <- running do
			opts = [decoded_yaml: submission, supermission_pid: self(), prev_mission_pid: prev_pid]
			MissionReport.init_mission(mission.report_pid, opts)
		end

		{:noreply, %Mission{mission | submissions: remaining}}
	end

	defp convert_parallel_mission({key, value}) do
		case value do
			%{} -> Map.put_new(value, "name", key)
			[_|_] -> raise "Can't be a list"
			[] -> raise "Can't be a list"
			_ -> %{"missions" => value}
		end
	end

	#########
	# CALLS #
	#########

	def handle_call({:set_as_running, field_agent}, _from, mission) do
		mission = %Mission{mission | running: true, field_agent_pid: field_agent}
		{:reply, mission, mission}
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

	def handle_call({:get_output, _output_key}, _from, mission) do
		output = Enum.map(mission.output, &(&1[:data]))
		{:reply, output, mission}
	end

	def handle_call(:get_outpost, _from, mission) do
		field_agent = FieldAgent.get(mission.field_agent_pid)
		{:reply, field_agent.outpost_pid, mission}
	end

	def handle_call(:get_outpost_plan, _from, mission) do
		plan = case mission.decoded_yaml do
			%{"outpost" => plan} -> plan
			_ -> nil
		end
		{:reply, plan, mission}
	end

end
