# Mino Shared Space Design QA

- Source visual truth: `Design/References/shared-space-selected.png`
- Implementation capture: `Design/QA/shared-space-implementation.jpg`
- State: 陪伴 / 我们的空间，默认窗口状态
- Source pixels: 1487 × 1058
- Implementation pixels: 1126 × 768
- Native viewport: 1126 × 768 captured window area; this is a macOS window, so CSS size is not applicable
- Density normalization: compared by normalized frame proportions and original-resolution crops; the implementation capture is a Computer Use window capture rather than a browser screenshot

## Full-view comparison evidence

The source and implementation were opened together in one comparison input. The implementation preserves the selected composition: a 16.7% left navigation rail, title and online status in the upper-left of the content canvas, partner avatar in the upper-right, a full-bleed warm shared-room illustration, and centered bottom actions. Major proportions, hierarchy, warm cream/coral/mint tokens, and illustration quality match at the smaller native capture size.

## Focused-region evidence

The sidebar, title/status block, avatar, character scene, and bottom action area were readable at original resolution in the combined full-view comparison, so separate focused crops were not needed. The chat, interaction, and avatar states were also captured and inspected during the interaction pass.

## Required fidelity surfaces

- Fonts and typography: native macOS system/PingFang fallback matches the source hierarchy and Chinese rendering. Title, navigation, status, and action weights remain legible at the smaller viewport.
- Spacing and layout rhythm: sidebar ratio, title inset, scene crop, and bottom-action placement track the source. The window has a 980 × 680 minimum and scales without hiding persistent controls.
- Colors and visual tokens: warm ivory canvas, pale peach navigation selection, coral primary actions, mint presence state, and cocoa text match the selected direction with accessible contrast.
- Image quality and asset fidelity: the room and avatar use dedicated generated raster assets in the selected soft felt/clay art direction. No placeholder, emoji, CSS drawing, inline SVG, or code-native approximation replaces the visual assets.
- Copy and content: `我们的空间`, `团子在线`, `发个互动`, `说句话`, and the five primary destinations match the selected concept. Supporting screens use concise Chinese product copy.

## Findings

No actionable P0, P1, or P2 differences remain.

- P3: the `Mino` wordmark uses a rounded native text treatment rather than a final custom brand asset. This is acceptable for the current product foundation and can be replaced when the identity system is finalized.
- P3: a compact partner-presence row was added at the bottom of the sidebar. This is an intentional extension for persistent couple context and does not compete with the primary hierarchy.

## Interaction verification

- Navigation: 陪伴、事件线、聊天、互动、形象 all switch to working states.
- Chat: entering `晚安呀` enables 发送; sending appends the message and clears the composer.
- Interaction: the 亲亲 action invokes the existing desktop-pet interaction path.
- Avatar import: 导入形象素材 opens the native macOS image picker; the picker was cancelled without selecting user data.
- Accessibility: primary destinations, actions, status, avatar, text field, and native window controls are present in the macOS accessibility tree.

## Comparison history

1. Initial implementation capture was 212 × 506 because the SwiftUI root did not provide a minimum intrinsic frame. This P1 prevented the content canvas from appearing. Fixed by setting native content size and minimum/ideal root dimensions.
2. The first chat capture centered the message stack inside the scroll area. This P2 weakened conversation hierarchy. Fixed by giving the stack full available width with leading alignment.
3. Post-fix full-view comparison at 1126 × 768 found no remaining actionable P0/P1/P2 differences.

## Follow-up polish

- Replace the temporary rounded `Mino` text treatment after a production wordmark is approved.
- Add reduced-motion and high-contrast visual checks when accessibility settings become part of the release matrix.

final result: passed
