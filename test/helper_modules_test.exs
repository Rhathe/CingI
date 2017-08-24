defmodule Helper do
	def check_exit_code(pid) do
		mission = Cingi.Mission.get(pid)
		case mission.exit_code do
			nil -> check_exit_code(pid)
			_ -> mission.exit_code
		end
	end
end
