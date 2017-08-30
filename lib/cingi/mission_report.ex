defmodule Cingi.MissionReport do
	alias Cingi.MissionReport
	alias Cingi.Mission
	alias Cingi.Branch
	use GenServer

	defstruct [
		plan: %{},
		cli_pid: nil,
		branch_pid: nil,
		missions: []
	]

	# Client API

	def start_link(opts) do
		GenServer.start_link(__MODULE__, opts)
	end

	def initialized_mission(pid, mission_pid) do
		GenServer.cast(pid, {:mission_init, mission_pid})
	end

	def finished_mission(pid, mission_pid) do
		GenServer.cast(pid, {:mission_finished, mission_pid})
	end

	def init_mission(pid, opts) do
		GenServer.cast(pid, {:init_mission, opts})
	end

	def send_data(pid, data) do
		GenServer.cast(pid, {:data, data})
	end

	def get(pid) do
		GenServer.call(pid, :get)
	end

	# Server Callbacks

	def init(opts) do
		report = cond do
			opts[:string] -> start_missions(YamlElixir.read_from_string(opts[:string]), opts)
			opts[:file] -> start_missions(YamlElixir.read_from_file(opts[:file]), opts)
		end
		{:ok, report}
	end

	def start_missions(map, opts) do
		opts = opts |> Keyword.delete(:string) |> Keyword.delete(:file)
		name = Map.get(map, "name", "MAIN")
		map = Map.put(map, "name", name)
		MissionReport.init_mission(self(), [decoded_yaml: map])
		struct(MissionReport, Keyword.put(opts, :plan, map))
	end

	def handle_cast({:init_mission, opts}, report) do
		opts = opts ++ [report_pid: self()]
		Branch.init_mission(report.branch_pid, opts)
		{:noreply, report}
	end

	def handle_cast({:mission_init, mission_pid}, report) do
		missions = report.missions ++ [mission_pid]
		{:noreply, %MissionReport{report | missions: missions}}
	end

	def handle_cast({:mission_finished, _}, report) do
		if report.cli_pid do
			send report.cli_pid, {:report, self()}
		end
		{:noreply, report}
	end

	def handle_cast({:data, data}, report) do
		if (report.cli_pid) do
			case data[:pid] do
				[] -> [data[:data]]
				[_|_] ->
					keys = data[:pid] |> Enum.map(&(Mission.get(&1).key)) |> Enum.join("|")
					split = String.split(data[:data], "\n")
					split |> Enum.map(&("[#{keys}]    #{&1}"))
			end |> Enum.map(&(IO.puts &1))
		end

		{:noreply, report}
	end

	def handle_call(:get, _from, report) do
		{:reply, report, report}
	end
end
