# To publish new version to CocoaPods:
# - create new release on Github with a tag `1.0.0`
# - `git tag 1.0.0`
# - `pod trunk push MediaToolSwift.podspec --allow-warnings`

Pod::Spec.new do |spec|
  spec.name         = "MediaToolSwift"
  spec.version      = "1.0.9"
  spec.summary      = "A Swift library for media handling and manipulation."
  spec.description  = <<-DESC
                      MediaToolSwift is a Swift library that provides a collection of classes and utilities for media handling and manipulation. It provides an easy-to-use interface for performing common media operations such as compression, conversion, resizing and more. Supports video, image and audio media types.
                      DESC
  spec.homepage     = "https://github.com/starkdmi/MediaToolSwift"
  spec.license      = { :type => 'MPL-2.0', :file => 'LICENSE' }
  spec.author       = "Dmitry Starkov"
  spec.source       = { :git => "https://github.com/starkdmi/MediaToolSwift.git", :tag => "#{spec.version}" }
  spec.platforms    = { :ios => "13.0", :osx => "11.0", :tvos => "13.0" }
  spec.source_files = "Sources/**/*.swift", "Sources/Classes/ObjCExceptionCatcher/**/*.{h,m}"
  spec.public_header_files = "Sources/Classes/ObjCExceptionCatcher/**/*.h"
  spec.frameworks   = "Foundation"
  # spec.ios.framework  = 'UIKit'
  # spec.tvos.framework = 'UIKit'
  # spec.osx.framework  = 'AppKit'
  spec.module_name  = "MediaToolSwift"
  spec.swift_version = "5.8"
  spec.requires_arc = true
  spec.dependency "SDWebImageWebPCoder"
end
