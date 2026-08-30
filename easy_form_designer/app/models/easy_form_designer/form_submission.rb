module EasyFormDesigner
  # One completed submission and the task it produced.
  #
  # `payload` keeps the raw answers keyed by field token, so the record of what
  # the requester actually typed survives any later edit to the issue.
  class FormSubmission < EasyFormDesigner::ApplicationRecord
    belongs_to :form,
               class_name: "EasyFormDesigner::Form",
               inverse_of: :submissions

    belongs_to :issue, optional: true
    belongs_to :user, class_name: "User", optional: true

    validates :form, presence: true

    scope :sorted, -> { order(created_at: :desc) }

    # @return [Hash]
    def answers
      payload.presence || {}
    end

    # @param token [String]
    def answer_for(token)
      answers[token.to_s]
    end

  end
end
