cask "tiny-clips" do
  auto_updates true
  version "1.4.0.2"
  sha256 "cbd118277fbe4dd7ba9bdba5fc26836696ec89c7c2ac8b2b1e4b05345b150438"

  url "https://github.com/jamesmontemagno/tiny-clips-mac/releases/download/v#{version}/TinyClips-v#{version}.zip"
  name "TinyClips"
  desc "Menu bar app for screenshot, video, and GIF capture"
  homepage "https://github.com/jamesmontemagno/tiny-clips-mac"

  app "TinyClips.app"

  postflight do
    system "xattr", "-dr", "com.apple.quarantine", "#{appdir}/TinyClips.app"
  end

  zap trash: [
    "~/Library/Preferences/com.tinyclips.app.plist",
  ]
end
