defmodule Cingi.Headquarters do
	@moduledoc """
	Headquarters manage all the branches within the cluster
	and assign mission to branches based on capacity.
	There should only be one Headquarters at each cluster.
	If a branch is started without a Headquarters, and
	doesn't intend to connect to an existing cluster,
	a Headquarters should be created for it.
	"""

	alias Cingi.Headquarters
	alias Cingi.Branch
	alias Cingi.Mission
	alias Cingi.MissionReport
	use GenServer

	defstruct [
		node: nil,
		running: true,
		branch_pids: [],
		queued_missions: [],
		running_missions: %{},
		finished_missions: %{},
	]

	def start_link(opts \\ []) do
		GenServer.start_link(__MODULE__, [], opts)
	end

	def get(pid) do
		GenServer.call pid, :get
	end

	def pause(pid) do
		GenServer.call pid, :pause
	end

	def resume(pid) do
		GenServer.call pid, :resume
	end

	def link_branch(pid, branch_pid) do
		# May be passed in name, so get real pid while still in same node
		branch = Branch.get(branch_pid)
		true_branch_pid = branch.pid
		GenServer.call pid, {:link_branch, true_branch_pid, Node.self}
	end

	def terminate_branches(pid) do
		GenServer.call pid, :terminate_branches
	end

	def queue_mission(pid, mission_pid) do
		GenServer.cast pid, {:queue_mission, mission_pid}
	end

	def run_missions(pid) do
		GenServer.cast pid, :run_missions
	end

	def finished_mission(pid, mission_pid, result, branch_pid) do
		GenServer.cast pid, {:finished_mission, mission_pid, result, branch_pid}
	end

	# Server Callbacks

	def init(_) do
		headquarters = %Headquarters{node: Node.self}
		{:ok, headquarters}
	end

	def handle_call(:get, _from, hq) do
		{:reply, hq, hq}
	end

	def handle_call(:pause, _from, hq) do
		hq = %Headquarters{hq | running: false}
		for b <- get_all_branches(hq) do Branch.pause(b) end
		{:reply, hq, hq}
	end

	def handle_call(:resume, _from, hq) do
		hq = %Headquarters{hq | running: true}
		for b <- get_all_branches(hq) do Branch.resume(b) end
		Headquarters.run_missions(self())
		{:reply, hq, hq}
	end

	def handle_call({:link_branch, branch_pid, branch_node}, _from, hq) do
		Node.monitor branch_node, true
		hq = %Headquarters{hq | branch_pids: hq.branch_pids ++ [branch_pid]}
		Branch.link_headquarters(branch_pid, self())
		{:reply, hq, hq}
	end

	def handle_call(:terminate_branches, _from, hq) do
		get_all_branches(hq) |> Enum.map(&Branch.terminate/1)
		{:reply, hq, hq}
	end

	def handle_cast({:queue_mission, mission_pid}, hq) do
		missions = hq.queued_missions ++ [mission_pid]
		Headquarters.run_missions(self())
		{:noreply, %Headquarters{hq | queued_missions: missions}}
	end

	def handle_cast(:run_missions, hq) do
		hq = try do
			if not hq.running do raise "Not running" end

			[mission | queued_missions] = hq.queued_missions

			branch_pid = get_branch(hq)
			branch_missions = Map.get(hq.running_missions, branch_pid, []) ++ [mission]
			Branch.run_mission(branch_pid, mission)

			%Headquarters{hq |
				queued_missions: queued_missions,
				running_missions: Map.put(hq.running_missions, branch_pid, branch_missions),
			}
		rescue
			MatchError -> hq
			RuntimeError -> hq
		end
		{:noreply, hq}
	end

	def handle_cast({:finished_mission, mission_pid, result, branch_pid}, hq) do
		mission = Mission.get(mission_pid)
		super_pid = mission.supermission_pid
		report_pid = mission.report_pid

		cond do
			super_pid -> Mission.send_result(super_pid, result, mission_pid)
			report_pid -> MissionReport.finished_mission(report_pid, mission_pid)
			true -> :ok
		end

		running = hq.running_missions
			|> Map.get(branch_pid, [])
			|> List.delete(mission_pid)

		finished = Map.get(hq.running_missions, branch_pid, []) ++ [mission_pid]

		{:noreply, %Headquarters{hq |
			running_missions: Map.put(hq.running_missions, branch_pid, running),
			finished_missions: Map.put(hq.finished_missions, branch_pid, finished),
		}}
	end

	def handle_info({:nodedown, _}, hq) do
		self_pid = self()
		{up, _} = get_all_branches(hq, false)
		{running, stopped} = hq.running_missions |> Map.split(up)
		stopped
			|> Enum.map(&(elem(&1, 1)))
			|> List.flatten
			|> Enum.map(fn (m) ->
				Mission.send_result(m, %{status: 221}, m)
				Headquarters.finished_mission(self_pid, m, %{status: 221}, nil)
			end)

		{:noreply, %Headquarters{
			branch_pids: up,
			running_missions: running,
		}}
	end

	# Get branch with lowerst number of current missions to pass a mission along to
	def get_branch(hq) do
		get_all_branches(hq)
			|> Enum.map(&Branch.get/1)
			|> Enum.min_by(&(length(&1.running_missions) + length(&1.started_missions)))
			|> (fn(b) -> b.pid end).()
	end

	# Get all branches that are currently still alive
	def get_all_branches(hq, get_running_only \\ true) do
		hq.branch_pids
			|> Enum.split_with(fn b ->
				case :rpc.pinfo(b) do
					{:badrpc, _} -> false
					_ -> true
				end
			end)
			|> (fn({up, down}) ->
				case get_running_only do
					true -> up
					false -> {up, down}
				end
			end).()
	end
end
