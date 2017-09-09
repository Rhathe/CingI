defmodule Cingi.Mission do
	alias Cingi.Mission
	alias Cingi.MissionReport
	alias Cingi.FieldAgent
	use GenServer

	defstruct [
		pid: nil,
		key: "",
		index: nil,
		name: nil,

		report_pid: nil,
		prev_mission_pid: nil,
		supermission_pid: nil,
		submission_holds: [],
		field_agent_pid: nil,

		mission_plan_templates: %{},
		mission_plan: nil,
		original_mission_plan: nil,

		cmd: nil,
		submissions: nil,
		submissions_num: nil,

		input_file: "$IN", # Get input by default
		output_filter: [], # Don't filter anything by default
		output: [],

		output_with_stderr: false, # Stderr will be printed to ouput if false, redirected to output if true
		fail_fast: true, # fail_fast true by default, but if parallel will default to false
		skipped: false,

		running: false,
		finished: false,

		when: nil,
		exit_code: nil,
	]

	# Client API

	def start_link(opts) do
		GenServer.start_link(__MODULE__, opts)
	end

	def send(pid, data) do
		GenServer.cast(pid, {:data_and_metadata, data})
	end

	def initialized_submission(pid, submission_pid) do
		GenServer.cast(pid, {:init_submission, submission_pid})
	end

	def send_result(pid, result, finished_mpid) do
		GenServer.cast(pid, {:finished, result, finished_mpid})
	end

	def run_submissions(pid, prev_pid \\ nil) do
		GenServer.cast(pid, {:run_submissions, prev_pid})
	end

	def construct_from_plan(pid, new_plan) do
		GenServer.cast(pid, {:construct_from_plan, new_plan})
	end

	def stop(pid) do
		GenServer.cast(pid, :stop)
	end

	def pause(pid) do
		GenServer.call(pid, :pause)
	end

	def resume(pid) do
		GenServer.call(pid, :resume)
	end

	def get(pid) do
		GenServer.call(pid, :get)
	end

	def get_outpost(pid) do
		GenServer.call(pid, :get_outpost)
	end

	def get_outpost_plan(pid) do
		GenServer.call(pid, :get_outpost_plan)
	end

	def get_mission_plan_template(pid, key) do
		case {pid, key} do
			{nil, _} -> %{}
			{_, nil} -> %{}
			_ -> GenServer.call(pid, {:get_mission_plan_template, key})
		end
	end

	def set_as_running(pid, field_agent_pid) do
		GenServer.call(pid, {:set_as_running, field_agent_pid})
	end

	def get_output(pid, selector \\ nil) do
		case pid do
			nil -> []
			_ -> GenServer.call(pid, {:get_output, selector})
		end
	end

	# Server Callbacks

	def init(opts) do
		opts = opts ++ [
			pid: self(),
			original_mission_plan: opts[:mission_plan],
		]
		mission = struct(Mission, opts)
		{:ok, mission}
	end

	#########
	# CASTS #
	#########

	def handle_cast({:construct_from_plan, new_plan}, mission) do
		mission = Map.merge(mission, new_plan)
		mission = %Mission{mission |
			submissions_num: case mission.submissions do
				%{} -> length(Map.keys(mission.submissions))
				[_|_] -> length(mission.submissions)
				_ -> 0
			end,
			key: case mission.key do
				"" -> construct_key(mission.name || mission.cmd)
				_ -> mission.key
			end,
			skipped: determine_skipped_status(mission),
		}

		# Reconstruct mission after getting submissions_num
		mission = %Mission{mission |
			output_filter: get_output_filter(
				mission.output_filter,
				last_index: mission.submissions_num - 1
			),
		}

		mission = case mission do
			%{cmd: nil, submissions: nil} ->
				IO.puts :stderr, "Must have cmd or submissions, got #{inspect(mission.mission_plan)}"
				%Mission{mission | cmd: "exit 199"}
			_ -> mission
		end

		mission_pid = mission.supermission_pid
		if mission_pid do Mission.initialized_submission(mission_pid, self()) end
		MissionReport.initialized_mission(mission.report_pid, self())

		{:noreply, mission}
	end

	def handle_cast({:finished, result, finished_mpid}, mission) do
		# Indicate that finished_mpid has finished
		submission_holds = update_in_list(
			mission.submission_holds,
			fn({h, _}) -> h.pid == finished_mpid end,
			fn(h) -> Map.replace(h, :finished, true) end
		)

		# Submission might not have initialized yet, filter out nil
		sub_pids = submission_holds
			|> Enum.map(&(&1.pid))
			|> Enum.filter(&(&1))

		exit_codes = sub_pids
			|> Enum.map(&(Mission.get(&1)))
			|> Enum.filter(&(&1.finished))
			|> Enum.map(&(&1.exit_code))

		# Check if a failure should trigger a fail_fast behavior
		check =
			self() == finished_mpid or (
				length(exit_codes) > 0
				and Enum.max(exit_codes) > 0
				and mission.fail_fast
			)

		# If mission already finished, do nothing
		if check do Enum.map(sub_pids, &Mission.stop/1) end

		# Boolean to check if more submissions need to run
		more_submissions? = not mission.skipped
			and not check
			and (length(exit_codes) != mission.submissions_num)

		exit_code = cond do
			length(exit_codes) == 0 -> result.status
			more_submissions? -> nil

			# Get last exit code if missions are sequential
			is_list(mission.submissions) ->
				[head | _] = Enum.reverse(exit_codes)
				head

			# Get largest exit code if parallel
			true ->
				exit_codes
					|> Enum.filter(&(&1))
					|> (fn(x) ->
						case x do
							[] -> nil
							x -> Enum.max(x)
						end
					end).()
		end

		# If submissions have not finished then more should be queued up
		# Else tell the field agent that the mission is finished
		{finished, running} = cond do
			mission.finished ->
				{true, false}
			more_submissions? ->
				Mission.run_submissions(self(), finished_mpid)
				{false, true}
			true ->
				FieldAgent.mission_has_finished(mission.field_agent_pid, result)
				{true, false}
		end

		{:noreply, %Mission{mission |
			exit_code: exit_code,
			finished: finished,
			running: running,
			submission_holds: submission_holds,
		}}
	end

	def handle_cast({:data_and_metadata, data}, mission) do
		submission_pid = Enum.at(data[:pid], 0)
		submission_index = Enum.find_index(mission.submission_holds, &(&1.pid == submission_pid))

		splits = Enum.split_with(mission.output_filter, &(&1[:key]))

		new_data = case splits do
			# All empty lists, no filter
			{[], []} -> [data]
			{keys, indices} ->
				indices = Enum.map(indices, &(&1[:index]))
				keys = Enum.map(keys, &(&1[:key]))

				cond do
					is_nil(submission_pid) -> []
					submission_index in indices -> [data]
					length(keys) == 0 -> []
					Mission.get(submission_pid).key in keys -> [data]
					true -> []
				end
		end

		case new_data do
			[] -> :ok
			_ ->
				pids = [self()] ++ data[:pid]
				data_without_pid = Keyword.delete(data, :pid)
				send_data = data_without_pid ++ [pid: pids]

				if mission.supermission_pid do
					Mission.send(mission.supermission_pid, send_data)
				else
					MissionReport.send_data(mission.report_pid, send_data)
				end
		end

		{:noreply, %Mission{mission | output: mission.output ++ new_data}}
	end

	def handle_cast({:init_submission, pid}, mission) do
		sh = update_in_list(
			mission.submission_holds,
			fn({h, _}) -> is_nil(h.pid) end,
			fn(h) -> Map.replace(h, :pid, pid) end
		)

		# Send stop message
		if (mission.finished) do Mission.stop(pid) end
		{:noreply, %Mission{mission | submission_holds: sh}}
	end

	def handle_cast({:run_submissions, prev_pid}, mission) do
		{running, remaining} = case mission.submissions do
			%{} -> {Enum.map(mission.submissions, fn({k, v}) -> [mission_plan: v, key: k] end), %{}}
			[{submission, index}|b] -> {[[mission_plan: submission, index: index]], b}
			[] -> {[], []}
			nil -> {[], nil}
		end

		sh = mission.submission_holds
		sh = sh ++ for submission <- running do
			opts = submission ++ [supermission_pid: self(), prev_mission_pid: prev_pid]
			MissionReport.init_mission(mission.report_pid, opts)
			%{pid: nil, finished: false}
		end

		{:noreply, %Mission{mission | submissions: remaining, submission_holds: sh}}
	end

	def handle_cast(:stop, mission) do
		cond do
			mission.cmd -> FieldAgent.stop(mission.field_agent_pid)
			mission.submissions ->
				mission.submission_holds
					|> Enum.map(&(&1.pid))
					|> Enum.filter(&(&1))
					|> Enum.map(&Mission.stop/1)
		end
		{:noreply, %Mission{mission | fail_fast: true}}
	end

	#########
	# CALLS #
	#########

	def handle_call({:set_as_running, field_agent}, _from, mission) do
		mission = %Mission{mission | running: true, field_agent_pid: field_agent}
		{:reply, mission, mission}
	end

	def handle_call(:pause, _from, mission) do
		mission = %Mission{mission | running: false}
		{:reply, mission, mission}
	end

	def handle_call(:resume, _from, mission) do
		mission = %Mission{mission | running: true}
		{:reply, mission, mission}
	end

	def handle_call(:get, _from, mission) do
		{:reply, mission, mission}
	end

	def handle_call({:get_output, selector}, _from, mission) do
		output =
			try do
				case selector do
					# Empty slector means just get normal output
					nil -> mission.output

					# String sleector means get submission output with same key
					"" <> output_key ->
						mission.submission_holds
							|> Enum.map(&(&1.pid))
							|> Enum.map(&Mission.get/1)
							|> Enum.find(&(&1.key == output_key))
							|> (fn(s) -> s.output end).()

					# Default/integer selector means get submissions at index
					index ->
						mission.submission_holds
							|> Enum.at(index)
							|> (fn(s) -> Mission.get(s.pid).output end).()
				end
			rescue
				_ -> []
			end |> Enum.map(&(&1[:data]))

		{:reply, output, mission}
	end

	def handle_call(:get_outpost, _from, mission) do
		field_agent = FieldAgent.get(mission.field_agent_pid)
		{:reply, field_agent.outpost_pid, mission}
	end

	def handle_call(:get_outpost_plan, _from, mission) do
		# FIXME: Currently does not work correctly on edge case
		# where mission extends another mission
		# and the mission_template defines an outpost plan
		plan = case mission.mission_plan do
			%{"outpost" => plan} -> plan
			_ -> nil
		end
		{:reply, plan, mission}
	end

	def handle_call({:get_mission_plan_template, key}, _from, mission) do
		templates = mission.mission_plan_templates || %{}
		template = case Map.has_key?(templates, key) do
			true -> templates[key]
			false -> Mission.get_mission_plan_template(mission.supermission_pid, key)
		end
		{:reply, template, mission}
	end

	##################
	# MISC FUNCTIONS #
	##################

	defp update_in_list(list, filter, update) do
		case list do
			[] -> []
			_ ->
				found = list
					|> Enum.with_index
					|> Enum.find(filter)

				case found do
					nil -> list
					{el, index} ->
						el = update.(el)
						List.replace_at(list, index, el)
				end
		end
	end

	def determine_skipped_status(mission) do
		w = mission.when

		case {w, mission.prev_mission_pid} do
			{nil, _} -> false
			{_, nil} -> true
			{w, prev_pid} ->
				prev = Mission.get(prev_pid)
				output = prev.output
					|> Enum.map(&(&1[:data]))
					|> Enum.join("")
					|> String.trim()

				cond do
					prev.exit_code in Map.get(w, "exit_codes", []) -> false
					output in Map.get(w, "outputs", []) -> false
					prev.exit_code == 0 and Map.get(w, "success") == true -> false
					prev.exit_code > 0 and Map.get(w, "success") == false -> false
					true -> true
				end
		end
	end

	def get_output_filter(output_plan, opts) do
		case output_plan do
			nil -> []
			[] -> []
			[_|_] -> output_plan
			x -> [x]
		end
			|> Enum.map(fn(x) ->
				case MissionReport.parse_variable(x, opts) do
					[error: _] -> nil
					y -> y
				end
			end)
			|> Enum.filter(&(&1))
	end

	defp construct_key(name) do
		name = name || ""
		name = String.replace(name, ~r/ /, "_")
		name = String.replace(name, ~r/[^_a-zA-Z0-9]/, "")
		String.downcase(name)
	end
end
