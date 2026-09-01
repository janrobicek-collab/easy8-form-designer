class AddSectionToEasyFormDesignerFormFields < ActiveRecord::Migration[7.2]

  def change
    # PRD M11. Null means the field is top-level / ungrouped, which is what
    # every field that already exists is — so this column changes nothing
    # about any current form until an author actually creates a section.
    add_column :easy_form_designer_form_fields, :section_id, :integer, null: true
    add_index :easy_form_designer_form_fields, :section_id
  end

end
