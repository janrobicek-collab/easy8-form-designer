Rails.application.routes.draw do
  resources :easy_form_designer_forms, path: "form-designer/forms" do
    member do
      post :publish
      post :unpublish
    end

    # Requester-facing fill-in + submit, scoped under the form it belongs to.
    resource :submission, only: %i[new create show],
                          controller: "easy_form_designer_submissions",
                          as: :easy_form_designer_submission
  end

  # Mappable native/custom attributes for a given project + tracker pair.
  # Feeds the builder's "Maps to" dropdown.
  get "form-designer/attributes", to: "easy_form_designer_attributes#index",
                                  as: :easy_form_designer_attributes
end
