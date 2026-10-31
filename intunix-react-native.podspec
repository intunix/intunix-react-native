require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "intunix-react-native"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = { "Intunix" => "support@intunix.com" }
  s.platforms    = { :ios => "15.0" }
  s.source       = { :git => "https://github.com/intunix/intunix-react-native.git", :tag => s.version.to_s }
  s.source_files = "ios/**/*.{h,m,mm,swift}"
  s.swift_version = "5.9"
  # The vendored SDK uses Swift `package` access, which needs a package name outside SwiftPM.
  s.pod_target_xcconfig = { "OTHER_SWIFT_FLAGS" => "$(inherited) -package-name intunix" }

  s.dependency "React-Core"

  # The Intunix iOS SDK sources are vendored in ios/IntunixSDK (see scripts/sync-ios-sdk.sh):
  # spm_dependency links the Swift package twice into the pod.
end
