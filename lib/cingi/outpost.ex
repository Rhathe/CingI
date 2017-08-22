defmodule Cingi.Outpost do
	@moduledoc """
	Outposts are processes set up by commanders to connect to headquarters
	and receive missions. Outposts have to set up the environment,
	like a workspace folder, or can be set up inside docker containers
	"""

	alias Cingi.Outpost
	use GenServer

	defstruct [
		setup_steps: nil,
		slave: nil,
	]

	# Client API

	def start_link(opts) do
		GenServer.start_link(__MODULE__, opts)
	end

	def get(pid) do
		GenServer.call(pid, :get)
	end

	def test do
		{:ok, pid} = start_link(name: "sfafasf")
		outpost = get(pid)
		call outpost.slave, :shell_default, :cd , ["/tmp"]
		#call outpost.slave, Outpost, :blah, []
		#call outpost.slave, System, :cmd, ["pwd", []]
	end

	def blah do
		result = Porcelain.exec("ls", [])
		IO.inspect result.out
	end

	# Server Callbacks

	def init(opts) do
		host = get_host opts[:host]
		allow_boot host
		{:ok, slave} = :slave.start_link(host, to_charlist(opts[:name]), slave_args(opts[:args]))
		load_paths slave
		{:ok, %Outpost{slave: slave}}
	end

	defp allow_boot(host) do
		:erl_boot_server.add_slave host
	end

	defp load_paths(slave) do
		:rpc.block_call(slave, :code, :add_paths, [:code.get_path])
	end

	defp slave_args(_args) do
		cookie = case :erlang.get_cookie do
			:nocookie -> ""
			_ -> "-setcookie #{:erlang.get_cookie}"
		end
		"#{cookie} -pa /home/ramon/dream_challenge" |> to_charlist
	end

	defp get_host(host) do
		host = case host do
			nil ->
				node()
				|> to_string
				|> String.split("@")
				|> Enum.at(1)
			_ -> host
		end
		to_charlist host
	end

	def call(slave, module, method, args) do
		:rpc.block_call(slave, module, method, args)
	end

	def cast(slave, module, method, args) do
		:rpc.call(slave, module, method, args)
	end

	def handle_call(:get, _from, outpost) do
		{:reply, outpost, outpost}
	end
end
