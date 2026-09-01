require "easy_extensions/spec_helper"

# The security control behind PRD M8's hidden fields: a hidden field's answer
# must come from the form's own preset, never from whatever a request happens
# to carry for its token — the requester form never even renders an input for
# it, but nothing stops a crafted POST from including one anyway.
RSpec.describe EasyFormDesigner::AnswerResolver, logged: :admin do
  subject(:resolve) { described_class.new(form, answers).call }

  let_it_be(:tracker, refind: true) { create(:tracker) }
  let_it_be(:project, refind: true) { create(:project, trackers: [tracker]) }

  let(:form) { create(:easy_form_designer_form, project: project, tracker: tracker) }

  context "with a hidden preset field and no submitted value for it" do
    let(:answers) { {} }

    before do
      create(:easy_form_designer_form_field, :hidden_priority, form: form, label: "Priority", token: "priority")
      form.reload
    end

    it "fills in the preset" do
      expect(resolve["priority"]).to eq(IssuePriority.active.first!.id.to_s)
    end
  end

  context "with a hidden preset field AND a submitted value for its token (the tamper case)" do
    # Two explicitly distinct records — not IssuePriority.active.first/.last,
    # which could coincidentally be the same record in a sparsely-seeded test
    # environment and make the "discarded" assertion pass for the wrong
    # reason (nothing to distinguish, not because AnswerResolver did its job).
    let_it_be(:preset_priority) { create(:issue_priority) }
    let_it_be(:other_priority) { create(:issue_priority) }

    let(:answers) { { "priority" => other_priority.id.to_s } }

    before do
      create(:easy_form_designer_form_field, form: form, label: "Priority", token: "priority", widget: "select",
                                             mapped_attribute: "priority_id", hidden: true,
                                             preset_value: preset_priority.id.to_s)
      form.reload
    end

    it "discards the submitted value and uses the preset instead" do
      expect(other_priority.id).not_to eq(preset_priority.id) # sanity: the two really do differ
      expect(resolve["priority"]).to eq(preset_priority.id.to_s)
    end
  end

  context "with a hidden day-offset preset" do
    let(:answers) { {} }

    before do
      create(:easy_form_designer_form_field, :preset_due_date_offset, form: form, label: "Due date",
                                                                      token: "due_date")
      form.reload
    end

    it "resolves the offset against today" do
      expect(resolve["due_date"]).to eq((Date.current + 7).to_s)
    end
  end

  context "with a VISIBLE field that has a default" do
    # Explicit, not IssuePriority.active.first! — see the note on
    # preset_priority/other_priority above; a global enumeration's ambient
    # contents shouldn't be load-bearing for this test's setup.
    let_it_be(:default_priority) { create(:issue_priority) }
    let_it_be(:submitted_priority) { create(:issue_priority) }

    let(:answers) { {} }

    before do
      create(:easy_form_designer_form_field, form: form, label: "Priority", token: "priority", widget: "select",
                                             mapped_attribute: "priority_id", hidden: false,
                                             preset_value: default_priority.id.to_s)
      form.reload
    end

    # This is the other half of PRD M8: a visible field's default is a
    # PREFILL the requester may change, seeded in the controller's #new
    # action — never re-applied here. If AnswerResolver overwrote it too, a
    # requester who deliberately cleared or changed a defaulted field would
    # have that choice silently discarded.
    it "does NOT overwrite an already-submitted value" do
      answers = { "priority" => submitted_priority.id.to_s }

      expect(described_class.new(form, answers).call["priority"]).to eq(submitted_priority.id.to_s)
    end

    it "does not inject the default when the requester left it blank" do
      expect(resolve).not_to have_key("priority")
    end
  end

  # PRD M11. Same tamper property as the M8 presets above, different remedy:
  # a field in a hidden section wasn't asked and has no preset to fall back
  # on, so its answer is DISCARDED rather than replaced.
  context "with a field in a section whose rule evaluates false" do
    let_it_be(:shown_priority) { create(:issue_priority) }
    let_it_be(:other_priority) { create(:issue_priority) }

    let(:answers) { { "priority" => other_priority.id.to_s, "serial" => "SN-12345" } }

    before do
      trigger = create(:easy_form_designer_form_field, :select_priority, form: form, label: "Priority",
                                                                         token: "priority")
      section = create(:easy_form_designer_form_section, :gated, form: form, visibility_field: trigger,
                                                                 visibility_value: shown_priority.id.to_s)
      create(:easy_form_designer_form_field, form: form, label: "Serial", token: "serial", widget: "text",
                                             mapped_attribute: "subject", section: section)
      form.reload
    end

    it "discards the answer for the hidden section's field" do
      expect(resolve).not_to have_key("serial")
    end

    it "leaves answers outside the section untouched" do
      expect(resolve["priority"]).to eq(other_priority.id.to_s)
    end

    context "when the rule matches" do
      let(:answers) { { "priority" => shown_priority.id.to_s, "serial" => "SN-12345" } }

      it "keeps the answer" do
        expect(resolve["serial"]).to eq("SN-12345")
      end
    end
  end

  # A hidden M8 field is a legitimate rule input — by the time sections are
  # evaluated it is guaranteed to be carrying its preset, which is why the
  # resolver evaluates them against the already-preset-filled hash.
  context "when the rule reads an M8 hidden preset field" do
    let_it_be(:stamped_priority) { create(:issue_priority) }

    let(:answers) { { "serial" => "SN-12345" } }

    before do
      trigger = create(:easy_form_designer_form_field, form: form, label: "Priority", token: "priority",
                                                       widget: "select", mapped_attribute: "priority_id",
                                                       hidden: true, preset_value: stamped_priority.id.to_s)
      section = create(:easy_form_designer_form_section, :gated, form: form, visibility_field: trigger,
                                                                 visibility_value: stamped_priority.id.to_s)
      create(:easy_form_designer_form_field, form: form, label: "Serial", token: "serial", widget: "text",
                                             mapped_attribute: "subject", section: section)
      form.reload
    end

    it "sees the preset and keeps the section's field" do
      expect(resolve["serial"]).to eq("SN-12345")
    end
  end

  context "with an ordinary visible, unmapped-preset field" do
    let(:answers) { { "name" => "Jane" } }

    before do
      create(:easy_form_designer_form_field, form: form, label: "Name", token: "name", widget: "text",
                                             mapped_attribute: "subject")
      form.reload
    end

    it "passes the submitted answers through unchanged" do
      expect(resolve).to eq(answers)
    end
  end
end
