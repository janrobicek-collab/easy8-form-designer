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

    # Maps to a custom field instead of a native attribute.
    trait :custom do
      mapped_attribute { nil }
      custom_field { association :issue_custom_field }
    end
  end

  factory :easy_form_designer_form_submission, class: "EasyFormDesigner::FormSubmission" do
    form { association :easy_form_designer_form }
    user { User.current }
    payload { {} }
  end
end
