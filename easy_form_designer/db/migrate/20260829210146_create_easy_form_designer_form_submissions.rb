class CreateEasyFormDesignerFormSubmissions < ActiveRecord::Migration[7.2]

  def change
    create_table :easy_form_designer_form_submissions do |t|
      t.belongs_to :form, null: false
      t.belongs_to :issue, null: true
      t.belongs_to :user, null: true

      # Raw answers keyed by field token — the audit trail of what the requester
      # actually submitted, independent of any later edit to the created issue.
      t.json :payload

      t.timestamps
    end
  end

end
