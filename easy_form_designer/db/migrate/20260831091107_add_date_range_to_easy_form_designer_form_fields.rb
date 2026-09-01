class AddDateRangeToEasyFormDesignerFormFields < ActiveRecord::Migration[7.2]

  def change
    # Date-widget format validation: an absolute bound OR a day offset from
    # "today" (the day of submission, not of authoring) — never both for the
    # same side. Flat columns rather than one JSON blob, matching every other
    # column added to this table.
    add_column :easy_form_designer_form_fields, :min_date, :date, null: true
    add_column :easy_form_designer_form_fields, :max_date, :date, null: true

    # Signed integer days from today. Negative means "in the past" (e.g. -7 on
    # min_date_offset_days rejects anything more than 7 days ago); positive
    # means "in the future" (e.g. +30 on max_date_offset_days caps how far out
    # a date can be booked).
    add_column :easy_form_designer_form_fields, :min_date_offset_days, :integer, null: true
    add_column :easy_form_designer_form_fields, :max_date_offset_days, :integer, null: true
  end

end
