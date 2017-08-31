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
	use GenServer

	defstruct [
		node: nil,
		running: true,
		branch_pids: [],
		queued_missions: [],
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
		true_branch_pid = Branch.get(branch_pid).pid
		GenServer.call pid, {:link_branch, true_branch_pid}
	end

	def init_mission(pid, opts) do
		GenServer.cast pid, {:init_mission, opts}
	end

	def run_missions(pid) do
		GenServer.cast pid, :run_missions
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

	def handle_call({:link_branch, branch_pid}, _from, hq) do
		hq = %Headquarters{hq | branch_pids: hq.branch_pids ++ [branch_pid]}
		Branch.link_headquarters(branch_pid, self())
		{:reply, hq, hq}
	end

	def handle_cast({:init_mission, opts}, hq) do
		{:ok, mission} = Mission.start_link(opts)
		missions = hq.queued_missions ++ [mission]
		Headquarters.run_missions(self())
		{:noreply, %Headquarters{hq | queued_missions: missions}}
	end

	def handle_cast(:run_missions, hq) do
		hq = try do
			if not hq.running do raise "Not running" end

			[mission | queued_missions] = hq.queued_missions

			branch_pid = get_branch(hq)
			Branch.run_mission(branch_pid, mission)

			%Headquarters{hq | queued_missions: queued_missions}
		rescue
			MatchError -> hq
			RuntimeError -> hq
		end
		{:noreply, hq}
	end

	# Get branch with lowerst number of current missions to pass a mission along to
	def get_branch(hq) do
		get_all_branches(hq)
			|> Enum.map(&Branch.get/1)
			|> Enum.min_by(&(length(&1.running_missions) + length(&1.started_missions)))
			|> (fn(b) -> b.pid end).()
	end

	# Get all branches that are currently still alive
	def get_all_branches(hq) do
		hq.branch_pids |> Enum.filter(&(GenServer.whereis(&1)))
	end
end
