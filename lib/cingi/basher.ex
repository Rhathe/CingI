defmodule Cingi.Basher do
	alias Cingi.Basher
	use GenServer

	defstruct cmd: "", output: [], running: false, exit_code: Null

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
		{:ok, %Basher{cmd: cmd}}
	end

	def handle_cast({:run}, basher) do
		[cmd | args] = String.split(basher.cmd)
		Porcelain.spawn(cmd, args, out: {:send, self()})
		{:noreply, %Basher{basher | running: true}}
	end

	def handle_call({:get}, _from, basher) do
		{:reply, basher, basher}
	end

	def handle_info({pid, :data, :out, data}, basher) do
		{:noreply, %Basher{basher | output: basher.output ++ [data]}}
	end

	def handle_info({pid, :result, result}, basher) do
		{:noreply, %Basher{basher | exit_code: result.status}}
	end
end
