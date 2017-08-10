defmodule Cingi.Mission do
	alias Cingi.Mission
	use GenServer

	defstruct cmd: Null, submissions: Null, output: [], running: false, exit_code: Null

	# Client API

	def start_link(cmd) do
		GenServer.start_link(__MODULE__, cmd)
	end

	def start_link(submissions) do
		GenServer.start_link(__MODULE__, submissions)
	end

	def run(pid) do
		GenServer.cast(pid, {:run})
	end

	def get(pid) do
		GenServer.call(pid, {:get})
	end

	# Server Callbacks

	def init(cmd) do
		{:ok, %Mission{cmd: cmd}}
	end

	def init(submissions) do
		{:ok, %Mission{submissions: submissions}}
	end

	def handle_cast({:run}, mission) do
		Porcelain.spawn("bash", [ "-c", mission.cmd], out: {:send, self()})
		{:noreply, %Mission{mission | running: true}}
	end

	def handle_call({:get}, _from, mission) do
		{:reply, mission, mission}
	end

	def handle_info({_pid, :data, :out, data}, mission) do
		{:noreply, %Mission{mission | output: mission.output ++ [data]}}
	end

	def handle_info({_pid, :result, result}, mission) do
		{:noreply, %Mission{mission | exit_code: result.status}}
	end
end
