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

		test "parses $IN[$LAST] gives nil" do
			assert [type: "IN", index: nil] = Report.parse_variable "$IN[$LAST]"
		end

		test "parses $IN[$LAST] gives last_index" do
			assert [type: "IN", index: 5] = Report.parse_variable("$IN[$LAST]", last_index: 5)
		end

		test "fails to parse nil" do
			assert [error: "Unrecognized pattern "] = Report.parse_variable nil
		end

		test "fails to parse empty string" do
			assert [error: "Unrecognized pattern "] = Report.parse_variable ""
		end

		test "fails to parse arbitrary string" do
			assert [error: "Unrecognized pattern blah"] = Report.parse_variable "blah"
		end

		test "fails to parse invalids in type" do
			assert [error: "Invalid characters"] = Report.parse_variable "$af09"
			assert [error: "Invalid characters"] = Report.parse_variable "$af09[s]"
		end

		test "fails to parse if invalid after $" do
			assert [error: "Unrecognized pattern $09af"] = Report.parse_variable "$09af"
		end

		test "fails to parse with bad brackets" do
			assert [error: "Nonmatching brackets"] = Report.parse_variable "$IN["
			assert [error: "Invalid characters"] = Report.parse_variable "$IN]"
			assert [error: "Nonmatching brackets"] = Report.parse_variable "$IN[s"
		end

		test "fails to parse with no key" do
			assert [error: "Empty/bad key"] = Report.parse_variable "$IN[]"
			assert [error: "Empty/bad key"] = Report.parse_variable "$IN['']"
			assert [error: "Empty/bad key"] = Report.parse_variable "$IN[\"\"]"
			assert [error: "Empty/bad key"] = Report.parse_variable "$IN[\"]"
			assert [error: "Empty/bad key"] = Report.parse_variable "$IN[']"
		end

		test "fails to parse with nonmatching strings" do
			assert [error: "Nonmatching quotes"] = Report.parse_variable "$IN['blah\"]"
			assert [error: "Nonmatching quotes"] = Report.parse_variable "$IN[\"blah']"
			assert [error: "Nonmatching quotes"] = Report.parse_variable "$IN['blah]"
			assert [error: "Nonmatching quotes"] = Report.parse_variable "$IN[blah']"
			assert [error: "Nonmatching quotes"] = Report.parse_variable "$IN[\"blah]"
			assert [error: "Nonmatching quotes"] = Report.parse_variable "$IN[blah\"]"
		end
	end
end
