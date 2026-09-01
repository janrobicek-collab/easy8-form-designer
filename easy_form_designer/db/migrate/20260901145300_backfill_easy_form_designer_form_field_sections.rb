class BackfillEasyFormDesignerFormFieldSections < ActiveRecord::Migration[7.2]

  # Deliberately plain ActiveRecord::Base subclasses scoped to this
  # migration, not the live app models — EasyFormDesigner::FormField and
  # ::FormSection will keep changing after this migration exists (e.g.
  # #section becomes required in the very next one), and a data migration
  # must not be at the mercy of that drift. No validations or callbacks run
  # here on purpose; every column is written explicitly.
  class MigrationFormField < ActiveRecord::Base
    self.table_name = "easy_form_designer_form_fields"
  end

  class MigrationFormSection < ActiveRecord::Base
    self.table_name = "easy_form_designer_form_sections"
  end

  # REQ-16. Every field is about to be required to belong to a section.
  # Today `position` is a single form-wide sequence and `section_id` is
  # nullable — most fields have no section at all. This walks each form's
  # fields in their existing order and turns every maximal run of
  # consecutive ungrouped fields into its own new "General" section,
  # inserted at the position that run occupied, so the rendered order is
  # unchanged. A pre-existing section's fields keep their section but are
  # renumbered to a within-section position, since `position` stops being
  # form-wide immediately after this (see the following migration and
  # FormSection#fields' `order(:position)`, which is now scoped by
  # `section_id` through the association itself).
  #
  # Safe to run destructively here because the plugin is pre-release behind
  # `:easy_form_designer_enabled` with no production installs — this is not
  # a pattern to repeat once real data exists.
  def up
    form_ids = MigrationFormField.distinct.pluck(:form_id)
    form_ids.each { |form_id| backfill_form(form_id) }
  end

  def down
    # Nothing is destroyed by `up` — fields keep whatever section they end
    # up in, including a newly created "General" one. The follow-up
    # migration's own `down` is what actually matters (it relaxes the
    # NOT NULL constraint again); reversing the grouping itself would need a
    # marker distinguishing "backfilled" from "author-created" that this
    # migration doesn't keep, so it isn't attempted.
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def backfill_form(form_id)
    fields = MigrationFormField.where(form_id: form_id).order(:position, :id).to_a
    return if fields.empty?

    segments = build_segments(fields)
    order_and_persist(form_id, segments)
  end

  # Maximal runs of fields sharing the same section identity (nil, or a
  # given existing section id) in their current position order.
  def build_segments(fields)
    segments = []

    fields.each do |field|
      last = segments.last
      if last && last[:section_id] == field.section_id
        last[:fields] << field
      else
        segments << { section_id: field.section_id, fields: [field] }
      end
    end

    segments
  end

  def order_and_persist(form_id, segments)
    seen_existing_ids = []
    ordered_targets = []

    segments.each do |segment|
      if segment[:section_id]
        next if seen_existing_ids.include?(segment[:section_id])

        seen_existing_ids << segment[:section_id]
        ordered_targets << { existing_id: segment[:section_id] }
      else
        ordered_targets << { new_segment: segment }
      end
    end

    # A section with no fields at all (an author created it, hasn't put
    # anything in it yet) never appears in `segments` — append these at the
    # end, in their own existing relative order, matching what the builder
    # canvas already does for an empty section today.
    empty_sections = MigrationFormSection.where(form_id: form_id)
                                          .where.not(id: seen_existing_ids)
                                          .order(:position, :id)
    empty_sections.each { |section| ordered_targets << { existing_id: section.id } }

    ordered_targets.each_with_index do |target, index|
      position = index + 1

      if target[:new_segment]
        create_section_for_segment(form_id, target[:new_segment], position)
      else
        MigrationFormSection.where(id: target[:existing_id]).update_all(position: position)
      end
    end

    renumber_fields_within_sections(form_id, seen_existing_ids)
  end

  def create_section_for_segment(form_id, segment, position)
    name = unique_general_name(form_id)

    section = MigrationFormSection.create!(
      form_id: form_id,
      name: name,
      token: unique_general_token(form_id, name),
      position: position
    )

    segment[:fields].each_with_index do |field, index|
      field.update_columns(section_id: section.id, position: index + 1)
    end
  end

  # A pre-existing section's fields may have arrived here split across more
  # than one segment, if an author interleaved fields from two sections
  # before this migration (the builder discourages it but doesn't forbid
  # it). Position has to be renumbered across ALL of a section's fields
  # together, or two fields could land on the same position within it.
  def renumber_fields_within_sections(form_id, existing_section_ids)
    existing_section_ids.each do |section_id|
      fields = MigrationFormField.where(form_id: form_id, section_id: section_id).order(:position, :id)
      fields.each_with_index { |field, index| field.update_columns(position: index + 1) }
    end
  end

  def unique_general_name(form_id)
    taken = MigrationFormSection.where(form_id: form_id).pluck(:name)
    return "General" unless taken.include?("General")

    n = 2
    n += 1 while taken.include?("General #{n}")
    "General #{n}"
  end

  def unique_general_token(form_id, name)
    base = name.parameterize(separator: "_")
    taken = MigrationFormSection.where(form_id: form_id).pluck(:token)
    candidate = base
    suffix = 1
    while taken.include?(candidate)
      suffix += 1
      candidate = "#{base}_#{suffix}"
    end

    candidate
  end

end
