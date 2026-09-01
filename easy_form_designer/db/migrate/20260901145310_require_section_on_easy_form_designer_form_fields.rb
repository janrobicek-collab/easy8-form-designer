class RequireSectionOnEasyFormDesignerFormFields < ActiveRecord::Migration[7.2]

  # REQ-16. Every field lives in a section from here on — the previous
  # migration guarantees every existing field already has one.
  def up
    change_column_null :easy_form_designer_form_fields, :section_id, false
  end

  def down
    change_column_null :easy_form_designer_form_fields, :section_id, true
  end

end
