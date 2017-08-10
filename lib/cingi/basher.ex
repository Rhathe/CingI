defmodule Cingi.Basher do
	use GenServer

	defstruct cmd: "", output: [], running: false

	# Client API

	def start_link(cmd) do
		GenServer.start_link(__MODULE__, cmd)
	end

	def run(pid) do
		GenServer.cast(pid, {:run})
	end

	def get(pid) do
		GenServer.call(pid, {:get})
	end

	# Server Callbacks

	def init(cmd) do
		{:ok, %Cingi.Basher{cmd: cmd}}
	end

	def handle_cast({:run}, basher) do
		{:noreply, %Cingi.Basher{
			basher |
			running: true,
			output: basher.output ++ [System.cmd(basher.cmd, [])]
		}}
	end

	def handle_call({:get}, _from, basher) do
		{:reply, basher, basher}
	end
end
