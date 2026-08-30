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
