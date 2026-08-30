EasyInitHelper.register_access_control_block do
  Redmine::AccessControl.map do |map|
    map.project_module :easy_form_designer do |pmap|
      # Browse the form library and open published forms.
      pmap.permission :view_easy_forms, {
        easy_form_designer_forms: %i[index show],
      }, global: true

      # Build, edit, publish and delete forms.
      pmap.permission :manage_easy_forms, {
        easy_form_designer_forms: %i[new create edit update destroy publish unpublish],
        easy_form_designer_attributes: %i[index],
      }, global: true, depends_on: :view_easy_forms

      # Fill in and submit a published form. Deliberately separate from
      # :view_easy_forms so a requester can submit without seeing the library.
      pmap.permission :submit_easy_forms, {
        easy_form_designer_submissions: %i[new create show],
      }, global: true, public: false
    end
  end
end
