module EasyFormDesigner
  # Resolves `{{ token }}` placeholders in a form's subject and description
  # templates against a submission payload.
  #
  # An unknown token is an error, never a silent blank — a template that
  # references a field somebody later deleted should fail loudly at submit
  # time rather than quietly producing a half-empty task description.
  class TemplateCompiler
    TOKEN_PATTERN = /\{\{\s*([a-zA-Z0-9_-]+)\s*\}\}/

    class UnknownToken < StandardError; end

    attr_reader :form, :answers

    # @param form [EasyFormDesigner::Form]
    # @param answers [Hash] raw answers keyed by field token
    def initialize(form, answers)
      @form = form
      @answers = (answers || {}).stringify_keys
    end

    # @return [String]
    def subject
      compile(form.subject_template, :subject)
    end

    # @return [String]
    def description
      compile(form.description_template, :description)
    end

    # Tokens referenced by a template that no field on the form provides.
    # Used by the builder to warn before publishing.
    #
    # @param template [String]
    # @return [Array<String>]
    def self.unknown_tokens(form, template)
      known = form.fields.map(&:token)
      template.to_s.scan(TOKEN_PATTERN).flatten.uniq - known
    end

    private

    # @param template [String]
    # @param which [Symbol] which template, for the error message
    # @return [String]
    def compile(template, which)
      return "" if template.blank?

      template.gsub(TOKEN_PATTERN) do
        token = Regexp.last_match(1)
        raise UnknownToken, unknown_token_message(token, which) unless known_token?(token)

        display_value(token)
      end
    end

    # @return [Boolean]
    def known_token?(token)
      form.fields.any? { |f| f.token == token }
    end

    # Renders one answer for inclusion in text. Choice fields store the raw
    # value, so look up the human label where the field can provide one.
    #
    # @return [String]
    def display_value(token)
      field = form.fields.detect { |f| f.token == token }
      raw = answers[token]

      return "" if raw.blank?

      case field&.widget
      when "select"
        label_for_option(field, raw)
      when "date"
        format_date(raw)
      else
        raw.to_s
      end
    end

    # @return [String]
    def label_for_option(field, raw)
      pair = field.options.detect { |(_label, value)| value.to_s == raw.to_s }
      pair ? pair.first.to_s : raw.to_s
    end

    # @return [String]
    def format_date(raw)
      date = raw.is_a?(Date) ? raw : Date.safe_parse(raw.to_s)
      date ? ::I18n.l(date) : raw.to_s
    end

    # @return [String]
    def unknown_token_message(token, which)
      ::I18n.t("easy_form_designer.error.unknown_token",
               token: "{{ #{token} }}",
               template: which)
    end

  end
end
