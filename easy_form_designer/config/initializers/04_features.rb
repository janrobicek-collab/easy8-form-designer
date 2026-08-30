# Guards the whole engine while it is unreleased. Nothing in the UI or the
# menu is reachable unless this flag is on for the actor.
#
# `owners` is a team name, not a person (EasyFeatures::Feature: "no personal
# data"). EWOK is this project's own label — reassign to a real squad if the
# Forms engine is picked up at roadmap planning.
EasyFeatures.register(
  :easy_form_designer_enabled,
  owners: %w[EWOK],
  ref_id: "687043",
  introduced_in: "15.11.6",
  status: :experimental,
  description: "Custom Forms Engine — no-code form builder compiling submissions into Easy8 tasks"
)
