defmodule Cingi.Branch do
	alias Cingi.Branch
	alias Cingi.FieldAgent
	alias Cingi.Headquarters
	alias Cingi.Outpost
	alias Cingi.Mission
	alias Cingi.MissionReport
	use GenServer

	defstruct [
		node: nil,
		pid: nil,
		name: nil,

		hq_pid: nil,
		cli_pid: nil, # Get cli pid if run through cli

		running: true,
		mission_reports: [],
		started_missions: [],
		running_missions: [],
		finished_missions: [],
	]

	def start_link(args \\ []) do
		GenServer.start_link(__MODULE__, args, [name: args[:name]])
	end

	def create_report(pid, yaml_tuple) do
		GenServer.call(pid, {:yaml, yaml_tuple})
	end

	def init_mission(pid, opts) do
		GenServer.cast(pid, {:init_mission, opts})
	end

	def run_mission(pid, mission) do
		GenServer.cast(pid, {:run_mission, mission})
	end

	def send_mission_to_outpost(pid, mission_pid) do
		GenServer.cast(pid, {:outpost_for_mission, mission_pid})
	end

	def mission_has_run(pid, mission_pid) do
		GenServer.cast(pid, {:mission_has_run, mission_pid})
	end

	def mission_has_finished(pid, mission_pid, result) do
		GenServer.cast(pid, {:mission_has_finished, mission_pid, result})
	end

	def report_has_finished(pid, report_pid, mission_pid) do
		GenServer.cast(pid, {:report_has_finished, report_pid, mission_pid})
	end

	def outpost_data(pid, outpost_pid, data) do
		GenServer.cast(pid, {:outpost_data, outpost_pid, data})
	end

	def report_data(pid, report_pid, data) do
		GenServer.cast(pid, {:report_data, report_pid, data})
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

	def link_headquarters(pid, hq_pid) do
		GenServer.call(pid, {:link_headquarters, hq_pid})
	end

	def link_cli(pid, cli_pid) do
		GenServer.call(pid, {:link_cli, cli_pid})
	end

	# Server Callbacks

	def init(opts) do
		branch = %Branch{
			node: Node.self,
			pid: self(),
			name: opts[:name],
			hq_pid: nil,
		}
		{:ok, branch}
	end

	def handle_call({:yaml, yaml_tuple}, _from, branch) do
		{:ok, missionReport} = MissionReport.start_link(yaml_tuple ++ [branch_pid: self()])
		reports = branch.mission_reports ++ [missionReport]
		{:reply, missionReport, %Branch{branch | mission_reports: reports}}
	end

	def handle_call(:pause, _from, branch) do
		branch = %Branch{branch | running: false}
		for m <- branch.running_missions do Mission.pause(m) end
		{:reply, branch, branch}
	end

	def handle_call(:resume, _from, branch) do
		branch = %Branch{branch | running: true}
		for m <- branch.running_missions do Mission.resume(m) end
		Headquarters.run_missions(branch.hq_pid)
		{:reply, branch, branch}
	end

	def handle_call(:get, _from, branch) do
		{:reply, branch, branch}
	end

	def handle_call({:link_headquarters, hq_pid}, _from, branch) do
		branch = %Branch{branch | hq_pid: hq_pid}
		{:reply, branch, branch}
	end

	def handle_call({:link_cli, cli_pid}, _from, branch) do
		branch = %Branch{branch | cli_pid: cli_pid}
		{:reply, branch, branch}
	end

	def handle_cast({:init_mission, opts}, branch) do
		{:ok, mission} = Mission.start_link(opts)

		# Report passes in opts of the report_pid and outpost_pid
		# If there is an outpost_pid, then an outpost sent the report
		case opts[:outpost_pid] do
			# No outpost_pid, sne dto hq for distribution
			nil -> Headquarters.queue_mission(branch.hq_pid, mission)

			# outpost_pid, bypass hq and run on this branch
			_ -> Branch.run_mission(self(), mission)
		end
		{:noreply, branch}
	end

	def handle_cast({:run_mission, mission}, branch) do
		Branch.send_mission_to_outpost(self(), mission)
		branch = %Branch{branch | started_missions: branch.started_missions ++ [mission]}
		{:noreply, branch}
	end

	# Getting of the outpost should be handled by the specific Branch 
	# Because a Mission could have initialized at a different Branch
	# than the one currently running it, so the outpost that's retrieved
	# should be the one on the same node as the Branch running the mission
	def handle_cast({:outpost_for_mission, mission_pid}, branch) do
		mission = Mission.get(mission_pid)

		# The parent outpost process is either the outpost of its supermission
		# or potentially the parent of the outpost that started the mission_report,
		# as that outpost would be for setting up and needs its parent environnment to do so
		parent = case mission.supermission_pid do
			nil ->
				case MissionReport.get(mission.report_pid).outpost_pid do
					nil -> nil
					opid -> Outpost.get(opid).parent_pid
				end
			supermission -> Mission.get_outpost(supermission)
		end

		# See if mission has an outpost configuration
		# if so, use that to start initialize a new outpost,
		# otherwise use an outpost from this mission's supermission,
		# constructing on this node if necessary
		{:ok, outpost} = case {Mission.get_outpost_plan(mission_pid), parent} do
			{nil, nil} -> Outpost.start_link(branch_pid: self())
			{nil, parent} ->
				case Outpost.get_version_on_branch(parent, self()) do
					nil -> Outpost.create_version_on_branch(parent, self())
					x -> {:ok, x}
				end
			{plan, parent} -> Outpost.start_link(branch_pid: self(), plan: plan, parent_pid: parent)
		end

		Outpost.run_mission(outpost, mission_pid)
		{:noreply, branch}
	end

	def handle_cast({:mission_has_run, mission_pid}, branch) do
		started_missions = cond do
			mission_pid in branch.started_missions -> List.delete(branch.started_missions, mission_pid)
			true -> raise "Mission ran but not started"
		end
		Headquarters.run_missions(branch.hq_pid)
		{:noreply, %Branch{branch |
			started_missions: started_missions,
			running_missions: branch.running_missions ++ [mission_pid],
		}}
	end

	def handle_cast({:mission_has_finished, mission_pid, result}, branch) do
		mission = Mission.get(mission_pid)
		super_pid = mission.supermission_pid
		report_pid = mission.report_pid

		cond do
			super_pid ->
				smission = Mission.get(super_pid)
				FieldAgent.send_result(smission.field_agent_pid, result, mission_pid)
			report_pid -> MissionReport.finished_mission(report_pid, mission_pid)
			true -> :ok
		end

		running_missions = cond do
			mission_pid in branch.running_missions -> List.delete(branch.running_missions, mission_pid)
			true -> raise "Mission finished but not ran"
		end

		{:noreply, %Branch{branch |
			running_missions: running_missions,
			finished_missions: branch.finished_missions ++ [mission_pid],
		}}
	end

	def handle_cast({:report_has_finished, _report_pid, _mission_pid}, branch) do
		if (branch.cli_pid) do
			send branch.cli_pid, {:report, self()}
		end
		{:noreply, branch}
	end

	def handle_cast({:outpost_data, _outpost_pid, _data}, branch) do
		if (branch.cli_pid) do
			#IO.puts data[:data]
		end
		{:noreply, branch}
	end

	def handle_cast({:report_data, _report_pid, data}, branch) do
		if (branch.cli_pid) do
			case data[:pid] do
				[] -> [data[:data]]
				[_|_] ->
					keys = data[:pid] |> Enum.map(&(Mission.get(&1).key)) |> Enum.join("|")
					split = String.split(data[:data], "\n")
					split |> Enum.map(&("[#{keys}]    #{&1}"))
			end |> Enum.map(&(IO.puts &1))
		end
		{:noreply, branch}
	end
end
