FactoryBot.define do
  factory :easy_form_designer_form, class: "EasyFormDesigner::Form" do
    sequence(:name) { |n| "Form ##{n}" }
    sequence(:description) { |n| "Form description ##{n}" }
    status { "draft" }
    author { User.current }

    project { association :project }
    tracker { project&.trackers&.first || association(:tracker) }

    trait :published do
      status { "published" }
    end
  end

  factory :easy_form_designer_form_field, class: "EasyFormDesigner::FormField" do
    sequence(:label) { |n| "Field ##{n}" }
    sequence(:position) { |n| n }
    widget { "text" }
    required { false }

    form { association :easy_form_designer_form }

    # Mapped to a native attribute by default — an unmapped field is invalid.
    mapped_attribute { "subject" }

    trait :long_text do
      widget { "long_text" }
      mapped_attribute { "description" }
    end

    trait :select_priority do
      widget { "select" }
      mapped_attribute { "priority_id" }
    end

    trait :date_due do
      widget { "date" }
      mapped_attribute { "due_date" }
    end

    trait :number_estimated do
      widget { "number" }
      mapped_attribute { "estimated_hours" }
    end

    trait :radio_priority do
      widget { "radio" }
      mapped_attribute { "priority_id" }
    end

    trait :user_assignee do
      widget { "user" }
      mapped_attribute { "assigned_to_id" }
    end

    # No native attribute is multi-valued or boolean today, so both are
    # custom-field only — the caller supplies a matching custom_field:
    # scoped to its own form's project + tracker, the same way every other
    # custom-field-mapped spec in this suite already does.
    trait :multi_select do
      widget { "multi_select" }
      mapped_attribute { nil }
    end

    trait :checkbox do
      widget { "checkbox" }
      mapped_attribute { nil }
    end

    # PRD M7 format rules. email/url are only legal on the "text" widget and a
    # range only on "number", which is why :ranged also switches the widget —
    # the model rejects the combination otherwise.
    trait :email_validated do
      widget { "text" }
      validation_format { "email" }
    end

    trait :url_validated do
      widget { "text" }
      validation_format { "url" }
    end

    trait :ranged do
      widget { "number" }
      mapped_attribute { "estimated_hours" }
      min_value { 1 }
      max_value { 40 }
    end

    # Maps to a custom field instead of a native attribute.
    trait :custom do
      mapped_attribute { nil }
      custom_field { association :issue_custom_field }
    end

    # PRD M8 — hidden/preset fields. A hidden field silently stamps a
    # value at submission; the PRD's own example is priority.
    #
    # `.first || create(...)` rather than `.first!`: IssuePriority is a
    # GLOBAL enumeration, not scoped to this factory's own project/tracker,
    # so whether one already exists depends entirely on what has (or hasn't)
    # been seeded/created elsewhere — order-dependent across the full suite.
    # Reuses one if the ambient data happens to provide it, creates one
    # otherwise, so this trait is never flaky about data it doesn't own.
    trait :hidden_priority do
      widget { "select" }
      mapped_attribute { "priority_id" }
      hidden { true }
      preset_value { (IssuePriority.active.first || create(:issue_priority)).id.to_s }
    end

    # The PRD's other headline example: "due date = today + 7 days".
    trait :preset_due_date_offset do
      widget { "date" }
      mapped_attribute { "due_date" }
      hidden { true }
      preset_offset_days { 7 }
    end

    # PRD M13. Always maps to the "attachments" pseudo-attribute — a file
    # field has no other possible target and no custom-field alternative.
    trait :file_upload do
      widget { "file" }
      mapped_attribute { EasyFormDesigner::FormField::ATTACHMENTS_ATTRIBUTE }
    end
  end

  # PRD M11 — a named group of fields, optionally gated by a visibility rule.
  factory :easy_form_designer_form_section, class: "EasyFormDesigner::FormSection" do
    sequence(:name) { |n| "Section ##{n}" }
    sequence(:position) { |n| n }

    form { association :easy_form_designer_form }

    # Gated on a field the caller supplies — the rule needs a field, an
    # operator and (for operators that take one) a value, or the model
    # rejects it as half-specified.
    #
    # "=" is EasyQuery's own equals operator, not a name invented here; the
    # operators a rule may use come from EasyQuery.operators_by_filter_type
    # for the referenced field's filter type.
    trait :gated do
      visibility_operator { "=" }
    end
  end

  factory :easy_form_designer_form_submission, class: "EasyFormDesigner::FormSubmission" do
    form { association :easy_form_designer_form }
    user { User.current }
    payload { {} }
  end
end
