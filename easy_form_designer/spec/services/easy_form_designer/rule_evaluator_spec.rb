require "easy_extensions/spec_helper"

# PRD M11. Every operator here comes from EasyQuery.operators_by_filter_type,
# and every semantic below is derived from EasyQuery#sql_for_field — this
# spec is where the two are held to agree, since nothing enforces it at
# runtime.
RSpec.describe EasyFormDesigner::RuleEvaluator, logged: :admin do
  def evaluate(operator, values, answer, filter_type: nil, today: Date.new(2026, 9, 1))
    described_class.new(
      operator: operator, values: values, answer: answer,
      filter_type: filter_type, today: today
    ).call
  end

  describe "set operators" do
    it { expect(evaluate("=", ["a"], "a")).to be(true) }
    it { expect(evaluate("=", ["a"], "b")).to be(false) }
    it { expect(evaluate("=", %w[a b], "b")).to be(true) }
    it { expect(evaluate("=", [], "a")).to be(false) }

    # sql_for_field's "!" is `NOT IN (...) OR field IS NULL`, so "is not X"
    # holds for a field nobody answered. That reading is also what makes a
    # not-equals section usable as an "unless" gate.
    it "treats a blank answer as satisfying 'is not'" do
      expect(evaluate("!", ["a"], "")).to be(true)
    end

    it { expect(evaluate("!", ["a"], "a")).to be(false) }
    it { expect(evaluate("!", ["a"], "b")).to be(true) }

    it { expect(evaluate("*", [], "x")).to be(true) }
    it { expect(evaluate("*", [], "")).to be(false) }
    it { expect(evaluate("!*", [], "")).to be(true) }
    it { expect(evaluate("!*", [], "x")).to be(false) }

    # An empty multi-select posts [""], which is absent rather than present —
    # the same distinction SubmissionValidator's blank? check already makes.
    it "treats an empty multi-select selection as absent" do
      expect(evaluate("*", [], [""])).to be(false)
    end

    # "&" is all-of, as against "=" being any-of. Only offered on
    # :list_optional_and, where the answer is itself multi-valued.
    it { expect(evaluate("&", %w[a b], %w[a b c])).to be(true) }
    it { expect(evaluate("&", %w[a b], %w[a])).to be(false) }
  end

  describe "text operators" do
    it { expect(evaluate("~", ["ell"], "HELLO")).to be(true) }
    it { expect(evaluate("~", ["zz"], "HELLO")).to be(false) }
    it { expect(evaluate("!~", ["zz"], "HELLO")).to be(true) }
    it { expect(evaluate("^~", ["he"], "Hello")).to be(true) }
    it { expect(evaluate("^~", ["lo"], "Hello")).to be(false) }
    it { expect(evaluate("$~", ["LO"], "Hello")).to be(true) }

    it "matches case-insensitively, as the SQL LIKE does" do
      expect(evaluate("~", ["HeLLo"], "hello world")).to be(true)
    end
  end

  describe "ordinal operators" do
    it { expect(evaluate(">=", ["5"], "7", filter_type: :float)).to be(true) }
    it { expect(evaluate(">=", ["5"], "3", filter_type: :float)).to be(false) }
    it { expect(evaluate("<=", ["5"], "3", filter_type: :float)).to be(true) }
    it { expect(evaluate("><", %w[1 10], "5", filter_type: :float)).to be(true) }
    it { expect(evaluate("><", %w[1 10], "50", filter_type: :float)).to be(false) }

    it "is false when the answer isn't a number at all" do
      expect(evaluate(">=", ["5"], "abc", filter_type: :float)).to be(false)
    end

    # The ±1e-5 tolerance is sql_for_field's own, not an invention here.
    it "compares floats with the tolerance the SQL uses" do
      expect(evaluate("=", ["2.5"], "2.5000001", filter_type: :float)).to be(true)
    end

    # Same decimal-comma tolerance SubmissionValidator already applies.
    it "accepts a decimal comma" do
      expect(evaluate("=", ["2.5"], "2,5", filter_type: :float)).to be(true)
    end
  end

  describe "date comparison" do
    let(:today) { Date.new(2026, 9, 1) }

    it { expect(evaluate("=", ["2026-09-01"], "2026-09-01", filter_type: :date_period)).to be(true) }
    it { expect(evaluate("=", ["2026-09-01"], "2026-09-02", filter_type: :date_period)).to be(false) }
    it { expect(evaluate(">=", ["2026-09-01"], "2026-09-05", filter_type: :date_period)).to be(true) }
    it { expect(evaluate("<=", ["2026-09-01"], "2026-08-01", filter_type: :date_period)).to be(true) }

    it "handles a between range" do
      expect(evaluate("><", %w[2026-08-01 2026-09-30], "2026-09-15", filter_type: :date_period)).to be(true)
    end

    it "is false for an unparsable date" do
      expect(evaluate("=", ["2026-09-01"], "not a date", filter_type: :date_period)).to be(false)
    end
  end

  # Windows relative to today, mirroring EasyQuery#relative_date_clause.
  describe "relative date operators" do
    let(:today) { Date.new(2026, 9, 1) }

    it "t matches today only" do
      expect(evaluate("t", [], today.to_s, filter_type: :date_period, today: today)).to be(true)
      expect(evaluate("t", [], (today - 1).to_s, filter_type: :date_period, today: today)).to be(false)
    end

    it "t- matches exactly n days ago" do
      expect(evaluate("t-", ["3"], (today - 3).to_s, filter_type: :date_period, today: today)).to be(true)
      expect(evaluate("t-", ["3"], (today - 4).to_s, filter_type: :date_period, today: today)).to be(false)
    end

    it ">t- is less than n days ago" do
      expect(evaluate(">t-", ["7"], (today - 2).to_s, filter_type: :date_period, today: today)).to be(true)
      expect(evaluate(">t-", ["7"], (today - 30).to_s, filter_type: :date_period, today: today)).to be(false)
    end

    it "<t- is more than n days ago" do
      expect(evaluate("<t-", ["7"], (today - 30).to_s, filter_type: :date_period, today: today)).to be(true)
      expect(evaluate("<t-", ["7"], (today - 2).to_s, filter_type: :date_period, today: today)).to be(false)
    end

    it "><t- is within the past n days" do
      expect(evaluate("><t-", ["7"], (today - 3).to_s, filter_type: :date_period, today: today)).to be(true)
      expect(evaluate("><t-", ["7"], (today + 3).to_s, filter_type: :date_period, today: today)).to be(false)
    end
  end

  # These six are offered by EasyQuery.operators_by_filter_type[:date_period]
  # but have NO branch in sql_for_field — in an ordinary Easy8 filter they
  # fall through to its `else` and match nothing. They are implemented here
  # via get_date_range, which already computes each window, so the builder
  # has no dead options.
  describe "named periods EasyQuery leaves unimplemented" do
    it "ld is yesterday" do
      expect(evaluate("ld", [], (Date.today - 1).to_s, filter_type: :date_period)).to be(true)
      expect(evaluate("ld", [], Date.today.to_s, filter_type: :date_period)).to be(false)
    end

    it "m is the current month" do
      expect(evaluate("m", [], Date.today.to_s, filter_type: :date_period)).to be(true)
      expect(evaluate("m", [], (Date.today << 2).to_s, filter_type: :date_period)).to be(false)
    end

    it "lm is last month" do
      expect(evaluate("lm", [], (Date.today << 1).to_s, filter_type: :date_period)).to be(true)
    end

    it "y is the current year" do
      expect(evaluate("y", [], Date.today.to_s, filter_type: :date_period)).to be(true)
      expect(evaluate("y", [], Date.new(Date.today.year - 1, 6, 1).to_s, filter_type: :date_period)).to be(false)
    end

    it "w is the current week" do
      expect(evaluate("w", [], Date.today.to_s, filter_type: :date_period)).to be(true)
    end
  end

  # The composite period operators take Easy8's own period hash rather than a
  # list, and hand it straight to get_date_range — the same dispatch
  # TimelogController#index makes. The two are different pickers, not
  # variants: "1" resolves a NAMED period and ignores from/to, "2" reads
  # explicit from/to and ignores the period.
  describe "composite period operators" do
    it "date_period_1 resolves a named period" do
      expect(evaluate("date_period_1", { "period" => "today" }, Date.today.to_s,
                      filter_type: :date_period)).to be(true)
    end

    it "date_period_1 resolves a rolling window" do
      expect(evaluate("date_period_1", { "period" => "30_days" }, (Date.today - 5).to_s,
                      filter_type: :date_period)).to be(true)
      expect(evaluate("date_period_1", { "period" => "30_days" }, (Date.today - 60).to_s,
                      filter_type: :date_period)).to be(false)
    end

    it "date_period_1 supports the n-days periods" do
      expect(evaluate("date_period_1", { "period" => "in_past_n_days", "period_days" => 7 },
                      (Date.today - 3).to_s, filter_type: :date_period)).to be(true)
    end

    it "date_period_2 takes an explicit from/to" do
      expect(evaluate("date_period_2", { "from" => "2026-01-01", "to" => "2026-12-31" },
                      "2026-06-15", filter_type: :date_period)).to be(true)
      expect(evaluate("date_period_2", { "from" => "2026-01-01", "to" => "2026-12-31" },
                      "2025-06-15", filter_type: :date_period)).to be(false)
    end

    it "date_period_2 accepts a one-sided range" do
      expect(evaluate("date_period_2", { "from" => "2026-01-01" }, "2026-06-15",
                      filter_type: :date_period)).to be(true)
      expect(evaluate("date_period_2", { "from" => "2026-01-01" }, "2025-06-15",
                      filter_type: :date_period)).to be(false)
    end

    # get_date_range returns {from: nil, to: nil} for an unrecognised period
    # or an empty free range — an unbounded window. For a query filter that
    # merely widens the result set; for a visibility rule it would expose the
    # section to everyone, so it must match nothing instead.
    it "matches nothing when the period resolves to no window at all", :aggregate_failures do
      expect(evaluate("date_period_2", {}, Date.today.to_s, filter_type: :date_period)).to be(false)
      expect(evaluate("date_period_1", { "period" => "" }, Date.today.to_s,
                      filter_type: :date_period)).to be(false)
      expect(evaluate("date_period_1", { "period" => "nonsense" }, Date.today.to_s,
                      filter_type: :date_period)).to be(false)
    end
  end

  describe "status operators" do
    let_it_be(:open_status) { create(:issue_status, is_closed: false) }
    let_it_be(:closed_status) { create(:issue_status, is_closed: true) }

    it { expect(evaluate("o", [], open_status.id.to_s)).to be(true) }
    it { expect(evaluate("o", [], closed_status.id.to_s)).to be(false) }
    it { expect(evaluate("c", [], closed_status.id.to_s)).to be(true) }
    it { expect(evaluate("c", [], open_status.id.to_s)).to be(false) }

    it "is false when the answer names no status at all" do
      expect(evaluate("o", [], "")).to be(false)
    end
  end

  # An operator this engine can't evaluate must never silently match — that
  # would show a section to everyone rather than to the intended few.
  it "returns false for an operator it does not implement" do
    expect(evaluate(">dd", [], "anything")).to be(false)
  end
end
