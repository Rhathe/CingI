defmodule Cingi.MissionReport do
	alias Cingi.MissionReport
	alias Cingi.Branch
	use GenServer

	defstruct [
		plan: %{},
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

	def handle_cast({:mission_finished, result}, report) do
		Branch.report_has_finished(report.branch_pid, self(), result)
		{:noreply, report}
	end

	def handle_cast({:data, data}, report) do
		Branch.report_data(report.branch_pid, self(), data)
		{:noreply, report}
	end

	def handle_call(:get, _from, report) do
		{:reply, report, report}
	end

	def parse_variable(v) do
		reg = ~r/\$(?<vartype>[a-zA-Z]+)(?<bracket1>\[?)(?<quote1>['"]?)(?<key>[a-zA-Z_0-9]*)(?<quote2>['"]?)(?<bracket2>\]?)/
		captured = Regex.named_captures(reg, v)
		case captured do
			nil -> [error: "Unrecognized pattern #{v}"]
			%{"vartype" => nil} -> [error: "Unrecognized pattern #{v}"]
			%{
				"vartype" => type,
				"key" => "",
				"bracket1" => "",
				"bracket2" => "",
				"quote1" => "",
				"quote2" => "",
			} -> [type: type]
			%{
				"vartype" => type,
				"key" => key,
				"bracket1" => "[",
				"bracket2" => "]",
			} ->
				case captured do
					%{"key" => ""} -> [error: "Empty/bad key"]
					%{"quote1" => "'", "quote2" => "'"} -> [type: type, key: key]
					%{"quote1" => "\"", "quote2" => "\""} -> [type: type, key: key]
					%{"quote1" => "", "quote2" => ""} ->
						case Integer.parse(key) do
							:error -> [type: type, key: key]
							{i, ""} -> [type: type, index: i]
							{_, _} -> [error: "Invalid index"]
						end
					_ -> [error: "Nonmatching quotes"]
				end
			_ -> [error: "Nonmatching brackets"]
		end
	end
end
