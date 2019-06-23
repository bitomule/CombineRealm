Pod::Spec.new do |s|

  s.name             = "CombineRealm"
  s.version          = "1.0.0"
  s.summary          = "A Combine wrapper of Realm's notifications and write bindings"
  s.swift_version    = "5.0"

  s.description      = <<-DESC
    This is a Combine extension that provides an easy and straight-forward way
    to use Realm's natively reactive collection type as a Publisher
                       DESC

  s.homepage         = "https://github.com/bitomule/CombineRealm"
  s.license          = 'MIT'
  s.author           = { "David Collado" => "bitomule@gmail.com" }
  s.source           = { :git => "https://github.com/bitomule/CombineRealm.git", :tag => s.version.to_s }

  s.requires_arc = true

  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.15'
  s.tvos.deployment_target = '13.0'
  s.watchos.deployment_target = '6.0'

  s.source_files = 'Pod/Classes/*.swift'

  s.frameworks = 'Foundation'
  s.dependency 'RealmSwift', '~> 3.14'

end