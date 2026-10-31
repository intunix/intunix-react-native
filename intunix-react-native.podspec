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

  s.dependency "React-Core"

  # The native Intunix iOS SDK is published with Swift Package Manager (React Native 0.75+).
  spm_dependency(s,
    url: "https://github.com/intunix/intunix-ios",
    requirement: { kind: "upToNextMajorVersion", minimumVersion: "1.5.6" },
    products: ["Intunix"]
  )
end
