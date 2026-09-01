module EasyFormDesigner
  # Resolves `{{ token }}` placeholders in a form's subject and description
  # templates against a submission payload.
  #
  # An unknown token is an error, never a silent blank — a template that
  # references a field somebody later deleted should fail loudly at submit
  # time rather than quietly producing a half-empty task description.
  #
  # The two templates target different formats and are NOT interchangeable:
  #
  # * subject      -> plain text. `issues.subject` is a plain varchar.
  # * description  -> HTML. Easy8 renders task descriptions exclusively through
  #   CKEditor::HTML::Formatter — `Redmine::WikiFormatting.formatter` ignores the
  #   `text_formatting` setting entirely and always returns it. Nothing in that
  #   pipeline converts newlines, so a plain-text description renders as one
  #   collapsed line.
  #
  # That difference drives the escaping split below: an answer substituted into
  # the description must be HTML-escaped (it is requester-supplied) and have its
  # line breaks turned into <br>, while the same answer in the subject must stay
  # exactly as typed.
  class TemplateCompiler
    TOKEN_PATTERN = /\{\{\s*([a-zA-Z0-9_-]+)\s*\}\}/

    # PRD M11 — a conditional section's block, in Mustache's familiar
    # open/close shape:  {{#section_token}} ... {{/section_token}}
    #
    # The optional <p> wrappers are not decoration. The description template
    # is CKEditor HTML, so a marker typed on its own line arrives as
    # "<p>{{#hardware}}</p>" — consuming the wrapper along with the marker is
    # what stops every compiled description growing a trail of empty
    # paragraphs, whether the section is kept or dropped. Both wrappers are
    # optional, so a marker used mid-sentence still matches.
    #
    # A single gsub over TOKEN_PATTERN can't express this: that pattern
    # matches one identifier, and a bounded region needs the backreference to
    # its own opening token to know where it ends.
    SECTION_PATTERN = %r{(?:<p>\s*)?\{\{#\s*([a-zA-Z0-9_-]+)\s*\}\}(?:\s*</p>)?(.*?)(?:<p>\s*)?\{\{/\s*\1\s*\}\}(?:\s*</p>)?}m

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
      compile(form.subject_template, :subject) { |token| display_value(token) }
    end

    # @return [String] an HTML fragment
    def description
      compile(form.description_template, :description) { |token| html_value(token) }
    end

    # Tokens referenced by a template that no field on the form provides.
    # Used by the builder to warn before publishing.
    #
    # @param template [String]
    # @return [Array<String>]
    def self.unknown_tokens(form, template)
      known = form.fields.map(&:token)
      normalized = normalize_entities(template)

      # Section markers ({{#token}} / {{/token}}) are stripped before field
      # tokens are scanned — TOKEN_PATTERN would otherwise never match them
      # anyway (the # and / sit outside its character class), but removing
      # them keeps this method's meaning exact: what it returns is field
      # tokens the form can't provide, and nothing else.
      normalized.scan(TOKEN_PATTERN).flatten.uniq - known
    end

    # Section tokens a template refers to that this form no longer has (PRD
    # M11) — the section-level counterpart of .unknown_tokens, for the same
    # publish-time warning.
    #
    # @param form [EasyFormDesigner::Form]
    # @param template [String]
    # @return [Array<String>]
    def self.unknown_section_tokens(form, template)
      known = form.sections.map(&:token)
      referenced = normalize_entities(template).scan(/\{\{#\s*([a-zA-Z0-9_-]+)\s*\}\}/).flatten.uniq

      referenced - known
    end

    # CKEditor emits a non-breaking space for some typed spaces, so a token the
    # author sees as "{{ name }}" can reach us as "{{&nbsp;name&nbsp;}}" and
    # silently fail TOKEN_PATTERN — a token that looks correct in the editor but
    # never resolves. Normalising both the entity and the literal U+00A0 keeps
    # matching aligned with what the author actually sees.
    #
    # @param template [String, nil]
    # @return [String]
    def self.normalize_entities(template)
      template.to_s.gsub(/&nbsp;|\u00A0/, " ")
    end

    private

    # @param template [String]
    # @param which [Symbol] which template, for the error message
    # @yieldparam token [String]
    # @return [String]
    def compile(template, which)
      return "" if template.blank?

      resolve_sections(self.class.normalize_entities(template)).gsub(TOKEN_PATTERN) do
        token = Regexp.last_match(1)
        raise UnknownToken, unknown_token_message(token, which) unless known_token?(token)

        yield(token)
      end
    end

    # PRD M11. Runs before token substitution: keeps a visible section's
    # block (markers removed, contents intact) and drops a hidden one's
    # entirely, so the flat substitution below never sees tokens belonging to
    # fields nobody was asked.
    #
    # An unknown section token is an error for the same reason an unknown
    # field token is — a template still referring to a section somebody
    # deleted should say so, not quietly emit its contents unconditionally.
    #
    # @param template [String]
    # @return [String]
    def resolve_sections(template)
      template.gsub(SECTION_PATTERN) do
        token = Regexp.last_match(1)
        block = Regexp.last_match(2)
        section = form.sections.detect { |s| s.token == token }

        raise UnknownToken, unknown_section_message(token) if section.blank?

        section.visible?(answers) ? block : ""
      end
    end

    # @return [Boolean]
    def known_token?(token)
      form.fields.any? { |f| f.token == token }
    end

    # An answer rendered for the HTML description: escaped, because it is
    # requester-supplied and lands inside markup, then with its line breaks
    # promoted to <br> so a multi-line answer stays multi-line in the task.
    #
    # @return [String]
    def html_value(token)
      escaped = ERB::Util.html_escape(display_value(token))
      escaped.gsub(/\r\n|\r|\n/, "<br>")
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
      when "select", "radio"
        label_for_option(field, raw)
      when "multi_select"
        Array(raw).filter_map { |v| label_for_option(field, v) }.join(", ")
      when "date"
        format_date(raw)
      when "checkbox"
        checkbox_label(raw)
      when "user"
        user_label(raw)
      when "file"
        # PRD M13. IssueBuilder hands this compiler filenames, never the
        # upload objects themselves (see its #serializable_answers), so a
        # file token reads "photo.png, receipt.pdf" rather than being
        # unusable in a template.
        Array(raw).join(", ")
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
    def checkbox_label(raw)
      raw.to_s == "1" ? ::I18n.t(:general_text_yes_capitalize) : ::I18n.t(:general_text_no_capitalize)
    end

    # A submitted user-lookup answer is a Principal id, not a value already
    # present on the field — Principal, not User, because assigned_to accepts
    # groups too.
    #
    # @return [String]
    def user_label(raw)
      Principal.find_by(id: raw)&.name || raw.to_s
    end

    # @return [String]
    def format_date(raw)
      date = raw.is_a?(Date) ? raw : Date.safe_parse(raw.to_s)
      date ? ::I18n.l(date) : raw.to_s
    end

    # @return [String]
    def unknown_section_message(token)
      ::I18n.t("easy_form_designer.error.unknown_section",
               token: "{{##{token}}}")
    end

    # @return [String]
    def unknown_token_message(token, which)
      ::I18n.t("easy_form_designer.error.unknown_token",
               token: "{{ #{token} }}",
               template: which)
    end

  end
end
