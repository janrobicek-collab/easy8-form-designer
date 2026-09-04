class AddPresetsToEasyFormDesignerFormFields < ActiveRecord::Migration[7.2]

  def change
    # PRD M8 — default and hidden/preset fields. A field can be hidden from the
    # requester entirely, or shown pre-filled with a value the requester may
    # still change — `hidden` alone decides which, on top of the same preset.
    add_column :easy_form_designer_form_fields, :hidden, :boolean, null: false, default: false

    # Mirrors the min_date/min_date_offset_days shape already on this table
    # (see 20260831091107): a fixed value, OR a day offset from today for the
    # "date" widget only — never both, enforced in the model exactly like the
    # existing date-bound pair. A multi_select preset is stored as a
    # newline-separated list in this same text column, the same idiom core
    # itself uses for CustomField#possible_values= (splits on /[\n\r]+/) —
    # not JSON, to stay consistent with every other column on this table.
    add_column :easy_form_designer_form_fields, :preset_value, :text, null: true
    add_column :easy_form_designer_form_fields, :preset_offset_days, :integer, null: true
  end

end
