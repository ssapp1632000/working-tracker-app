# Floating Widget Feature Guide

## What is the Floating Widget?

The floating widget is a **minimalist, always-on-top timer** that stays visible while you work in other applications. It's perfect for tracking time without having the full app taking up screen space.

## How to Use

### 1. Switch to Floating Mode

There are two ways to activate floating mode:

**Option A: Click the Button**
1. In the dashboard, look at the top-right of the app bar
2. Click the **picture-in-picture icon** (📱)
3. The app will minimize to a small floating widget

**Option B: Minimize the Window**
- The current implementation uses a button (Option A above)
- Future versions will support minimize-to-float behavior

### 2. Using the Floating Widget

When in floating mode, you'll see:
- **Project name** - Currently tracked project
- **Timer display** - Running time in HH:MM:SS format
- **Dropdown arrow** - Click to expand and see all projects
- **Restore button** - Click to return to full app

#### Floating Widget Features:
✅ Always stays on top of other windows
✅ Small, non-intrusive size (300x300px)
✅ Slide-in/out animation on hover
✅ Switch between projects without opening full app
✅ Real-time timer updates

### 3. Return to Full App

To switch back to the full dashboard:
1. Hover over the floating widget (it will slide out)
2. Click the **maximize icon** (⛶) in the top-right
3. The full app window will restore

## Floating Widget Layout

```
┌─────────────────────────┐
│ 🏢  Project Name         │
│     01:23:45        ▼ ⛶ │  ← Main view (collapsed)
└─────────────────────────┘

When you hover:
┌───────────────────────────────┐
│ 🏢  Project Name               │
│     01:23:45          ▼ ⛶     │
├───────────────────────────────┤  ← Expanded view
│ 🏢  Binghatti Project_1   ●   │  ← Active project
│ 🏢  Binghatti Project_2        │
│ 🏢  Marina Heights             │
│ 🏢  Downtown Tower             │
└───────────────────────────────┘
```

## Quick Actions in Floating Mode

### Switch Projects
1. Hover over the widget
2. Click the **dropdown arrow** (▼)
3. Click any project to switch timers
4. The dropdown closes automatically

### Stop Timer
1. Hover over the widget
2. Expand the project list
3. Click the **currently active project** (marked with green dot ●)
4. Timer stops

## Tips & Tricks

### Positioning
- The widget appears on the right side of your screen
- You can drag it to reposition (standard window behavior)
- Position is remembered when you switch back

### Workflow
1. **Start your workday**: Login → Select project → Start timer
2. **Minimize to float**: Click the floating widget button
3. **Work freely**: The widget stays visible while you work
4. **Switch projects**: Hover → Expand → Click new project
5. **Check reports**: Restore window → View reports → Minimize again
6. **End workday**: Restore window → Stop timer → Logout

### Best Use Cases
- ✅ **Coding/Development** - Track time while working in your IDE
- ✅ **Design Work** - Keep timer visible in Photoshop/Figma
- ✅ **Research** - Track time while browsing/reading
- ✅ **Video Editing** - Monitor work time in editing software
- ✅ **Any focused work** - Maintain time awareness without distraction

## Keyboard Shortcuts (Coming Soon)

In future versions, you'll be able to:
- `Ctrl+Shift+F` - Toggle floating mode
- `Ctrl+Shift+M` - Maximize/minimize
- `Ctrl+Shift+S` - Start/stop timer from anywhere

## Troubleshooting

### Floating widget doesn't appear
- **Check**: Are you logged in?
- **Fix**: Make sure you're in the dashboard before clicking the floating button

### Can't find the floating widget
- **Check**: It might be off-screen or hidden
- **Fix**: Click the floating widget button again to reset position

### Widget not staying on top
- **Check**: Window manager permissions
- **Fix**: On macOS, grant "Screen Recording" permission in System Preferences

### Can't restore main window
- **Check**: Click the maximize icon (⛶) in the top-right
- **Fix**: If it doesn't work, restart the app

## Technical Details

### Window Management
- **Main Mode**: 800x600px, centered, normal window
- **Floating Mode**: 300x300px, always-on-top, frameless
- **Transition**: Smooth switch between modes with state preservation

### Data Persistence
- All timer data is saved automatically
- Switching modes doesn't affect running timers
- Project selections persist across mode changes

### Platform Support
- ✅ **Windows** - Fully supported
- ✅ **macOS** - Fully supported
- ✅ **Linux** - Fully supported
- ❌ **Web/Mobile** - Not supported (desktop-only feature)

## Future Enhancements

Planned features for the floating widget:
1. **Auto-minimize on start** - Option to start in floating mode
2. **Custom positioning** - Save preferred screen position
3. **Resize support** - Adjustable widget size
4. **Transparency control** - Adjust opacity
5. **Themes** - Dark mode for floating widget
6. **Hotkeys** - Global keyboard shortcuts
7. **Multiple monitors** - Choose which screen for widget
8. **Notifications** - Time alerts in floating mode

## Summary

The floating widget gives you the perfect balance between:
- 📊 **Full app** - Complete features, reports, settings
- 🎯 **Floating widget** - Minimal, focused, always-visible timer

Switch between modes seamlessly to match your workflow!

---

**Need Help?** Check the main README.md or report issues on GitHub.
