# Contributing to UI/UX Master

Thank you for your interest in contributing to UI/UX Master! This document provides guidelines for contributing to the project.

## How to Contribute

### Reporting Issues

If you find a bug or have a suggestion:

1. Check if the issue already exists in [GitHub Issues](https://github.com/kdbhalala/ui-ux-master/issues)
2. If not, create a new issue with:
   - Clear, descriptive title
   - Detailed description
   - Steps to reproduce (for bugs)
   - Expected vs actual behavior
   - Screenshots (if applicable)

### Suggesting Enhancements

We welcome suggestions for:
- Additional platform patterns
- New design examples
- Tool integrations
- Documentation improvements
- Code examples

Create an issue with the `enhancement` label.

### Pull Requests

1. **Fork the repository**
   ```bash
   git clone https://github.com/kdbhalala/ui-ux-master.git
   cd ui-ux-master
   ```

2. **Create a branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Make your changes**
   - Follow the existing structure and style
   - Add practical examples
   - Update documentation
   - Test thoroughly

4. **Commit your changes**
   ```bash
   git add .
   git commit -m "Add: Brief description of changes"
   ```

5. **Push and create PR**
   ```bash
   git push origin feature/your-feature-name
   ```

## Guidelines

### Documentation Style

- **Clear and concise** - Get to the point quickly
- **Practical examples** - Show, don't just tell
- **Code snippets** - Provide working examples
- **Accessibility-first** - Always consider a11y
- **Platform-aware** - Respect platform conventions

### File Structure

```
ui-ux-master/
├── SKILL.md              # Main guide (keep < 20KB)
├── README.md             # Overview and quick start
└── references/           # Deep dive documentation
    ├── topic.md          # Focused, single-topic files
    └── ...
```

### Writing Guidelines

**Do:**
- ✅ Use clear headings and structure
- ✅ Provide code examples
- ✅ Include visual examples (ASCII art, code)
- ✅ Follow WCAG accessibility guidelines
- ✅ Test on multiple platforms
- ✅ Link to official documentation
- ✅ Use semantic markdown

**Don't:**
- ❌ Make assumptions about user knowledge
- ❌ Use jargon without explanation
- ❌ Ignore accessibility
- ❌ Copy-paste without attribution
- ❌ Add content without examples

### Code Examples

**SwiftUI (iOS/macOS):**
```swift
// Clear, working examples
Button("Save") {
    // Action
}
.buttonStyle(.borderedProminent)
```

**CSS/HTML (Web):**
```css
/* Well-commented examples */
.component {
  /* Modern CSS properties */
  display: grid;
  gap: 16px;
}
```

### Commit Messages

Follow conventional commits:

- `Add: New feature or content`
- `Fix: Bug fix or correction`
- `Update: Content update or improvement`
- `Docs: Documentation only`
- `Refactor: Code restructuring`
- `Test: Testing additions`

Examples:
```
Add: iOS 18 widget patterns
Fix: Color contrast ratio calculation
Update: Typography scale for iPadOS
Docs: Add responsive design examples
```

## Areas for Contribution

### High Priority
- [ ] Android design patterns
- [ ] Windows design guidelines
- [ ] More code examples (React, Vue, Angular)
- [ ] Design system templates
- [ ] Accessibility testing guides

### Medium Priority
- [ ] Video tutorials
- [ ] Interactive examples
- [ ] Figma/Sketch templates
- [ ] Component playground
- [ ] Design system generator

### Enhancement Ideas
- [ ] Community showcase
- [ ] Real-world case studies
- [ ] Performance benchmarks
- [ ] A/B testing guidelines
- [ ] Localization patterns

## Review Process

1. **Submission** - Create PR with clear description
2. **Initial Review** - Maintainers review within 48 hours
3. **Feedback** - Address comments and suggestions
4. **Approval** - Two maintainer approvals required
5. **Merge** - Squash and merge to main

## Code of Conduct

### Our Standards

- **Be respectful** - Treat everyone with respect
- **Be constructive** - Provide helpful feedback
- **Be inclusive** - Welcome diverse perspectives
- **Be professional** - Keep discussions on-topic

### Unacceptable Behavior

- Harassment or discrimination
- Trolling or insulting comments
- Personal attacks
- Spam or off-topic content

## Getting Help

- **Questions:** [GitHub Discussions](https://github.com/kdbhalala/ui-ux-master/discussions)
- **Bugs:** [GitHub Issues](https://github.com/kdbhalala/ui-ux-master/issues)
- **Chat:** [Discord Server](#) (if available)

## Recognition

Contributors will be:
- Listed in CONTRIBUTORS.md
- Mentioned in release notes
- Credited in documentation

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

Thank you for making UI/UX Master better! 🎨
