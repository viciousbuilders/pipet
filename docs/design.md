# Pipet design

Reading this as a native macOS utility for friends and everyday users, with a warm, playful visual language drawn from Plan2Go and PopPopAI.

Taste dials: DESIGN_VARIANCE 4, MOTION_INTENSITY 2, VISUAL_DENSITY 4. The Taste skill primarily targets the web; its brand, spacing, typography and copy principles are applied here alongside SwiftUI guidance from UI/UX Pro Max. Native controls and SF Symbols handle platform interactions.

Brand: Pipet. Voice into text, wherever you type. Coral speech-bubble mascot with sound bars, on cream. System rounded display typography and native system body type.

Semantic colors adapt to light and dark modes. Primary text and action labels target WCAG AA. Cards use 18-point corners, controls 10-point corners, and keycaps 8-point corners. Motion is limited to recording feedback and short state transitions, with Reduce Motion respected.

Audit: the previous app had a CV wordmark, a permissions-only settings page, and a small HUD whose errors disappeared quickly. Keep the global hold shortcut, privacy disclosure, optional login launch and transcript recovery. Replace the CV identity, show Codex setup status, add a practice text field, and keep recoverable errors visible in the main window.

No account credentials or recordings are included in releases. Recipients use their own Codex sign-in.
