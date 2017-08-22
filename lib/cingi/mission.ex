defmodule Cingi.Mission do
	alias Cingi.Mission
	alias Cingi.MissionReport
	use GenServer

	defstruct [
		key: "",

		report_pid: nil,
		prev_mission_pid: nil,
		supermission_pid: nil,
		submission_pids: [],
		headquarters_pid: nil,
		outpost_pid: nil,

		decoded_yaml: nil,
		cmd: nil,
		bash_process: nil,
		submissions: nil,
		submissions_num: nil,

		input_file: nil,
		output: [],

		listen_for_api: false, # Enable to listen in the output for any cingi api calls
		output_with_stderr: false, # Stderr will be printed to ouput if false, redirected to output if true
		running: false,
		finished: false,

		exit_code: nil
	]

	# Client API

	def start_link(opts) do
		GenServer.start_link(__MODULE__, opts)
	end

	def run(pid, headquarters_pid \\ nil) do
		GenServer.call(pid, {:run, headquarters_pid})
	end

	def send(pid, data) do
		GenServer.cast(pid, {:data_and_metadata, data})
	end

	def initialized_submission(pid, submission_pid) do
		GenServer.cast(pid, {:init_submission, submission_pid})
	end

	def send_result(pid, finished_pid, result) do
		GenServer.cast(pid, {:finished, finished_pid, result})
	end

	def run_bash_process(pid) do
		GenServer.cast(pid, :run_bash_process)
	end

	def run_submissions(pid, prev_pid \\ nil) do
		GenServer.cast(pid, {:run_submissions, prev_pid})
	end

	def init_input(pid) do
		case pid do
			nil -> nil
			_ -> GenServer.cast(pid, :init_input)
		end
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
			end
		}

		case mission do
			%{cmd: nil, submissions: nil} ->
				raise "Must have cmd or submissions, got #{inspect(opts[:decoded_yaml])}"
			_ -> :ok
		end

		# Construct input file from previous output
		Mission.init_input(self())

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
		new_map = [key: construct_key(map["name"]), input_file: map["input"]]
		submissions = map["missions"]

		new_map ++ cond do
			is_map(submissions) -> [submissions: submissions]
			is_list(submissions) -> [submissions: submissions]
			true -> [cmd: submissions]
		end
	end

	#########
	# CASTS #
	#########

	def handle_cast({:finished, finished_pid, result}, mission) do
		exit_codes = Enum.map(mission.submission_pids, fn m -> Mission.get(m).exit_code end)

		exit_code = case length(exit_codes) do
			0 -> result.status
			_ -> cond do
				length(exit_codes) != mission.submissions_num -> nil
				nil in exit_codes -> nil
				true -> Enum.at(exit_codes, 0)
			end
		end

		case exit_code do
			nil -> Mission.run_submissions(self(), finished_pid)
			_ ->
				super_pid = mission.supermission_pid
				report_pid = mission.report_pid

				cond do
					super_pid -> Mission.send_result(super_pid, self(), result)
					report_pid -> MissionReport.finished_mission(report_pid, self())
					true -> :ok
				end
		end

		{:noreply, %Mission{mission |
			exit_code: exit_code,
			finished: true,
			running: false
		}}
	end

	def handle_cast(:init_input, mission) do
		input_file = case mission.input_file do
			"$" <> output_key ->
				Temp.track!
				output = Mission.get_output(mission.prev_mission_pid, output_key)
				{:ok, fd, path} = Temp.open
				IO.write fd, output
				path
			_ -> mission.input_file
		end
		{:noreply, %Mission{mission | input_file: input_file}}
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

	def handle_cast(:run_bash_process, mission) do
		script = "./priv/bin/wrapper.sh"
		cmds = [mission.cmd] ++ case mission.input_file do
			nil -> []
			_ -> [mission.input_file]
		end

		# Porcelain's basic driver only takes nil or :out for err
		err = case mission.output_with_stderr do
			true -> :out
			false -> nil
		end

		proc = Porcelain.spawn(script, cmds, out: {:send, self()}, err: err)
		{:noreply, %Mission{mission | bash_process: proc}}
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

	def handle_call({:run, headquarters_pid}, _from, mission) do
		cond do
			mission.cmd -> Mission.run_bash_process(self())
			mission.submissions -> Mission.run_submissions(self())
		end
		mission = %Mission{mission | running: true, headquarters_pid: headquarters_pid}
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

	#########
	# INFOS #
	#########

	def handle_info({_pid, :data, :out, data}, mission) do
		add_to_output(mission, data: data, type: :out)
	end

	def handle_info({_pid, :data, :err, data}, mission) do
		add_to_output(mission, data: data, type: :err)
	end

	def handle_info({_pid, :result, result}, mission) do
		Mission.send_result(self(), self(), result)
		{:noreply, mission}
	end

	defp add_to_output(mission, opts) do
		time = :os.system_time(:millisecond)
		Mission.send(self(), opts ++ [timestamp: time, pid: []])
		{:noreply, mission}
	end

end
