class CreateEasyFormDesignerFormFields < ActiveRecord::Migration[7.2]

  def change
    create_table :easy_form_designer_form_fields do |t|
      t.belongs_to :form, null: false

      t.integer :position, null: false, default: 1
      t.string :label, null: false
      t.string :help_text
      t.string :token, null: false
      t.string :widget, null: false
      t.boolean :required, null: false, default: false

      # Exactly one of these must be set — enforced in the model. Either a
      # native attribute name ("subject", "priority_id", ...) or an
      # IssueCustomField valid for the form's project + tracker pair.
      t.string :mapped_attribute
      t.belongs_to :custom_field, null: true

      t.timestamps
    end

    add_index :easy_form_designer_form_fields, %i[form_id token], unique: true
    add_index :easy_form_designer_form_fields, %i[form_id position]
  end

end
