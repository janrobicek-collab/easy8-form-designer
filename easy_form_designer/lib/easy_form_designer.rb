require "rys"

require "easy_form_designer/version"
require "easy_form_designer/engine"

# == Configuration of EasyFormDesigner
# Static configuration stored in the memory
#
# @example Getting a configuration
#   EasyFormDesigner.config.my_key
#
# == Settings for EasyFormDesigner
# Dynamic settings stored in the DB
#
# @example Getting
#   EasyFormDesigner.setting(:my_value)
#
module EasyFormDesigner

  # Feature flag guarding the whole engine while it is unreleased.
  FEATURE_KEY = :easy_form_designer_enabled

  class << self

    # Whether the engine's UI and routes should be exposed at all.
    #
    # @return [Boolean]
    def enabled?
      EasyFeature.enabled?(FEATURE_KEY)
    end

    # Forms are administered globally, not per project.
    #
    # @param user [User, nil]
    # @return [Boolean]
    def visible_for?(user = nil)
      user ||= User.current

      enabled? && user.allowed_to_globally?(:view_easy_forms)
    end

    # @param user [User, nil]
    # @return [Boolean]
    def manageable_for?(user = nil)
      user ||= User.current

      enabled? && user.allowed_to_globally?(:manage_easy_forms)
    end

  end

end
