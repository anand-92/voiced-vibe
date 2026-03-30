# UI/UX Master

> **Master UI/UX design skill combining Apple HIG, modern web design, SuperDesign patterns, and universal design principles for creating exceptional interfaces across all platforms.**

[![Agent Skills Compatible](https://img.shields.io/badge/Agent%20Skills-Compatible-blue)](https://agentskills.io)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![ClawdHub](https://img.shields.io/badge/ClawdHub-Published-green)](https://clawdhub.com)

## Overview

The **UI/UX Master** skill is your comprehensive guide to designing beautiful, functional, and accessible user interfaces. It combines industry-leading design systems (Apple HIG, Material Design), modern web patterns, and universal UX principles into one powerful resource.

### Perfect For

- 🎨 **iOS/macOS Developers** - Native Apple platform design
- 🌐 **Web Designers** - Modern responsive web interfaces
- 📱 **Mobile App Developers** - Touch-first interfaces
- 💻 **Full-Stack Developers** - End-to-end UI/UX
- 🎯 **Product Designers** - Cross-platform experiences

### What You Get

✅ **Complete Apple HIG** - iOS, macOS, watchOS, tvOS, visionOS  
✅ **Modern Web Design** - Responsive, PWA, performance  
✅ **Color Systems** - oklch(), semantic colors, dark mode  
✅ **Typography** - SF fonts, web fonts, type scales  
✅ **Accessibility** - WCAG AA/AAA compliance  
✅ **Animation** - Motion principles, micro-interactions  
✅ **Component Library** - Buttons, forms, cards, navigation  
✅ **Design Trends** - Glassmorphism, Neo-brutalism  

## Features

### 🎯 Universal Coverage

**Platforms:**
- iOS & iPadOS (Touch interfaces)
- macOS (Desktop applications)
- watchOS (Glanceable interfaces)
- Web (Responsive websites & apps)
- Progressive Web Apps (PWA)

**Design Systems:**
- Apple Human Interface Guidelines
- SuperDesign patterns
- Material Design principles
- Modern web design standards

### 🎨 Comprehensive Topics

- **Color Theory** - oklch color space, palettes, contrast
- **Typography** - Font pairing, type scales, web fonts
- **Layout Systems** - CSS Grid, Flexbox, 8pt grid
- **Components** - Buttons, forms, cards, navigation, modals
- **Responsive Design** - Mobile-first, breakpoints
- **Dark Mode** - Semantic colors, elevation strategies
- **Accessibility** - WCAG compliance, screen readers
- **Animation** - Durations, easing, motion principles
- **Performance** - Optimization, lazy loading

### 💡 Practical & Actionable

- ✅ Code examples (SwiftUI, CSS, HTML)
- ✅ ASCII wireframes for planning
- ✅ Design checklists
- ✅ Quick reference tables
- ✅ Tool recommendations
- ✅ Decision guides

## Quick Start

### Installation

#### Via ClawdHub CLI
```bash
clawdhub install ui-ux-master
```

#### Manual Installation
```bash
# Clone the repository
git clone https://github.com/kdbhalala/ui-ux-master.git

# Install via Clawdbot
clawdbot skill install ./ui-ux-master
```

### Example Usage

#### Design an iOS App
```
"Design an iOS settings screen with native components"
```

The skill will provide:
- iOS navigation patterns (Tab Bar, Navigation Bar)
- Native component guidelines
- SF Symbols integration
- Dark mode support
- Accessibility compliance

#### Create a Modern Website
```
"Create a responsive landing page with glassmorphism"
```

The skill will provide:
- Mobile-first responsive layout
- Modern CSS (oklch colors, backdrop-filter)
- Performance optimization
- Accessibility guidelines
- Code examples

#### Design Accessible Forms
```
"Design an accessible form with validation"
```

The skill will provide:
- WCAG AA compliant design
- Form validation patterns
- Error message guidelines
- Keyboard navigation
- Screen reader support

## Structure

```
ui-ux-master/
├── SKILL.md                    # Main skill guide (15KB)
├── README.md                   # This file
├── LICENSE                     # MIT License
└── references/                 # Reference documentation (16 files)
    ├── apple-platforms.md      # Complete Apple HIG
    ├── apple-ios.md            # iOS patterns
    ├── apple-macos.md          # macOS patterns
    ├── apple-watchos.md        # watchOS patterns
    ├── web-design.md           # Modern web patterns
    ├── color-systems.md        # Color theory & palettes
    ├── typography.md           # Font pairing & scales
    ├── layout-patterns.md      # Grid systems & spacing
    ├── forms.md                # Form design & validation
    ├── navigation-patterns.md  # Navigation types
    ├── animation-guide.md      # Motion principles
    ├── accessibility.md        # WCAG compliance
    ├── responsive-design.md    # Responsive patterns
    ├── dark-mode.md            # Dark mode implementation
    ├── design-trends.md        # Modern trends
    └── tools-resources.md      # Design tools & libraries
```

## Documentation

### Core Guides

- [**SKILL.md**](SKILL.md) - Complete skill documentation
- [**Apple Platforms**](references/apple-platforms.md) - Apple HIG overview
- [**Web Design**](references/web-design.md) - Modern web patterns
- [**Color Systems**](references/color-systems.md) - Color theory & implementation
- [**Accessibility**](references/accessibility.md) - WCAG guidelines

### Platform-Specific

- [iOS Design Patterns](references/apple-ios.md)
- [macOS Design Patterns](references/apple-macos.md)
- [watchOS Design Patterns](references/apple-watchos.md)

### Design Systems

- [Typography Guide](references/typography.md)
- [Layout Patterns](references/layout-patterns.md)
- [Color Systems](references/color-systems.md)
- [Animation Guide](references/animation-guide.md)

## Design Philosophy

### Core Principles

**1. Clarity Over Cleverness**
- Information hierarchy is obvious
- Actions are predictable
- Feedback is immediate

**2. Consistency Breeds Familiarity**
- Patterns repeat across interface
- Terminology is uniform
- Visual language is coherent

**3. Beauty Through Simplicity**
- Every element serves a purpose
- White space creates breathing room
- Visual noise is minimized

**4. Accessibility is Non-Negotiable**
- Works for everyone
- Keyboard navigable
- Screen reader friendly
- High contrast options

## Examples

### iOS App Design
```swift
// Native iOS button with SF Symbol
Button(action: { /* action */ }) {
    Label("Save Changes", systemImage: "checkmark.circle.fill")
}
.buttonStyle(.borderedProminent)
```

### Modern Web Card
```html
<div class="card glass">
  <img src="image.jpg" alt="Description" />
  <div class="card-body">
    <h3>Card Title</h3>
    <p>Card description goes here...</p>
    <button class="btn-primary">Action</button>
  </div>
</div>
```

```css
.card.glass {
  background: rgba(255, 255, 255, 0.1);
  backdrop-filter: blur(10px);
  border-radius: 12px;
  border: 1px solid rgba(255, 255, 255, 0.2);
}
```

### Accessible Form
```html
<form>
  <div class="form-group">
    <label for="email">Email Address</label>
    <input 
      type="email" 
      id="email" 
      name="email"
      aria-required="true"
      aria-describedby="email-help"
    />
    <small id="email-help">We'll never share your email.</small>
  </div>
  <button type="submit">Submit</button>
</form>
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

### Guidelines

1. Follow the existing structure and format
2. Add practical examples and code snippets
3. Ensure accessibility compliance
4. Test on multiple platforms
5. Update documentation

### Areas for Contribution

- Additional platform patterns
- More code examples
- Design tool integrations
- Community best practices
- Accessibility improvements

## Resources

### Official Guidelines
- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines)
- [Material Design](https://material.io/design)
- [WCAG Guidelines](https://www.w3.org/WAI/WCAG21/quickref/)

### Tools
- **Design:** Figma, Sketch, Adobe XD
- **Icons:** SF Symbols, Lucide, Heroicons
- **Colors:** oklch.com, coolors.co, contrast-ratio.com
- **Fonts:** Google Fonts, Adobe Fonts

### Communities
- [Agent Skills](https://agentskills.io)
- [ClawdHub](https://clawdhub.com)
- [Designer News](https://www.designernews.co)
- [Dribbble](https://dribbble.com)

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Credits

Created with ❤️ by the Clawdbot community.

Built on top of:
- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines)
- [SuperDesign](https://superdesign.dev) patterns
- Modern web design principles
- Universal UX best practices

## Support

- **Issues:** [GitHub Issues](https://github.com/kdbhalala/ui-ux-master/issues)
- **Discussions:** [GitHub Discussions](https://github.com/kdbhalala/ui-ux-master/discussions)
- **ClawdHub:** [ClawdHub Page](https://clawdhub.com/skills/ui-ux-master)

---

**Made for [Agent Skills](https://agentskills.io) | Compatible with [Clawdbot](https://clawd.bot)**
