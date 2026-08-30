$LOAD_PATH.push File.expand_path("lib", __dir__)

require "easy_form_designer/version"

Gem::Specification.new do |s|
  s.name        = "easy_form_designer"
  s.version     = EasyFormDesigner::VERSION
  s.authors     = ["Easy Software"]
  s.email       = ["info@easysoftware.com"]
  s.homepage    = "https://easysoftware.com"
  s.summary     = "Custom Forms Engine for Easy8."
  s.description = "No-code form builder that compiles submissions into correctly-fielded Easy8 tasks."
  s.license     = "GPL-2.0-or-later"

  s.metadata["allowed_push_host"] = "https://gems.easysoftware.com"

  s.files      = Dir["{api,app,config,db,lib,easy_patch}/**/{*,.*}", "README.md"]
  s.test_files = Dir["spec/**/*"]

  s.add_dependency "rys"
end
