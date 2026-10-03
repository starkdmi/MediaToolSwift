# To publish new version to CocoaPods:
# - update `spec.version`, commit it, and create and push the matching Git tag
# - create a GitHub release from the pushed tag
# - `pod trunk push MediaToolSwift.podspec --allow-warnings`

Pod::Spec.new do |spec|
  spec.name                 = "MediaToolSwift"
  spec.version              = "1.3.0"
  spec.summary              = "A Swift library for media handling and manipulation."
  spec.description          = <<-DESC
                      MediaToolSwift is a Swift library that provides a collection of classes and utilities for media handling and manipulation. It provides an easy-to-use interface for performing common media operations such as compression, conversion, resizing and more. Supports video, image and audio media types.
                      DESC
  spec.homepage             = "https://github.com/starkdmi/MediaToolSwift"
  spec.license              = { :type => 'MPL-2.0', :file => 'LICENSE' }
  spec.author               = "Dmitry Starkov"
  spec.source               = { :git => "https://github.com/starkdmi/MediaToolSwift.git", :tag => "#{spec.version}" }
  spec.platforms            = { :ios => "15.0", :osx => "12.0", :tvos => "15.0", :visionos => "1.0" }
  spec.source_files         = "Sources/**/*.swift", "Sources/Classes/ObjCExceptionCatcher/**/*.{h,m}"
  spec.public_header_files  = "Sources/Classes/ObjCExceptionCatcher/**/*.h"
  spec.resource_bundles     = {"MediaToolSwift" => ["Sources/PrivacyInfo.xcprivacy"]}
  #spec.pod_target_xcconfig = {
  #  'OTHER_SWIFT_FLAGS[config=Advanced]' => '-DADVANCED -DIMAGEPLUS',
  #}
  spec.frameworks           = "Foundation", "AVFoundation", "VideoToolbox", "AudioToolbox", "Accelerate", "CoreImage", "ImageIO", "CoreMedia", "CoreLocation"
  spec.ios.frameworks       = "MobileCoreServices"
  spec.tvos.frameworks      = "MobileCoreServices"
  #spec.osx.frameworks      = ""
  spec.module_name          = "MediaToolSwift"
  spec.swift_version        = "5.9"
  spec.requires_arc         = true
end
