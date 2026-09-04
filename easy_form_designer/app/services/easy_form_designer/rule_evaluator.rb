module EasyFormDesigner
  # Decides whether one submitted answer satisfies one EasyQuery operator
  # (PRD M11's conditional sections).
  #
  # Every operator here is offered by EasyQuery.operators_by_filter_type, so
  # a section rule speaks exactly the vocabulary an Easy8 filter speaks. What
  # could NOT be reused is the evaluation: EasyQuery answers "does this match?"
  # by generating SQL, and EasyAutomations does it by asking the database
  # (`rule.query_from_conditions.in_scope?(issue.id)`). A section rule has no
  # saved record to query — the requester is mid-form and the "record" is a
  # hash of answers — so the semantics below are derived, operator by
  # operator, from EasyQuery#sql_for_field.
  #
  # Two deliberate departures from that source, both documented at the point
  # they happen:
  #
  # * the named periods (ld/lw/l2w/m/lm/y) are IMPLEMENTED here, because
  #   EasyQuery offers them without implementing them;
  # * every date window comes from EasyUtils::DateUtils.get_date_range, a
  #   pure function, rather than a second definition of "last month".
  class RuleEvaluator
    # get_date_range is an instance method on an includable module, which is
    # how every other caller reaches it (see TimelogController#index, which
    # dispatches date_period_1/2 exactly the way #composite_period_window
    # below does).
    include EasyUtils::DateUtils

    # EasyQuery offers these for :date_period but has no branch for them in
    # sql_for_field — they fall through to its `else`, register a
    # :query_string error and return "1=0", so selecting one in an ordinary
    # filter silently matches nothing. get_date_range already computes each
    # window, so they are mapped onto it here rather than left dead.
    NAMED_PERIODS = {
      "w" => "current_week",
      "ld" => "yesterday",
      "lw" => "last_week",
      "l2w" => "last_2_weeks",
      "m" => "current_month",
      "lm" => "last_month",
      "y" => "current_year",
    }.freeze

    # Operators whose value is a day count rather than a value to compare
    # against, mapped to the window they describe relative to today. nil is
    # an open end. Mirrors sql_for_field's relative_date_clause calls.
    RELATIVE_DAY_WINDOWS = {
      "t" => ->(_n) { [0, 0] },            # today
      "t-" => ->(n) { [-n, -n] },          # exactly n days ago
      ">t-" => ->(n) { [-n, nil] },        # less than n days ago
      "<t-" => ->(n) { [nil, -n] },        # more than n days ago
      "><t-" => ->(n) { [-n, 0] },         # in the past n days
    }.freeze

    attr_reader :operator, :values, :answer, :filter_type, :today

    # @param operator [String] an EasyQuery operator
    # @param values [Array, Hash] the rule's value(s); a Hash for date_period_*
    # @param answer [Object] what the requester submitted for the rule's field
    # @param filter_type [Symbol, nil]
    # @param today [Date] injectable so specs need not freeze the clock —
    #   the same shape FormField#effective_preset_value already uses
    def initialize(operator:, values:, answer:, filter_type: nil, today: User.current.today)
      @operator = operator.to_s
      @values = values
      @answer = answer
      @filter_type = filter_type
      @today = today
    end

    # @return [Boolean]
    def call
      case operator
      when "*" then present?
      when "!*" then !present?
      when "=" then equals?
      when "!" then not_equals?
      when "&" then includes_all?
      when "~" then text_match? { |a, v| a.include?(v) }
      when "!~" then !text_match? { |a, v| a.include?(v) }
      when "^~" then text_match? { |a, v| a.start_with?(v) }
      when "$~" then text_match? { |a, v| a.end_with?(v) }
      when ">=", "<=", "><" then ordinal?
      when "o" then status_closed?(false)
      when "c" then status_closed?(true)
      when *RELATIVE_DAY_WINDOWS.keys then within?(relative_window)
      when *NAMED_PERIODS.keys then within?(named_period_window)
      when "date_period_1", "date_period_2" then within?(composite_period_window)
      else false # an operator this engine cannot evaluate never matches
      end
    end

    private

    # @return [Array<String>]
    def value_list
      Array(values).map(&:to_s)
    end

    # @return [Array<String>]
    def answer_list
      Array(answer).reject { |v| v.to_s.empty? }.map(&:to_s)
    end

    # `*` in SQL is "IS NOT NULL AND <> ''" — an empty multi-select
    # submitting [""] is therefore absent, not present.
    #
    # @return [Boolean]
    def present?
      answer_list.any?
    end

    # sql_for_field's "=" is an IN, with two type-specific twists worth
    # keeping: a float comparison carries a ±1e-5 tolerance, and a date
    # compares by day rather than by string.
    #
    # @return [Boolean]
    def equals?
      return false if value_list.empty?

      case filter_type
      when :float, :integer then numeric_equals?
      when :date_period then date_answer.present? && value_list.any? { |v| parse_date(v) == date_answer }
      else answer_list.any? { |a| value_list.include?(a) }
      end
    end

    # @return [Boolean]
    def numeric_equals?
      answered = numeric_answer
      return false if answered.nil?

      value_list.any? do |v|
        target = Kernel.Float(v, exception: false)
        target && (answered - target).abs <= 1e-5
      end
    end

    # Deliberately true for a blank answer. sql_for_field's "!" is
    # `NOT IN (...) OR field IS NULL`, so "is not X" holds for a field
    # nobody filled in — which is also the reading that makes a not-equals
    # section usable as an "unless" gate.
    #
    # @return [Boolean]
    def not_equals?
      return true unless present?

      !equals?
    end

    # "&" means every listed value is present, as opposed to "=" matching any
    # one of them. Only offered on :list_optional_and, where the answer is
    # itself multi-valued.
    #
    # @return [Boolean]
    def includes_all?
      return false if value_list.empty?

      (value_list - answer_list).empty?
    end

    # The text operators are case-insensitive LIKEs in SQL (sql_contains and
    # friends), so they are compared downcased here.
    #
    # @return [Boolean]
    def text_match?
      needle = value_list.first.to_s.downcase
      return false if needle.empty?

      answer_list.any? { |a| yield(a.downcase, needle) }
    end

    # @return [Boolean]
    def ordinal?
      return date_ordinal? if filter_type == :date_period

      numeric_ordinal?
    end

    # @return [Boolean]
    def numeric_ordinal?
      answered = numeric_answer
      return false if answered.nil?

      case operator
      when ">=" then bound(0) && answered >= bound(0)
      when "<=" then bound(0) && answered <= bound(0)
      when "><" then bound(0) && bound(1) && answered.between?(bound(0), bound(1))
      else false
      end
    end

    # @return [Boolean]
    def date_ordinal?
      return false if date_answer.blank?

      from = parse_date(value_list[0])
      to = parse_date(value_list[1])

      case operator
      when ">=" then from && date_answer >= from
      when "<=" then from && date_answer <= from
      when "><" then from && to && date_answer.between?(from, to)
      else false
      end
    end

    # @return [Float, nil]
    def bound(index)
      Kernel.Float(value_list[index].to_s, exception: false)
    end

    # @return [Float, nil]
    def numeric_answer
      # "2,5" -> 2.5, the same decimal-comma tolerance SubmissionValidator
      # already applies to a submitted number.
      Kernel.Float(answer.to_s.strip.tr(",", "."), exception: false)
    end

    # @return [Date, nil]
    def date_answer
      @date_answer ||= parse_date(Array(answer).first)
    end

    # @return [Date, nil]
    def parse_date(raw)
      return raw if raw.is_a?(Date)
      return nil if raw.blank?

      Date.parse(raw.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    # o / c are only meaningful on :list_status, where the answer is a status
    # id and the question is whether that status closes the issue.
    #
    # @return [Boolean]
    def status_closed?(closed)
      status = IssueStatus.find_by(id: answer_list.first)
      return false if status.blank?

      status.is_closed? == closed
    end

    # @return [Array(Date, Date)] a [from, to] window, either end nilable
    def relative_window
      days = value_list.first.to_i
      from_offset, to_offset = RELATIVE_DAY_WINDOWS.fetch(operator).call(days)

      [from_offset && today + from_offset, to_offset && today + to_offset]
    end

    # @return [Array(Date, Date)]
    def named_period_window
      range = get_date_range("1", NAMED_PERIODS.fetch(operator))

      [range[:from], range[:to]]
    end

    # date_period_1/2's value is a hash rather than a list — Easy8's own
    # period picker shape — handed straight to the function that already
    # knows what each period means. The two types are different pickers, not
    # variants: "1" resolves a NAMED period and ignores from/to, "2" reads
    # explicit from/to and ignores the period. Same dispatch
    # TimelogController#index makes.
    #
    # @return [Array(Date, Date), nil] nil when the period resolves to no
    #   window at all
    def composite_period_window
      params = (values || {}).to_h.symbolize_keys
      type = operator == "date_period_1" ? "1" : "2"

      range = get_date_range(
        type, params[:period], params[:from], params[:to],
        params[:period_days], params[:period_days2], params[:shift]
      )

      # An unrecognised period, or a free range with neither end filled in,
      # comes back as {from: nil, to: nil} — an unbounded window, which would
      # make the rule match EVERY answer. For a filter that merely widens a
      # result set; for a visibility rule it would silently expose a section
      # to everyone. A rule that resolves to nothing matches nothing, the
      # same stance the unknown-operator branch takes.
      return nil if range[:from].blank? && range[:to].blank?

      [range[:from], range[:to]]
    end

    # @param window [Array(Date, Date), nil]
    # @return [Boolean]
    def within?(window)
      return false if date_answer.blank? || window.nil?

      from, to = window
      from = from.to_date if from.respond_to?(:to_date)
      to = to.to_date if to.respond_to?(:to_date)

      (from.nil? || date_answer >= from) && (to.nil? || date_answer <= to)
    end

  end
end
