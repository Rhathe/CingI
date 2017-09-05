defmodule Cingi.FieldAgent do
	@moduledoc """
	Field agents are processes that are assigned a mission by an outpost
	Typically they run the bash command in the same environment as the outpost
	They run on the same noide as the outpost but report the output to the mission
	"""

	alias Cingi.FieldAgent
	alias Cingi.Outpost
	alias Cingi.Mission
	alias Cingi.MissionReport
	alias Porcelain.Process, as: Proc
	use GenServer

	defstruct [
		mission_pid: nil,
		outpost_pid: nil,
		proc: nil,
	]

	# Client API

	def start_link(args \\ []) do
		GenServer.start_link(__MODULE__, args, [])
	end

	def get(pid) do
		GenServer.call(pid, :get)
	end

	def stop(pid) do
		GenServer.cast(pid, :stop)
	end

	def run_bash_process(pid) do
		GenServer.cast(pid, :run_bash_process)
	end

	def send_result(pid, result, prev_mpid \\ nil) do
		GenServer.cast(pid, {:result, result, prev_mpid})
	end

	def mission_has_finished(pid, result) do
		GenServer.cast(pid, {:mission_has_finished, result})
	end

	# Server Callbacks

	def init(opts) do
		field_agent = struct(FieldAgent, opts)
		mpid = field_agent.mission_pid
		mission = Mission.get(mpid)

		Mission.set_as_running(mpid, self())
		Outpost.mission_has_run(field_agent.outpost_pid, mpid)

		cond do
			mission.skipped -> FieldAgent.send_result(self(), %{status: nil})
			mission.cmd -> FieldAgent.run_bash_process(self())
			mission.submissions -> Mission.run_submissions(mpid, mission.prev_mission_pid)
		end

		{:ok, field_agent}
	end

	def handle_call(:get, _from, field_agent) do
		{:reply, field_agent, field_agent}
	end

	def handle_cast(:stop, field_agent) do
		mission = Mission.get(field_agent.mission_pid)
		case mission.cmd do
			nil ->
				mission.submission_holds |> Enum.map(fn(h) ->
					sub = Mission.get(h.pid)
					FieldAgent.stop(sub.field_agent_pid)
				end)
			_ -> case field_agent.proc do
					nil -> :ok
					_ -> Proc.send_input field_agent.proc, "kill\n"
				end
		end
		{:noreply, field_agent}
	end

	def handle_cast(:run_bash_process, field_agent) do
		mission = Mission.get(field_agent.mission_pid)
		script = "./priv/bin/wrapper.sh"
		{input_file, is_tmp} = init_input_file(mission)

		cmds = [mission.cmd] ++ case input_file do
			nil -> []
			false -> []
			_ -> [input_file, is_tmp]
		end

		# Porcelain's basic driver only takes nil or :out for err
		err = case mission.output_with_stderr do
			true -> :out
			false -> nil
		end

		proc = Porcelain.spawn(script, cmds, in: :receive, out: {:send, self()}, err: err)
		{:noreply, %FieldAgent{field_agent | proc: proc}}
	end

	def handle_cast({:result, result, prev_mpid}, field_agent) do
		mpid = field_agent.mission_pid
		Mission.send_result(mpid, result, prev_mpid)
		{:noreply, field_agent}
	end

	def handle_cast({:mission_has_finished, result}, field_agent) do
		Outpost.mission_has_finished(field_agent.outpost_pid, field_agent.mission_pid, result)
		{:noreply, field_agent}
	end

	#########
	# INFOS #
	#########

	def handle_info({_pid, :data, :out, data}, field_agent) do
		add_to_output(field_agent, data: data, type: :out)
	end

	def handle_info({_pid, :data, :err, data}, field_agent) do
		add_to_output(field_agent, data: data, type: :err)
	end

	def handle_info({_pid, :result, result}, field_agent) do
		FieldAgent.send_result(self(), result)
		{:noreply, field_agent}
	end

	###########
	# HELPERS #
	###########

	defp add_to_output(field_agent, opts) do
		time = :os.system_time(:millisecond)
		data = opts ++ [timestamp: time, pid: []]
		Mission.send(field_agent.mission_pid, data)
		Outpost.field_agent_data(field_agent.outpost_pid, self(), data)
		{:noreply, field_agent}
	end

	# Return {path_of_file, _boolean_indicating_whether_its_a_tmp_file}
	def init_input_file(mission) do
		input = case mission.input_file do
			n when n in [nil, false, []] -> []
			[_|_] -> mission.input_file
			input -> [input]
		end

		input = input
			|> Enum.map(fn (x) ->
				case MissionReport.parse_variable(x, last_index: mission.submissions_num - 1) do
					[error: _] -> :error
					[type: "IN"] -> Mission.get_output(mission.prev_mission_pid)
					[type: "IN", key: key] -> Mission.get_output(mission.prev_mission_pid, key)
					[type: "IN", index: index] -> Mission.get_output(mission.prev_mission_pid, index)
				end
			end)

		case input do
			[] -> {nil, false}
			input ->
				input = Enum.join(input)
				{:ok, fd, path} = Temp.open
				IO.write fd, input
				File.close fd
				{path, true}
		end
	end
end
