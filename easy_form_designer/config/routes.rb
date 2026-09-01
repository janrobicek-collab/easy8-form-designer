Rails.application.routes.draw do
  resources :easy_form_designer_forms, path: "form-designer/forms" do
    member do
      post :publish
      post :unpublish
      # Feeds the builder's preset-value picker (PRD M8). Form-scoped, not
      # under /form-designer/attributes — see the controller action's comment.
      get :preset_options, path: "preset-options"
    end
  end

  # Requester-facing fill-in + submit, scoped under the form it belongs to.
  #
  # Deliberately not a nested `resource` block: Rails prefixes a nested
  # resource's `as:` with the parent's own name regardless, producing
  # easy_form_designer_form_easy_form_designer_submission_path — explicit
  # routes keep the helper names short and matching what the views call.
  get "form-designer/forms/:easy_form_designer_form_id/submission/new",
      to: "easy_form_designer_submissions#new",
      as: :new_easy_form_designer_form_submission

  get "form-designer/forms/:easy_form_designer_form_id/submission",
      to: "easy_form_designer_submissions#show",
      as: :easy_form_designer_form_submission

  post "form-designer/forms/:easy_form_designer_form_id/submission",
      to: "easy_form_designer_submissions#create"

  # PRD M11. Re-renders the fields for the answers so far, so a conditional
  # section appears the moment its rule is satisfied. POST rather than GET
  # because it carries every answer — a multipart form's worth of them.
  post "form-designer/forms/:easy_form_designer_form_id/submission/refresh",
      to: "easy_form_designer_submissions#refresh",
      as: :refresh_easy_form_designer_form_submission

  # Mappable native/custom attributes for a given project + tracker pair.
  # Feeds the builder's "Maps to" dropdown.
  get "form-designer/attributes", to: "easy_form_designer_attributes#index",
                                  as: :easy_form_designer_attributes
end
