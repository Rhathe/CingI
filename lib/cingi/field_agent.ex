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
		node: nil,
		proc: nil,
		constructed_plan: %{},
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

	def run_mission(pid) do
		GenServer.cast(pid, :run_mission)
	end

	def run_bash_process(pid) do
		GenServer.cast(pid, :run_bash_process)
	end

	def send_mission_plan(pid, plan, from_pid, next_mpid \\ nil) do
		GenServer.cast(pid, {:received_mission_plan, plan, from_pid, next_mpid})
	end

	def finish_mission_plan(pid) do
		GenServer.cast(pid, :finish_mission_plan)
	end

	def mission_has_finished(pid, result) do
		GenServer.cast(pid, {:mission_has_finished, result})
	end

	def queue_other_field_agent_on_outpost_of_branch(pid, file, callback_fa_pid, branch_pid) do
		GenServer.cast(pid, {:queue_other_field_agent_on_outpost_of_branch, file, callback_fa_pid, branch_pid})
	end

	def send_result(pid, result, finished_mpid) do
		GenServer.cast(pid, {:result, result, finished_mpid})
	end

	# Server Callbacks

	def init(opts) do
		field_agent = struct(FieldAgent, opts)
		mpid = field_agent.mission_pid
		Mission.set_field_agent(mpid, self())
		{:ok, %FieldAgent{field_agent | node: Node.self}}
	end

	def handle_call(:get, _from, field_agent) do
		{:reply, field_agent, field_agent}
	end

	def handle_cast({:received_mission_plan, plan, from_pid, next_mpid}, field_agent) do
		new_plan = case plan do
			%{} -> plan |> Map.merge(field_agent.constructed_plan)
			[] -> %{}
			nil -> %{}
			_ -> %{"missions" => plan}
		end

		case {next_mpid, new_plan} do
			{_, %{"extends_file" => file}} ->
				outpost = Outpost.get(field_agent.outpost_pid)
				branch_pid = outpost.branch_pid
				mission = Mission.get(from_pid)
				FieldAgent.queue_other_field_agent_on_outpost_of_branch(mission.field_agent_pid, file, self(), branch_pid)

			# No more mpids to request from, construct from new_plan regardless
			{nil, _} -> FieldAgent.finish_mission_plan(self())

			# If a key does exist, request for the template with given key from the given mpid
			{mpid, %{"extends_template" => key}} -> Mission.request_mission_plan(mpid, key, self())

			# No more extending, construct_ from new_plan
			_ -> FieldAgent.finish_mission_plan(self())

		end

		new_plan = new_plan
			|> Map.delete("extends_template")
			|> Map.delete("extends_file")

		{:noreply, %FieldAgent{field_agent | constructed_plan: new_plan}}
	end

	def handle_cast({:queue_other_field_agent_on_outpost_of_branch, file, callback_fa_pid, branch_pid}, field_agent) do
		outpost_pid = Outpost.get_version_on_branch(field_agent.outpost_pid, branch_pid)
		Outpost.queue_field_agent_for_plan(outpost_pid, file, callback_fa_pid)
		{:noreply, field_agent}
	end

	def handle_cast(:finish_mission_plan, field_agent) do
		Mission.construct_from_plan(field_agent.mission_pid, field_agent.constructed_plan)
		Outpost.mission_plan_has_finished(field_agent.outpost_pid, self())
		{:noreply, field_agent}
	end

	def handle_cast(:run_mission, field_agent) do
		mpid = field_agent.mission_pid
		mission = Mission.get(mpid)
		Outpost.mission_has_run(field_agent.outpost_pid, mpid)

		cond do
			mission.skipped -> FieldAgent.send_result(self(), %{status: nil}, mpid)
			mission.cmd -> Outpost.queue_field_agent_for_bash(field_agent.outpost_pid, self())
			mission.submissions -> Mission.run_submissions(mpid, mission.prev_mission_pid)
		end

		{:noreply, field_agent}
	end

	def handle_cast(:stop, field_agent) do
		case field_agent.proc do
			nil -> :ok
			_ -> Proc.send_input field_agent.proc, "kill\n"
		end
		FieldAgent.send_result(self(), %{status: 137}, field_agent.mission_pid)
		{:noreply, field_agent}
	end

	def handle_cast(:run_bash_process, field_agent) do
		mpid = field_agent.mission_pid
		mission = Mission.get(mpid)

		proc = case mission.finished do
			true -> nil
			false ->
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

				outpost = Outpost.get(field_agent.outpost_pid)
				env = convert_env(outpost.env)
				dir = outpost.dir

				try do
					Porcelain.spawn(script, cmds, dir: dir, env: env, in: :receive, out: {:send, self()}, err: err)
				rescue
					# Error, send result as a 137 sigkill
					_ -> FieldAgent.send_result(self(), %{status: 137}, mpid)
				end
		end
		{:noreply, %FieldAgent{field_agent | proc: proc}}
	end

	def handle_cast({:result, result, finished_mpid}, field_agent) do
		mpid = field_agent.mission_pid
		Mission.send_result(mpid, result, finished_mpid)
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
		FieldAgent.send_result(self(), result, field_agent.mission_pid)
		{:noreply, field_agent}
	end

	###########
	# HELPERS #
	###########

	defp add_to_output(field_agent, opts) do
		time = :os.system_time(:millisecond)
		data = opts ++ [timestamp: time, field_agent_pid: self(), pid: []]
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

	def convert_env(env_map) do
		Enum.map(env_map || %{}, &(&1))
	end
end
