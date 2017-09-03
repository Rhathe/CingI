defmodule CingiMissionReportTest do
	use ExUnit.Case
	alias Cingi.MissionReport, as: Report 
	doctest Report

	describe "MissionReport.parse_variable/1" do
		test "parses $IN" do
			assert [type: "IN"] = Report.parse_variable "$IN"
		end

		test "parses $IN[2]" do
			assert [type: "IN", index: 2] = Report.parse_variable "$IN[2]"
		end

		test "parses $IN['2']" do
			assert [type: "IN", key: "2"] = Report.parse_variable "$IN['2']"
		end

		test "parses $IN[str]" do
			assert [type: "IN", key: "str"] = Report.parse_variable "$IN[str]"
		end

		test "parses $IN['str']" do
			assert [type: "IN", key: "str"]  = Report.parse_variable "$IN['str']"
		end

		test "parses $IN[\"str\"]" do
			assert [type: "IN", key: "str"] = Report.parse_variable "$IN[\"str\"]"
		end
	end
end
