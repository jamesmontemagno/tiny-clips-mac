# Changelog

All notable changes to this project will be documented in this file.

## v0.0.20 - 2026-03-09

### Added
- Microphone selection and status indicator in audio recording settings.
- Automatic update checks with enhanced release notes in appcast.

### Improved
- Refactored settings window activation logic for improved reliability and behavior when opening from menu bar.
- Refactored CaptureManager methods to streamline recording flow and prepare for new capture requests.
- Audio capture handling with improved microphone functionality and adjustable capture thresholds.
- UI styling enhancements in StartRecordingPanel and StopRecordingPanel for improved appearance.

### Fixed
- Microphone capture robustness improvements addressing interruption handling.

## v0.0.19 - 2026-03-08

### Added
- Subscription management and restore purchase functionality.
- Clips Manager with Uploadcare integration for user uploads.
- Smart default file naming templates with live preview.
- Option to include TinyClips windows in captures.
- Collapsible sidebar toggle in Clips Manager.
- Sidebar filters and tag management in Clips Manager.
- Accessibility enhancements across various views, including keyboard shortcuts and hints.
- Help text and improved issue reporting template in settings.
- Enhanced clipboard options in CaptureSettings.

### Improved
- Dimension display in RegionSelectionView to include both point and pixel values for clarity.
- Capture region handling with pixelWidth and pixelHeight properties for accuracy.
- DPI settings with scaleFactor parameter in saveImage function.
- Pixel dimension calculations for capture region settings in trimmer views.
- Clips Manager UI with collapsible sidebar and improved grid layout stability.
- Settings sections organization and layout improvements.
- Image capture and display logic in ScreenshotCapture and RegionIndicatorPanel.

### Fixed
- Save notifications are now always presented with Finder open on click.
- Grid cell overlap issues in Clips Manager.
- Sidebar toggle no longer shifts with split view state.
- Grid thumbnail overlap issues in Clips Manager.

## v0.0.14 - 2026-02-17

### Added
- Multi-monitor support for region selection and full-screen capture.
- Display picker UI for selecting target screen on multi-monitor setups (full-screen capture mode).
- "Always capture main display" setting in General preferences to bypass display picker if desired.
- Global hotkey functionality for screenshot, video, and GIF recording.

### Improved
- Fixed region selection overlay rendering on secondary displays through corrected coordinate space initialization.
- Enhanced window focus and activation for improved multi-screen usability.
- Improved event handling for escape key cancellation in display picker and region selector.
- Better window management with centralized activation logic.

### Fixed
- Region selection now works correctly on secondary displays.
- Escape key handling in display picker and region selector on menu bar app context.

## v0.0.13 - 2026-02-16

### Added
- Speed control for GIF and video trimming with multiple speed options (0.5x, 0.75x, 1x, 1.1x, 1.25x, 1.5x, 2x).
- Immediate save setting for screenshots and GIFs with option to skip editor.
- Saving state and progress overlay to GIF and screenshot editors.

### Improved
- Enhanced screenshot and GIF saving options with better editor toggle controls.
- GIF and video trimmer speed options and playback speed handling.
- Image rendering and scaling in EditorViewModel for better visual fidelity.
- Trimmer window frame width adjustments for better usability.

### Changed
- Default screenshot format changed from PNG to JPEG for faster saves.

## v0.0.12 - 2026-02-15

### Added
- Full-screen capture override by holding Option when starting Screenshot, Video, or GIF capture.
- New Guide window from the menu bar with usage help and shortcut documentation.

### Improved
- Menu bar capture labels now update live while Option is held to clearly indicate full-screen capture mode.
- Guide UI refreshed with segmented sections, improved spacing, and clearer content grouping.
- Guide window sizing refined to reduce excessive vertical space.
- Video and GIF trimmer windows are now resizable for larger capture regions.

### Fixed
- Removed fixed-size constraints from Video and GIF trimmer views so window resizing works correctly.

## v0.0.11 - 2026-02-15

### Added
- First-run onboarding wizard for permissions setup.
- Save notification preference in settings (default off).
- Reset all settings to defaults option for easier testing.

### Improved
- Onboarding welcome screen visuals with app icon and clearer guidance.
- Screen Recording step now includes explicit restart guidance.
- Added dedicated re-check action for Screen Recording permission status.

### Fixed
- Avoided potential QoS priority inversion in permission checking.
- Prevented duplicate popups during Screen Recording permission requests.
- Only mark onboarding complete when user explicitly finishes or dismisses.

### Maintenance
- Updated appcast for release metadata.

## v0.0.10 - 2026-02-14

### Added
- Mac App Store variant (`TinyClipsMAS`) from the same codebase.
- App Store-related documentation and project setup guidance.

### Improved
- Editor image handling and output flow refinements.
- Video trimming and timeline behavior improvements.
- Better main-thread handling around file panels and UI operations.

### Fixed
- Added `ITSAppUsesNonExemptEncryption` where required.
- Corrected plist path/signing-related project configuration issues.

### Maintenance
- Removed obsolete CI workflows and refreshed docs.

## v0.0.9 - 2026-02-14

### Added
- Countdown before Video and GIF recording.
- Release workflow step to generate changelog content.

### Improved
- Screenshot editor bottom bar layout and organization.

## v0.0.8 - 2026-02-13

### Added
- Screenshot format selection (PNG/JPEG), scale, and JPEG quality settings.
- Additional entitlement updates to support distribution/security requirements.

### Maintenance
- Updated appcast for release metadata.
