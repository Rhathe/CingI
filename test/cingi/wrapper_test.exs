defmodule WrapperTest do
	use ExUnit.Case

	test "runs echo" do
		assert "blah\n" = exec(["echo blah"]).out
	end

	test "runs ncat" do
		cmd = "ncat -l -i 1 8500"
		t = async_exec [cmd]
		is_running cmd
		exec ["echo finished | ncat localhost 8500"]
		res = Task.await t
		isnt_running cmd
		assert res.out == "finished\n"
	end

	test "runs ncat, kills ncat process" do
		cmd = "ncat -l -i 1 8501"
		t = _spawn [cmd]
		is_running cmd
		Process.exit t.pid, "test"
		isnt_running cmd
	end

	defp exec(cmds) do
		Porcelain.exec("priv/bin/wrapper.sh", cmds)
	end

	defp _spawn(cmds) do
		Porcelain.spawn("priv/bin/wrapper.sh", cmds)
	end

	defp is_running(cmd) do
		# Only two processes,the bash -c and the actual grep
		assert get_process_lines(cmd) > 2
	end

	defp isnt_running(cmd) do
		# Only two processes,the bash -c and the actual grep
		assert get_process_lines(cmd) <= 2
	end

	defp get_process_lines(cmd) do
		res = Porcelain.exec("bash", ["-c", "ps aux | grep \"#{cmd}\" | wc -l"])
		{n, _} = Integer.parse res.out
		n
	end

	defp async_exec(cmds) do
		Task.async(fn() -> exec(cmds) end)
	end
end
