require "easy_extensions/spec_helper"

# PRD M11 — conditional sections. The rule is what makes this more than
# cosmetic grouping: one field's ANSWER decides whether this section's fields
# are asked at all.
RSpec.describe EasyFormDesigner::FormSection, logged: :admin do
  let_it_be(:tracker, refind: true) { create(:tracker) }
  let_it_be(:project, refind: true) { create(:project, trackers: [tracker]) }
  let_it_be(:priority) { create(:issue_priority) }
  let_it_be(:other_priority) { create(:issue_priority) }

  let(:form) { create(:easy_form_designer_form, project: project, tracker: tracker) }

  # A dropdown on the same form, the natural thing for a rule to read.
  let(:trigger) do
    create(:easy_form_designer_form_field, :select_priority, form: form, label: "Priority", token: "priority")
  end

  describe "token generation" do
    it "derives a token from the name" do
      section = create(:easy_form_designer_form_section, form: form, name: "Hardware details", token: nil)

      expect(section.token).to eq("hardware_details")
    end

    it "disambiguates a token that is already taken" do
      create(:easy_form_designer_form_section, form: form, name: "Details", token: nil)
      form.reload
      second = create(:easy_form_designer_form_section, form: form, name: "Details", token: nil)

      expect(second.token).to eq("details_2")
    end
  end

  describe "the visibility rule" do
    it "is valid with no rule at all — an ungated group" do
      expect(build(:easy_form_designer_form_section, form: form)).to be_valid
    end

    it "is valid with all three parts" do
      section = build(:easy_form_designer_form_section, :gated, form: form,
                                                                visibility_field: trigger,
                                                                visibility_value: priority.id.to_s)

      expect(section).to be_valid
    end

    # Two parts out of three isn't "no rule", it's a rule nothing can
    # evaluate — and #visible? would have to guess which way to fail.
    it "rejects a field and operator with no value" do
      section = build(:easy_form_designer_form_section, :gated, form: form, visibility_field: trigger)

      expect(section).not_to be_valid
    end

    it "rejects a value with no field" do
      section = build(:easy_form_designer_form_section, form: form, visibility_value: "anything")

      expect(section).not_to be_valid
    end

    it "rejects an unrecognised operator" do
      section = build(:easy_form_designer_form_section, form: form, visibility_field: trigger,
                                                        visibility_operator: "contains",
                                                        visibility_value: priority.id.to_s)

      expect(section).not_to be_valid
    end

    it "rejects a field belonging to another form" do
      foreign = create(:easy_form_designer_form_field, :select_priority,
                       form: create(:easy_form_designer_form, project: project, tracker: tracker))
      section = build(:easy_form_designer_form_section, :gated, form: form, visibility_field: foreign,
                                                                visibility_value: priority.id.to_s)

      expect(section).not_to be_valid
    end

    # A multi-value field CAN drive a rule, now that operators come from
    # EasyQuery: a multi-value list is :list_optional, which offers = and !
    # like any other list. The earlier blanket refusal was an artefact of the
    # invented single-value comparison.
    it "accepts a multi_select field as the rule's input" do
      cf = create(:issue_custom_field, field_format: "list", multiple: true, possible_values: %w[a b],
                                       is_for_all: false, projects: [project.id], trackers: [tracker])
      multi = create(:easy_form_designer_form_field, :multi_select, form: form, custom_field: cf)
      section = build(:easy_form_designer_form_section, :gated, form: form, visibility_field: multi,
                                                                visibility_value: "a")

      expect(section).to be_valid
    end

    # A file field's answer is uploads — nothing filterable, so it has no
    # filter type and no operators to offer.
    it "rejects a file field as the rule's input" do
      file_field = create(:easy_form_designer_form_field, :file_upload, form: form)
      section = build(:easy_form_designer_form_section, :gated, form: form, visibility_field: file_field,
                                                                visibility_value: "x")

      expect(section).not_to be_valid
    end

    # No chained conditionals in v1 — a rule whose own input might never have
    # been asked is a materially harder problem the PRD doesn't ask for.
    it "rejects a field that itself sits in a conditional section" do
      gated = create(:easy_form_designer_form_section, :gated, form: form, visibility_field: trigger,
                                                               visibility_value: priority.id.to_s)
      nested_field = create(:easy_form_designer_form_field, form: form, widget: "text",
                                                            mapped_attribute: "subject", section: gated)
      form.reload

      section = build(:easy_form_designer_form_section, :gated, form: form, visibility_field: nested_field,
                                                                visibility_value: "x")

      expect(section).not_to be_valid
    end

    # Reuses FormField#preset_options — the same source of truth M8's preset
    # validation uses for "what can this field legally hold?"
    it "rejects a value that isn't one of the field's options" do
      section = build(:easy_form_designer_form_section, :gated, form: form, visibility_field: trigger,
                                                                visibility_value: "not-a-priority")

      expect(section).not_to be_valid
    end

    # A text field's operators are the text ones — EasyQuery's :text type has
    # no "=" at all, so "contains" is how you match one.
    it "accepts any value for a free-text field, which has no fixed options" do
      text = create(:easy_form_designer_form_field, form: form, widget: "text", mapped_attribute: "subject")
      section = build(:easy_form_designer_form_section, form: form, visibility_field: text,
                                                        visibility_operator: "~",
                                                        visibility_value: "anything at all")

      expect(section).to be_valid
    end

    it "rejects an operator the field's own type does not offer" do
      text = create(:easy_form_designer_form_field, form: form, widget: "text", mapped_attribute: "subject")
      # ":text" offers ~ !~ ^~ $~ !* * — never "=".
      section = build(:easy_form_designer_form_section, :gated, form: form, visibility_field: text,
                                                                visibility_value: "x")

      expect(section).not_to be_valid
    end

    # EasyQuery.hidden_values_by_operator — "is set" carries its own meaning,
    # so it needs no value, and any value left over from a previous choice is
    # cleared rather than kept as misleading dead data.
    #
    # Deliberately NOT the priority field: priority is :list, which offers
    # only = and !, because a priority is always set. "Is set" belongs to
    # :list_optional — the per-type operator lists really are different.
    it "accepts a value-less operator and clears any leftover value", :aggregate_failures do
      category = create(:easy_form_designer_form_field, form: form, widget: "select",
                                                        mapped_attribute: "category_id")
      section = create(:easy_form_designer_form_section, form: form, visibility_field: category,
                                                         visibility_operator: "*",
                                                         visibility_value: "leftover")

      expect(section).to be_valid
      expect(section.visibility_value).to be_nil
    end

    it "offers a field only the operators its own filter type allows", :aggregate_failures do
      category = create(:easy_form_designer_form_field, form: form, widget: "select",
                                                        mapped_attribute: "category_id")
      list_rule = build(:easy_form_designer_form_section, form: form, visibility_field: trigger)
      optional_rule = build(:easy_form_designer_form_section, form: form, visibility_field: category)

      # priority_id is :list, category_id is :list_optional — straight from
      # EasyIssueQuery's own filter declarations.
      expect(list_rule.available_operators).to eq(%w[= !])
      expect(optional_rule.available_operators).to eq(["=", "!", "!*", "*"])
    end

    it "requires two values for a between rule" do
      number = create(:easy_form_designer_form_field, :number_estimated, form: form)
      section = build(:easy_form_designer_form_section, form: form, visibility_field: number,
                                                        visibility_operator: "><",
                                                        visibility_value: [5].to_json)

      expect(section).not_to be_valid
    end

    it "accepts a between rule with both bounds" do
      number = create(:easy_form_designer_form_field, :number_estimated, form: form)
      section = build(:easy_form_designer_form_section, form: form, visibility_field: number,
                                                        visibility_operator: "><",
                                                        visibility_value: [5, 10].to_json)

      expect(section).to be_valid
    end

    it "requires a day count for a relative-date rule" do
      date = create(:easy_form_designer_form_field, :date_due, form: form)
      section = build(:easy_form_designer_form_section, form: form, visibility_field: date,
                                                        visibility_operator: ">t-",
                                                        visibility_value: ["soon"].to_json)

      expect(section).not_to be_valid
    end
  end

  describe "#visible?" do
    let(:section) do
      create(:easy_form_designer_form_section, :gated, form: form, visibility_field: trigger,
                                                       visibility_value: priority.id.to_s)
    end

    it "is always visible with no rule" do
      ungated = create(:easy_form_designer_form_section, form: form)

      expect(ungated.visible?({})).to be(true)
    end

    context "with an equals rule" do
      it "is visible when the answer matches" do
        expect(section.visible?("priority" => priority.id.to_s)).to be(true)
      end

      it "is hidden when the answer differs" do
        expect(section.visible?("priority" => other_priority.id.to_s)).to be(false)
      end

      it "is hidden when the field was never answered" do
        expect(section.visible?({})).to be(false)
      end
    end

    # EasyQuery's "!" is `NOT IN (...) OR IS NULL`, so it is also true of an
    # unanswered field — which is what makes it usable as an "unless" gate.
    context "with a not-equals rule" do
      before { section.update!(visibility_operator: "!") }

      it "is hidden when the answer matches" do
        expect(section.visible?("priority" => priority.id.to_s)).to be(false)
      end

      it "is visible when the answer differs" do
        expect(section.visible?("priority" => other_priority.id.to_s)).to be(true)
      end

      # "not equal to X" is true of an unanswered field, which is the reading
      # that keeps a not-equals section usable as an "unless" gate.
      it "is visible when the field was never answered" do
        expect(section.visible?({})).to be(true)
      end
    end

    it "accepts symbol-keyed answers" do
      expect(section.visible?(priority: priority.id.to_s)).to be(true)
    end
  end

  describe "when the rule's field is deleted" do
    let!(:section) do
      create(:easy_form_designer_form_section, :gated, form: form, visibility_field: trigger,
                                                       visibility_value: priority.id.to_s)
    end

    # All THREE columns have to go. Clearing only the reference would leave a
    # half-specified rule behind, and the section would then fail its own
    # all-or-nothing validation the next time anyone saved the form — broken
    # by a field somebody deleted a week ago.
    it "clears the whole rule, not just the reference", :aggregate_failures do
      trigger.destroy!
      section.reload

      expect(section.visibility_field_id).to be_nil
      expect(section.visibility_operator).to be_nil
      expect(section.visibility_value).to be_nil
      expect(section).to be_valid
    end

    it "leaves the section unconditionally visible" do
      trigger.destroy!

      expect(section.reload.visible?({})).to be(true)
    end
  end

  describe "deleting a section" do
    it "deletes its member fields with it" do
      section = create(:easy_form_designer_form_section, form: form)
      create(:easy_form_designer_form_field, form: form, widget: "text", mapped_attribute: "subject",
                                             section: section)

      expect { section.destroy! }.to change(EasyFormDesigner::FormField, :count).by(-1)
    end
  end
end
