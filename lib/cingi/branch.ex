defmodule Cingi.Branch do
	alias Cingi.Branch
	alias Cingi.FieldAgent
	alias Cingi.Outpost
	alias Cingi.Mission
	alias Cingi.MissionReport
	use GenServer

	defstruct [
		node: nil,
		pid: nil,
		name: nil,
		running: true,
		mission_reports: [],
		queued_missions: [],
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

	def run_missions(pid) do
		GenServer.cast(pid, :run_missions)
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
		branch = %Branch{
			node: Node.self,
			pid: self(),
			name: opts[:name],
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
		Branch.run_missions(self())
		{:reply, branch, branch}
	end

	def handle_call(:get, _from, branch) do
		{:reply, branch, branch}
	end

	def handle_cast({:init_mission, opts}, branch) do
		{:ok, mission} = Mission.start_link(opts)
		missions = branch.queued_missions ++ [mission]
		Branch.run_missions(self())
		{:noreply, %Branch{branch | queued_missions: missions}}
	end

	def handle_cast(:run_missions, branch) do
		branch = try do
			if not branch.running do raise "Not running" end

			[mission | queued_missions] = branch.queued_missions

			Branch.send_mission_to_outpost(self(), mission)
			%Branch{branch |
				queued_missions: queued_missions,
				started_missions: branch.started_missions ++ [mission]
			}
		rescue
			MatchError -> branch
			RuntimeError -> branch
		end
		{:noreply, branch}
	end

	# Getting of the outpost should be handled by the specific Branch 
	# Because a Mission could have initialized at a different Branch
	# than the one currently running it, so the outpost that's retrieved
	# should be the one on the same node as the Branch running the mission
	def handle_cast({:outpost_for_mission, mission}, branch) do
		# See if mission has an outpost configuration
		# if so, use that to start initialize a new outpost,
		# otherwise use an outpost from this mission's supermission,
		# constructing on this node if necessary
		{:ok, outpost} = case Mission.get_outpost_plan(mission) do
			nil ->
				case Mission.get(mission).supermission_pid do
					nil -> Outpost.start_link()
					supermission ->
						outpost = Mission.get_outpost(supermission)
						{:ok, Outpost.get_or_create_on_same_node(outpost)}
				end
			plan -> Outpost.start_link(plan)
		end

		Outpost.set_branch(outpost, self())
		Outpost.run_mission(outpost, mission)
		{:noreply, branch}
	end

	def handle_cast({:mission_has_run, mission_pid}, branch) do
		started_missions = cond do
			mission_pid in branch.started_missions -> List.delete(branch.started_missions, mission_pid)
			true -> raise "Mission ran but not started"
		end
		Branch.run_missions(self())
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
end
