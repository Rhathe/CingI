defmodule Cingi.Headquarters do
	alias Cingi.Headquarters
	alias Cingi.Outpost
	alias Cingi.Mission
	alias Cingi.MissionReport
	use GenServer

	defstruct [
		node: nil,
		running: true,
		mission_reports: [],
		queued_missions: [],
		started_missions: [],
		running_missions: [],
		finished_missions: [],
	]

	def start_link(opts \\ []) do
		GenServer.start_link(__MODULE__, [], opts)
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

	def init(_) do
		headquarters = %Headquarters{node: Node.self}
		{:ok, headquarters}
	end

	def handle_call({:yaml, yaml_tuple}, _from, headquarters) do
		{:ok, missionReport} = MissionReport.start_link(yaml_tuple ++ [headquarters: self()])
		reports = headquarters.mission_reports ++ [missionReport]
		{:reply, missionReport, %Headquarters{headquarters | mission_reports: reports}}
	end

	def handle_call(:pause, _from, headquarters) do
		headquarters = %Headquarters{headquarters | running: false}
		for m <- headquarters.running_missions do Mission.pause(m) end
		{:reply, headquarters, headquarters}
	end

	def handle_call(:resume, _from, headquarters) do
		headquarters = %Headquarters{headquarters | running: true}
		for m <- headquarters.running_missions do Mission.resume(m) end
		Headquarters.run_missions(self())
		{:reply, headquarters, headquarters}
	end

	def handle_call(:get, _from, hq) do
		{:reply, hq, hq}
	end

	def handle_cast({:init_mission, opts}, headquarters) do
		{:ok, mission} = Mission.start_link(opts)
		missions = headquarters.queued_missions ++ [mission]
		Headquarters.run_missions(self())
		{:noreply, %Headquarters{headquarters | queued_missions: missions}}
	end

	def handle_cast(:run_missions, headquarters) do
		headquarters = try do
			if not headquarters.running do raise "Not running" end

			[mission | queued_missions] = headquarters.queued_missions

			Headquarters.send_mission_to_outpost(self(), mission)
			%Headquarters{headquarters |
				queued_missions: queued_missions,
				started_missions: headquarters.started_missions ++ [mission]
			}
		rescue
			MatchError -> headquarters
			RuntimeError -> headquarters
		end
		{:noreply, headquarters}
	end

	# Getting of the outpost should be handled by Headquarters
	# Because a Mission could have initialized at a different HQ
	# than the one currently running it, so the outpost that's retrieved
	# should be the one on the same node as the HQ running the mission
	def handle_cast({:outpost_for_mission, mission}, hq) do
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

		Outpost.set_hq(outpost, self())
		Outpost.run_mission(outpost, mission)
		{:noreply, hq}
	end

	def handle_cast({:mission_has_run, mission_pid}, hq) do
		started_missions = cond do
			mission_pid in hq.started_missions -> List.delete(hq.started_missions, mission_pid)
			true -> raise "Mission ran but not started"
		end
		Headquarters.run_missions(self())
		{:noreply, %Headquarters{hq |
			started_missions: started_missions,
			running_missions: hq.running_missions ++ [mission_pid],
		}}
	end
end
