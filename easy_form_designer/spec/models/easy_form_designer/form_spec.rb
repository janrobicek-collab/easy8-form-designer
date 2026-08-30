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
