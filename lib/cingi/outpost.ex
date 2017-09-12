defmodule Cingi.Outpost do
	@moduledoc """
	Outposts are processes set up by commanders to connect to its branch
	and receive missions. Outposts have to set up the environment,
	like a workspace folder, or can be set up inside docker containers
	"""

	alias Cingi.Outpost
	alias Cingi.Branch
	alias Cingi.FieldAgent
	alias Cingi.Mission
	alias Cingi.MissionReport
	use GenServer

	defstruct [
		name: nil,
		node: nil,

		pid: nil,
		branch_pid: nil,
		parent_pid: nil,
		root_mission_pid: nil,

		setup_steps: nil,
		alternates: nil,

		plan: %{},
		is_setup: false,
		setting_up: false,
		setup_failed: false,
		dir: ".",
		env: %{},

		queued_field_agents: [],
		missions: [],
	]

	# Client API

	def start_link(args \\ []) do
		opts = case args[:name] do
			nil -> []
			name -> [name: name]
		end
		GenServer.start_link(__MODULE__, args, opts)
	end

	def get(pid) do
		GenServer.call(pid, :get)
	end

	def get_version_on_branch(pid, branch_pid) do
		GenServer.call(pid, {:outpost_on_branch, branch_pid})
	end

	def create_version_on_branch(pid, branch_pid) do
		start_link(original: pid, branch_pid: branch_pid)
	end

	def get_or_create_version_on_branch(pid, branch_pid) do
		case get_version_on_branch(pid, branch_pid) do
			nil -> create_version_on_branch(pid, branch_pid)
			x -> {:ok, x}
		end
	end

	def field_agent_data(pid, fa_pid, data) do
		GenServer.cast(pid, {:field_agent_data, fa_pid, data})
	end

	def run_mission(pid, mission) do
		GenServer.cast(pid, {:run_mission, mission})
	end

	def mission_has_run(pid, mission_pid) do
		GenServer.cast(pid, {:mission_has_run, mission_pid})
	end

	def mission_plan_has_finished(pid, fa_pid) do
		GenServer.cast(pid, {:mission_plan_has_finished, fa_pid})
	end

	def mission_has_finished(pid, mission_pid, result) do
		GenServer.cast(pid, {:mission_has_finished, mission_pid, result})
	end

	def report_has_finished(pid, report_pid, mission_pid) do
		GenServer.cast(pid, {:report_has_finished, report_pid, mission_pid})
	end

	def setup_with_steps(pid) do
		GenServer.cast(pid, :setup_with_steps)
	end

	def queue_field_agent_for_plan(pid, file, fa_pid) do
		GenServer.cast(pid, {:queue_field_agent, {:mission_plan, fa_pid, file}})
	end

	def queue_field_agent_for_bash(pid, fa_pid) do
		GenServer.cast(pid, {:queue_field_agent, {:bash_process, fa_pid}})
	end

	# Call explicitely, don't use Agent module with anonymous functions
	# See section on "A word on distributed agents"
	# https://github.com/elixir-lang/elixir/blob/cddc99b1d393e99a45db239334aba7bcbff3b218/lib/elixir/lib/agent.ex#L102
	def get_alternates(pid) do
		GenServer.call(pid, :get_alternates)
	end

	def update_alternates(pid) do
		GenServer.cast(pid, :update_alternates)
	end

	def update_parent(pid) do
		GenServer.cast(pid, :update_parent)
	end

	# Server Callbacks

	def init(opts) do
		outpost = case opts[:original] do
			nil -> struct(Outpost, opts)
			opid ->
				o = Outpost.get opid
				%Outpost{
					name: o.name,
					alternates: o.alternates,
					parent_pid: o.parent_pid,
					plan: o.plan,
					root_mission_pid: o.root_mission_pid,
					setup_steps: o.setup_steps
				}
		end

		outpost = %Outpost{outpost |
			node: Node.self,
			branch_pid: opts[:branch_pid],
			pid: self(),
			setup_steps: outpost.plan["setup_steps"]
		}

		Outpost.update_parent(self())
		Outpost.update_alternates(self())
		{:ok, outpost}
	end

	def handle_call(:get, _from, outpost) do
		{:reply, outpost, outpost}
	end

	def handle_call({:outpost_on_branch, branch_pid}, _from, outpost) do
		alternate = Agent.get(outpost.alternates, &(&1))[branch_pid]
		{:reply, alternate, outpost}
	end

	def handle_call(:get_alternates, _from, outpost) do
		alternates = Agent.get(outpost.alternates, &(&1))
		{:reply, alternates, outpost}
	end

	def handle_cast({:field_agent_data, _fa_pid, data}, outpost) do
		Branch.outpost_data(outpost.branch_pid, self(), data)
		{:noreply, outpost}
	end

	def handle_cast(:update_parent, outpost) do
		# Parent may not live on same branch, so create version of parent that does
		{:ok, parent_pid} = case {outpost.parent_pid, outpost.branch_pid} do
			{nil, _} -> {:ok, nil}
			{_, nil} -> {:ok, nil}
			{ppid, bpid} -> Outpost.get_or_create_version_on_branch(ppid, bpid)
		end
		{:noreply, %Outpost{outpost | parent_pid: parent_pid}}
	end

	def handle_cast(:update_alternates, outpost) do
		{:ok, alternates} = case outpost.alternates do
			nil -> Agent.start_link fn -> %{} end
			x -> {:ok, x}
		end

		self_pid = self()
		Agent.update(alternates, &(Map.put(&1, outpost.branch_pid, self_pid)))

		{:noreply, %Outpost{outpost | alternates: alternates}}
	end

	def handle_cast({:run_mission, mission}, outpost) do
		FieldAgent.start_link(mission_pid: mission, outpost_pid: self())
		{:noreply, %Outpost{outpost | missions: outpost.missions ++ [mission]}}
	end

	def handle_cast({:mission_has_run, mission_pid}, outpost) do
		Branch.mission_has_run(outpost.branch_pid, mission_pid)
		{:noreply, outpost}
	end

	def handle_cast({:mission_plan_has_finished, fa_pid}, outpost) do
		FieldAgent.run_mission(fa_pid)
		{:noreply, outpost}
	end

	def handle_cast({:mission_has_finished, mission_pid, result}, outpost) do
		Branch.mission_has_finished(outpost.branch_pid, mission_pid, result)
		{:noreply, outpost}
	end

	def handle_cast(:setup_with_steps, outpost) do
		outpost = case outpost.setting_up do
			true -> outpost
			false ->
				case {outpost.setup_steps, outpost.parent_pid} do
					{nil, nil} -> Outpost.report_has_finished(self(), nil, nil)
					{setup_steps, _} ->
						setup_steps = setup_steps || [":"]
						root_mission = Mission.get(outpost.root_mission_pid)

						yaml_opts = [
							prev_mission_pid: root_mission.prev_mission_pid,
							map: %{"missions" => setup_steps},
							outpost_pid: self(),
						]
						Branch.queue_report outpost.branch_pid, yaml_opts
				end
				%Outpost{outpost | setting_up: true}
		end
		{:noreply, outpost}
	end

	def handle_cast({:queue_field_agent, queued_fa_tup}, outpost) do
		fa_pid = elem(queued_fa_tup, 1)
		if outpost.setup_failed do FieldAgent.stop(fa_pid) end

		outpost = case outpost.is_setup do
			true ->
				run_field_agent(queued_fa_tup, outpost)
				outpost
			false ->
				Outpost.setup_with_steps self()
				queue = outpost.queued_field_agents ++ [queued_fa_tup]
				%Outpost{outpost | queued_field_agents: queue}
		end
		{:noreply, outpost}
	end

	def handle_cast({:report_has_finished, _report_pid, mission_pid}, outpost) do
		# Get last line of output from setup and see if it is in a proper format
		output = try do
			Mission.get_output(mission_pid)
				|> Enum.join("\n")
				|> String.split("\n", trim: true)
				|> Enum.take(-1)
				|> Enum.at(0)
				|> YamlElixir.read_from_string
		rescue
			_ -> %{}
		end

		replace_with = fn(var) ->
			case MissionReport.parse_variable(var) do
				[type: "SETUP", key: key] -> output[key]
				_ -> var
			end
		end

		base_outpost = case outpost.parent_pid do
			nil -> outpost
			ppid -> Outpost.get(ppid)
		end

		base_dir = outpost.plan["dir"] || base_outpost.dir
		base_env = Map.merge(base_outpost.env, outpost.plan["env"] || %{})

		dir = replace_with.(base_dir)
		env = base_env
			|>
				Enum.map(fn({k, v}) ->
					{replace_with.(k), replace_with.(v)}
				end)
			|>
				Enum.filter(fn(x) ->
					case x do
						{nil, _} -> false
						{_, nil} -> false
						_ -> true
					end
				end)
			|> Enum.into(%{})

		exit_code = case mission_pid do
			nil -> 0
			_ -> Mission.get(mission_pid).exit_code
		end

		setup_failed = case exit_code do
			0 -> false
			_ -> Enum.map(outpost.queued_field_agents, &(FieldAgent.stop(elem(&1, 1))))
				true
		end

		outpost = %Outpost{outpost |
			dir: dir || ".",
			env: env,
		}

		Enum.map(outpost.queued_field_agents, &(run_field_agent(&1, outpost)))

		{:noreply, %Outpost{outpost |
			is_setup: true,
			setting_up: false,
			setup_failed: setup_failed,
			queued_field_agents: [],
		}}
	end

	###########
	# HELPERS #
	###########

	def run_field_agent({:bash_process, fa_pid}, _outpost) do
		FieldAgent.run_bash_process fa_pid
	end

	def run_field_agent({:mission_plan, fa_pid, file}, outpost) do
		path = Path.join(outpost.dir, file)
		plan = try do
			YamlElixir.read_from_file path
		catch
			_ ->
				IO.puts :stderr, "File #{path} does not exist here in #{System.cwd}"
				%{}
		end

		FieldAgent.send_mission_plan(fa_pid, plan, nil, fa_pid)
	end
end
