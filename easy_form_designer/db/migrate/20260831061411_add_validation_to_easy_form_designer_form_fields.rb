class AddValidationToEasyFormDesignerFormFields < ActiveRecord::Migration[7.2]

  def change
    # PRD M7 — per-field format validation. The `required` flag already ships
    # on this table; these three columns carry the rest of M7.
    #
    # Flat columns rather than a JSON blob, matching the style of the three
    # migrations that created this schema, and keeping an authored rule
    # queryable ("which fields validate as email?").
    #
    # nil | "email" | "url" — see FormField::VALIDATION_FORMATS.
    add_column :easy_form_designer_form_fields, :validation_format, :string, null: true

    # Numeric range bounds for the "number" widget. decimal(30,3) mirrors the
    # precision core itself casts numeric custom values to (see
    # Redmine::FieldFormat::Numeric#order_statement, which CASTs to
    # decimal(30,3)) — a tighter column here would let the database round a
    # bound away from what the admin actually typed.
    add_column :easy_form_designer_form_fields, :min_value, :decimal, precision: 30, scale: 3, null: true
    add_column :easy_form_designer_form_fields, :max_value, :decimal, precision: 30, scale: 3, null: true
  end

end
