class CreateEasyFormDesignerForms < ActiveRecord::Migration[7.2]

  def change
    create_table :easy_form_designer_forms do |t|
      t.string :name, null: false
      t.text :description

      # The gateway pair. Both are required before the builder can load — they
      # scope which native and custom attributes a field may map to.
      t.belongs_to :project, null: false
      t.belongs_to :tracker, null: false

      t.integer :status, null: false, default: 0
      t.belongs_to :author, null: false

      # Token templates compiled into the created issue's subject/description.
      t.string :subject_template
      t.text :description_template

      t.timestamps
    end

    add_index :easy_form_designer_forms, %i[project_id tracker_id]
    add_index :easy_form_designer_forms, :status
  end

end
