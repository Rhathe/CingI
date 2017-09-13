defmodule Cingi.MissionReport do
	alias Cingi.MissionReport
	alias Cingi.Branch
	alias Cingi.Outpost
	use GenServer

	defstruct [
		plan: %{},
		branch_pid: nil,
		prev_mission_pid: nil,
		outpost_pid: nil, # Used when submitted by an outpost trying to setup
		missions: []
	]

	# Client API

	def start_link(opts) do
		GenServer.start_link(__MODULE__, opts)
	end

	def initialized_mission(pid, mission_pid) do
		GenServer.cast(pid, {:mission_has_init, mission_pid})
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
			opts[:map] -> opts[:map] |> start_missions(opts)
			opts[:string] -> opts[:string] |> get_map_from_yaml(&YamlElixir.read_from_string/1) |> start_missions(opts)
			opts[:file] -> opts[:file] |> get_map_from_yaml(&YamlElixir.read_from_file/1) |> start_missions(opts)
		end
		{:ok, report}
	end

	def start_missions(map, opts) do
		opts = opts |> Keyword.delete(:string) |> Keyword.delete(:file) |> Keyword.delete(:map)
		MissionReport.init_mission(self(), [mission_plan: map, prev_mission_pid: opts[:prev_mission_pid]])
		struct(MissionReport, Keyword.put(opts, :plan, map))
	end

	def handle_cast({:init_mission, opts}, report) do
		opts = opts ++ [report_pid: self(), outpost_pid: report.outpost_pid]
		Branch.init_mission(report.branch_pid, opts)
		{:noreply, report}
	end

	def handle_cast({:mission_has_init, mission_pid}, report) do
		missions = report.missions ++ [mission_pid]
		{:noreply, %MissionReport{report | missions: missions}}
	end

	def handle_cast({:mission_finished, mission_pid}, report) do
		Branch.report_has_finished(report.branch_pid, self(), mission_pid)
		if report.outpost_pid do
			Outpost.report_has_finished(report.outpost_pid, self(), mission_pid)
		end
		{:noreply, report}
	end

	def handle_cast({:data, data}, report) do
		Branch.report_data(report.branch_pid, self(), data)
		{:noreply, report}
	end

	def handle_call(:get, _from, report) do
		{:reply, report, report}
	end

	def get_map_from_yaml(yaml, parser) do
		try do
			parser.(yaml)
		catch
			err ->
				IO.puts :stderr, "Error parsing yaml: #{yaml}"
				IO.puts :stderr, inspect(err)
		end
	end

	def parse_variable(v, opts \\ []) do
		v = v || ""
		reg = ~r/\$(?<vartype>[a-zA-Z]+)(?<invalids>[^\[]*)(?<bracket1>\[?)(?<quote1>['"]?)(?<key>\$?[a-zA-Z_0-9]*)(?<quote2>['"]?)(?<bracket2>\]?)/
		captured = Regex.named_captures(reg, v)
		case captured do
			nil -> [error: "Unrecognized pattern #{v}"]
			%{"vartype" => nil} -> [error: "Unrecognized pattern #{v}"]
			%{
				"vartype" => type,
				"key" => "",
				"invalids" => "",
				"bracket1" => "",
				"bracket2" => "",
				"quote1" => "",
				"quote2" => "",
			} -> [type: type]
			%{
				"vartype" => type,
				"key" => key,
				"invalids" => "",
				"bracket1" => "[",
				"bracket2" => "]",
			} ->
				case captured do
					%{"key" => ""} -> [error: "Empty/bad key"]
					%{"quote1" => "'", "quote2" => "'"} -> [type: type, key: key]
					%{"quote1" => "\"", "quote2" => "\""} -> [type: type, key: key]
					%{"quote1" => "", "quote2" => ""} ->
						case {key, Integer.parse(key)} do
							{"$LAST", _} -> [type: type, index: opts[:last_index]]
							{_, :error} -> [type: type, key: key]
							{_, {i, ""}} -> [type: type, index: i]
							{_, {_, _}} -> [error: "Invalid index"]
						end
					_ -> [error: "Nonmatching quotes"]
				end
			%{"invalids" => ""} -> [error: "Nonmatching brackets"]
			_ -> [error: "Invalid characters"]
		end
	end
end
