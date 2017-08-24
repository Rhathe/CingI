defmodule Cingi.Outpost do
	@moduledoc """
	Outposts are processes set up by commanders to connect to headquarters
	and receive missions. Outposts have to set up the environment,
	like a workspace folder, or can be set up inside docker containers
	"""

	alias Cingi.Outpost
	alias Cingi.FieldAgent
	alias Cingi.Headquarters
	use GenServer

	defstruct [
		name: nil,
		node: nil,
		headquarters_pid: nil,
		setup_steps: nil,
		bash_process: nil,
		alternates: nil,
		is_setup: false,
		dir: nil,
		envs: nil,
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

	def get_on_same_node(pid) do
		GenServer.call(pid, {:outpost_on_node, Node.self})
	end

	def get_or_create_on_same_node(pid) do
		outpost = get_on_same_node(pid)
		{:ok, new_pid} = case outpost do
			nil -> start_link(original: pid)
			new_pid -> {:ok, new_pid}
		end
		new_pid
	end

	def run_mission(pid, mission) do
		GenServer.cast(pid, {:run_mission, mission})
	end

	def set_hq(pid, hq_pid) do
		GenServer.cast(pid, {:set_hq, hq_pid})
	end

	def mission_has_run(pid, mission_pid) do
		GenServer.cast(pid, {:mission_has_run, mission_pid})
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

	# Server Callbacks

	def init(opts) do
		outpost = case opts[:original] do
			nil -> struct(Outpost, opts)
			original -> Outpost.get original
		end

		outpost = %Outpost{outpost | node: Node.self}
		Outpost.update_alternates(self())
		{:ok, outpost}
	end

	def handle_call(:get, _from, outpost) do
		{:reply, outpost, outpost}
	end

	def handle_call({:outpost_on_node, node_pid}, _from, outpost) do
		self_pid = self()
		alternate = Agent.get(outpost.alternates, &(&1))
			|> Enum.find(fn(pid) ->
				# Already have output, prevent recursion
				tmp_outpost = case pid do
					^self_pid -> outpost
					_ -> Outpost.get(pid)
				end

				case tmp_outpost.node do
					^node_pid -> tmp_outpost
					_ -> nil
				end
			end)
		{:reply, alternate, outpost}
	end

	def handle_call(:get_alternates, _from, outpost) do
		alternates = Agent.get(outpost.alternates, &(&1))
		{:reply, alternates, outpost}
	end

	def handle_cast(:update_alternates, outpost) do
		{:ok, alternates} = case outpost.alternates do
			nil -> Agent.start_link fn -> [] end
			x -> {:ok, x}
		end

		self_pid = self()
		Agent.update(alternates, &(&1 ++ [self_pid]))

		{:noreply, %Outpost{outpost | alternates: alternates}}
	end

	def handle_cast({:run_mission, mission}, outpost) do
		FieldAgent.start_link(mission_pid: mission, outpost_pid: self())
		{:noreply, %Outpost{outpost | missions: outpost.missions ++ [mission]}}
	end

	def handle_cast({:set_hq, hq_pid}, outpost) do
		{:noreply, %Outpost{outpost | headquarters_pid: hq_pid}}
	end

	def handle_cast({:mission_has_run, mission_pid}, outpost) do
		Headquarters.mission_has_run(outpost.headquarters_pid, mission_pid)
		{:noreply, outpost}
	end
end
