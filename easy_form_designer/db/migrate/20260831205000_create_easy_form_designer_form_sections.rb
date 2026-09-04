class CreateEasyFormDesignerFormSections < ActiveRecord::Migration[7.2]

  def change
    # PRD M11 — conditional sections. A named group of fields, optionally
    # gated behind a rule ("show only if field X equals / doesn't equal V").
    create_table :easy_form_designer_form_sections do |t|
      t.belongs_to :form, null: false

      t.integer :position, null: false, default: 1
      t.string :name, null: false

      # Derived from the name the same way a field's token is derived from
      # its label. Needed because the description template names a section
      # in its block markers: {{#token}} ... {{/token}}.
      t.string :token, null: false

      # The rule. All three are null for an always-visible section; the model
      # enforces all-or-nothing, since a half-specified rule is ambiguous
      # rather than absent.
      #
      # NOT a foreign key constraint on visibility_field_id: FormField's own
      # before_destroy clears these three columns when the referenced field
      # goes away, and a DB-level FK would turn that ordering into a
      # constraint violation instead.
      t.integer :visibility_field_id, null: true
      t.string :visibility_operator, null: true
      t.text :visibility_value, null: true

      t.timestamps
    end

    add_index :easy_form_designer_form_sections, %i[form_id token], unique: true
    add_index :easy_form_designer_form_sections, %i[form_id position]
    add_index :easy_form_designer_form_sections, :visibility_field_id
  end

end
