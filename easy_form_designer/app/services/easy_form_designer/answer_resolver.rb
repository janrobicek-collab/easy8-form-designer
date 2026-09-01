module EasyFormDesigner
  # Resolves a raw submitted-answers hash into the hash IssueBuilder actually
  # writes, by overwriting every hidden field's answer with its preset.
  #
  # This is the security control for PRD M8's hidden fields, not a
  # convenience. EasyFormDesignerSubmissionsController#submitted_answers does
  # `params[:answers].permit!.to_h` — a crafted POST can carry
  # `answers[<hidden_field_token>]` for a field that was never rendered on the
  # requester form. Overwriting unconditionally from the form definition makes
  # that param inert regardless of what it contains: the form's own preset is
  # the sole authority for a hidden field's value, exactly as
  # IssueBuilder#build_issue already treats the form's mapping as the sole
  # authority for which attributes may be written at all (see its comment on
  # bypassing safe_attributes).
  #
  # A VISIBLE field's default is deliberately NOT resolved here — only in
  # EasyFormDesignerSubmissionsController#new, which seeds the initial
  # @answers a requester sees. A requester who clears a pre-filled field means
  # it; re-applying the default on this path would silently undo them.
  class AnswerResolver

    attr_reader :form, :answers

    # @param form [EasyFormDesigner::Form]
    # @param answers [Hash] raw answers keyed by field token
    def initialize(form, answers)
      @form = form
      @answers = (answers || {}).stringify_keys
    end

    # @return [Hash{String => Object}]
    def call
      resolved = answers.merge(hidden_field_presets)

      # PRD M11. A field in a section whose rule evaluates false was never
      # asked, so it has no answer — and unlike an M8 hidden field there is
      # no preset to put in its place. Discard whatever reached us for it.
      #
      # Same tamper property as the presets above, different remedy: a value
      # the requester had no legitimate way to supply must not reach the
      # task, whether it arrives from a stale input or a crafted POST.
      #
      # Evaluated against `resolved` rather than the raw answers on purpose —
      # an M8 hidden field is a legitimate rule input, and by this point it
      # is guaranteed to be carrying its preset.
      form.tokens_hidden_by_section(resolved).each { |token| resolved.delete(token) }

      resolved
    end

    private

    # @return [Hash{String => Object}]
    def hidden_field_presets
      form.fields.select(&:hidden?).each_with_object({}) do |field, acc|
        acc[field.token] = field.effective_preset_value
      end
    end

  end
end
