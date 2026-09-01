require "easy_extensions/spec_helper"

RSpec.describe EasyFormDesigner::Form, logged: :admin do
  subject(:form) { build(:easy_form_designer_form, project: project, tracker: tracker) }

  let_it_be(:tracker, refind: true) { create(:tracker) }
  let_it_be(:project, refind: true) { create(:project, trackers: [tracker]) }

  describe "validations" do
    it { is_expected.to be_valid }

    it "requires a name" do
      form.name = ""
      expect(form).not_to be_valid
    end

    context "when the tracker is not enabled on the project" do
      let_it_be(:foreign_tracker) { create(:tracker) }

      subject(:form) { build(:easy_form_designer_form, project: project, tracker: foreign_tracker) }

      # The gateway pair must be internally consistent, or the whole mapping
      # scope computed from it is meaningless.
      it { is_expected.not_to be_valid }
    end
  end

  # REQ-16. Every field requires a section, so a form has to have somewhere
  # to put a first one before the builder can ever add it.
  describe "#ensure_default_section" do
    it "creates one section on creation" do
      form = create(:easy_form_designer_form, project: project, tracker: tracker)

      expect(form.sections.count).to eq(1)
    end

    it "names it from the locale" do
      form = create(:easy_form_designer_form, project: project, tracker: tracker)

      expect(form.sections.first.name).to eq(I18n.t("easy_form_designer.form_section.default_name"))
    end
  end

  describe "#publishable?" do
    subject(:form) { create(:easy_form_designer_form, project: project, tracker: tracker) }

    context "with no fields" do
      it { expect(form).not_to be_publishable }
    end

    context "when every field is mapped" do
      before do
        create(:easy_form_designer_form_field, form: form, mapped_attribute: "subject")
        form.reload
      end

      it { expect(form).to be_publishable }
    end
  end

  # PRD M11. The requester page watches exactly these answers and asks the
  # server for a fresh render when one of them changes, so getting the set
  # wrong means either a section that never appears or a round trip on every
  # keystroke of an unrelated field.
  describe "#rule_trigger_tokens" do
    subject(:form) { create(:easy_form_designer_form, project: project, tracker: tracker) }

    let(:trigger) do
      create(:easy_form_designer_form_field, :select_priority, form: form, label: "Priority", token: "priority")
    end

    it "is empty when no section has a rule" do
      create(:easy_form_designer_form_field, form: form, token: "reason")
      create(:easy_form_designer_form_section, form: form, name: "Notes", token: "notes")

      expect(form.reload.rule_trigger_tokens).to be_empty
    end

    it "names the field a rule reads, and only that one", :aggregate_failures do
      gated = create(:easy_form_designer_form_section, :gated, form: form, name: "Extras", token: "extras",
                                                               visibility_field: trigger,
                                                               visibility_value: create(:issue_priority).id.to_s)
      create(:easy_form_designer_form_field, form: form, token: "serial", section: gated)

      expect(form.reload.rule_trigger_tokens).to eq(["priority"])
    end

    it "names a field driving several sections once" do
      priority = create(:issue_priority)
      2.times do |i|
        create(:easy_form_designer_form_section, :gated, form: form, name: "Extras #{i}", token: "extras_#{i}",
                                                         visibility_field: trigger,
                                                         visibility_value: priority.id.to_s)
      end

      expect(form.reload.rule_trigger_tokens).to eq(["priority"])
    end
  end

  describe "publishing" do
    subject(:form) { create(:easy_form_designer_form, project: project, tracker: tracker) }

    before do
      create(:easy_form_designer_form_field, form: form, mapped_attribute: "subject")
      form.reload
    end

    it "moves draft → published and back", :aggregate_failures do
      expect(form).to be_status_draft
      expect(form.publish).to be(true)
      expect(form.reload).to be_status_published
      expect(form.unpublish).to be(true)
      expect(form.reload).to be_status_draft
    end
  end

  describe ".visible" do
    let_it_be(:draft) { create(:easy_form_designer_form, project: project, tracker: tracker) }

    # Built as a draft and published only once it has a mapped field — a
    # published form with nothing mapped is invalid by design.
    let_it_be(:published) do
      create(:easy_form_designer_form, project: project, tracker: tracker).tap do |form|
        create(:easy_form_designer_form_field, form: form, mapped_attribute: "subject")
        form.reload.publish
      end
    end

    it "shows both to a manager" do
      expect(described_class.visible(User.current)).to include(draft, published)
    end
  end
end
