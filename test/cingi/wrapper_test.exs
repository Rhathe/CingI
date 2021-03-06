defmodule WrapperTest do
	use ExUnit.Case

	test "runs echo" do
		proc = exec(["echo blah"])
		assert "blah\n" = proc.out
		assert 0 = proc.status
	end

	test "gets exit_code" do
		proc = exec(["exit 5"])
		assert "" = proc.out
		assert 5 = proc.status
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

	test "background processes get killed" do
		cmd = "sleep 9"
		path = tmp_file("#/bin/sh\nsleep 9 &\npid=$!\nwait $pid")
		t = _spawn ["bash #{path}"]

		# Wait until sleep actually shows up as a process
		Helper.wait_for_process cmd

		is_running cmd
		Process.exit t.pid, "test"
		isnt_running cmd
		File.rm path
	end


	test "runs ncat, kills ncat process, also deletes tmp_file" do
		cmd = "ncat -l -i 1 8502"
		path = tmp_file("")
		t = _spawn [cmd, path, "true"]
		is_running cmd
		Process.exit t.pid, "test"
		isnt_running cmd
		assert false == File.exists? path
	end

	test "file piping works" do
		path = tmp_file("match1\nignored\nmatch2")
		assert "match1\nmatch2\n" = exec(["grep match", path]).out
		assert File.exists? path
		File.rm path
	end

	test "file piping autoremoves file" do
		path = tmp_file("match1\nignored\nmatch2")
		assert "match1\nmatch2\n" = exec(["grep match", path, "true"]).out
		assert false == File.exists? path
	end

	test "file piping works even without needing it" do
		path = tmp_file("match1\nignored\nmatch2")
		assert "blah\n" = exec(["echo blah", path, "true"]).out
	end

	test "stdin receiving kill kills process" do
		path = tmp_file("one\ntwo\nkill\nfour")
		cmd = "sleep 2"
		proc = exec [cmd], {:path, path}
		assert 137 = proc.status
	end

	test "stdin receiving anything else doesn't kill process" do
		path = tmp_file("one\ntwo\nthree\nfour")
		cmd = "exit 5"
		proc = exec [cmd], {:path, path}
		assert 5 = proc.status
	end

	defp exec(cmds, input \\ nil) do
		Porcelain.exec("./priv/bin/wrapper.sh", cmds, in: input)
	end

	defp _spawn(cmds, input \\ nil) do
		pid = Porcelain.spawn("./priv/bin/wrapper.sh", cmds, in: input)
		Helper.wait_for_process Enum.at(cmds, 0)
		pid
	end

	defp is_running(cmd) do
		assert Helper.get_process_lines(cmd) > 0
	end

	defp isnt_running(cmd) do
		# Might have checked too fast, wait for a quarter of a second before checking again
		# Since process dying from signal may not happen immediately
		n = Helper.get_process_lines(cmd)
		if n > 0 do Process.sleep(250) end
		assert Helper.get_process_lines(cmd) == 0
	end

	defp async_exec(cmds, input \\ nil) do
		pid = Task.async(fn() -> exec(cmds, input) end)
		Helper.wait_for_process Enum.at(cmds, 0)
		pid
	end

	defp tmp_file(content) do
		Temp.track!
		{:ok, fd, path} = Temp.open
		IO.write fd, content
		File.close fd
		path
	end
end
