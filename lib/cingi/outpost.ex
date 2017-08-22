defmodule Cingi.Outpost do
	@moduledoc """
	Outposts are processes set up by commanders to connect to headquarters
	and receive missions. Outposts have to set up the environment,
	like a workspace folder, or can be set up inside docker containers
	"""

	alias Cingi.Outpost
	alias Cingi.Mission
	use GenServer

	defstruct [
		name: nil,
		node: nil,
		setup_steps: nil,
		bash_process: nil,
		alternates: nil,
		is_setup: false,
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
		"""
		{:ok, new_pid} = case GenServer.call(pid, {:outpost_on_node, Node.self}) do
			nil -> start_link(original: pid)
			new_pid -> {:ok, new_pid}
		end
		new_pid
		"""
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
		alternate = Agent.get(outpost.alternates, &(&1))
			|> Enum.find(fn(pid) ->
				tmp_outpost = Outpost.get(pid)
				case tmp_outpost.node do
					^node_pid -> tmp_outpost
					_ -> nil
				end
			end)
		{:reply, alternate, outpost}
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

	def handle_cast({:run_bash_process, mission_pid}, outpost) do
		mission = Mission.get(mission_pid)
		script = "./priv/bin/wrapper.sh"
		cmds = [mission.cmd] ++ case mission.input_file do
			nil -> []
			_ -> [mission.input_file]
		end

		# Porcelain's basic driver only takes nil or :out for err
		err = case mission.output_with_stderr do
			true -> :out
			false -> nil
		end

		proc = Porcelain.spawn(script, cmds, out: {:send, self()}, err: err)
		{:noreply, %Outpost{outpost | bash_process: proc}}
	end

	#########
	# INFOS #
	#########

	def handle_info({_pid, :data, :out, data}, outpost) do
		add_to_output(outpost, data: data, type: :out)
	end

	def handle_info({_pid, :data, :err, data}, outpost) do
		add_to_output(outpost, data: data, type: :err)
	end

	def handle_info({_pid, :result, result}, outpost) do
		Mission.send_result(self(), self(), result)
		{:noreply, outpost}
	end

	defp add_to_output(outpost, opts) do
		time = :os.system_time(:millisecond)
		Mission.send(self(), opts ++ [timestamp: time, pid: []])
		{:noreply, outpost}
	end
end
