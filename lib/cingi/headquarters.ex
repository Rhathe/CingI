defmodule Cingi.Headquarters do
	alias Cingi.Headquarters
	alias Cingi.Mission
	alias Cingi.MissionReport
	use GenServer

	defstruct [
		node: nil,
		running: true,
		mission_reports: [],
		queued_missions: [],
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
			Mission.run(mission, self())
			Headquarters.run_missions(self())
			%Headquarters{headquarters |
				queued_missions: queued_missions,
				running_missions: headquarters.running_missions ++ [mission]
			}
		rescue
			MatchError -> headquarters
			RuntimeError -> headquarters
		end
		{:noreply, headquarters}
	end
end
