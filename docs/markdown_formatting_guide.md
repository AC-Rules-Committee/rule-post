# Markdown Formatting Guide for Rule Post

This guide explains the markdown formatting options available when writing enquiries, responses, and comments in Rule Post.

## Basic Text Formatting

### Bold Text
Use double asterisks or double underscores around text to make it **bold**.

```
**This is bold text**
__This is also bold__
```

**Result:** This is bold text

---

### Italic Text
Use single asterisks or single underscores around text to make it *italic*.

```
*This is italic text*
_This is also italic_
```

**Result:** This is italic text

---

### Bold and Italic Combined
Use three asterisks around text for ***bold and italic***.

```
***This is bold and italic***
```

**Result:** ***This is bold and italic***

---

### Inline Code
Use backticks around text to display it as `code`.

```
`const maxConcurrent = 3`
```

**Result:** `const maxConcurrent = 3`

---

## Headers

Create headers by starting a line with one or more `#` symbols followed by a space.

```
# Heading 1 (Largest)
## Heading 2
### Heading 3
#### Heading 4
##### Heading 5
###### Heading 6 (Smallest)
```

**Note:** Headers must be on their own line.

---

## Lists

### Bullet Lists
Create bullet points using `-`, `*`, or `+` followed by a space.

```
- First item
- Second item
  - Nested item (indent with spaces)
- Third item
```

**Result:**
- First item
- Second item
  - Nested item
- Third item

---

### Numbered Lists
Create numbered lists using numbers followed by a period and a space.

```
1. First step
2. Second step
3. Third step
```

**Result:**
1. First step
2. Second step
3. Third step

---

## Block Quotes

Create block quotes by starting a line with `>` followed by a space.

```
> This is a quoted statement
> It can span multiple lines
```

**Result:**
> This is a quoted statement
> It can span multiple lines

---

## Code Blocks

Create code blocks by starting a line with triple backticks. You can optionally specify the language for syntax highlighting.

````
```
Plain code block
```

```dart
// Dart code block example
void main() {
  print('Hello, World!');
}
```
````

---

## Strikethrough

Use double tildes around text to ~~strike it through~~.

```
~~This text is struck through~~
```

**Result:** ~~This text is struck through~~

---

## Tables

Create tables using pipes (`|`) to separate columns and a row of dashes to
separate the header from the body.

```
| Rule | Old Value | New Value |
| ---- | --------- | --------- |
| Subs | 45 min    | 60 min    |
| Days | Saturday  | Any day   |
```

**Result:**

| Rule | Old Value | New Value |
| ---- | --------- | --------- |
| Subs | 45 min    | 60 min    |
| Days | Saturday  | Any day   |

---

## Common Use Cases

### Highlighting Amendments or Changes
Use bold to emphasize changes:

```
The new rule should state: **"Players may substitute starting at the 60-minute mark"** instead of 45 minutes.
```

### Quoting Other Teams
Use block quotes to reference other teams' suggestions:

```
> RC suggests: "Matches must be played on Saturdays"

We propose: **"Matches can be played on any weekday"**
```

### Structured Communication
Combine formatting for clarity:

```
# Our Response

We agree with the ***proposed timeline***.

Key points:
- Point 1 with emphasis
- Point 2
- Point 3

> Original suggestion from Team A about the format

Our modification: **bold highlight of change**

Code compliance: `RULE_AMENDMENT_2024_v2`
```

---

## What's Not Supported

The following markdown features are **not** currently supported:

- ❌ Images
- ❌ Inline HTML
- ❌ Text color/styling (see below)

---

## Frequently Asked Questions

### Q: How do I change text color?

**A:** Text color is not currently supported in markdown. However, you can use **bold**, ***bold italic***, or block quotes to visually distinguish your text. 

For the common use case of distinguishing between quoted text (from other teams) and your edits:
- Use `>` blockquotes for text copied from other teams
- Use **bold** for your own edits or emphasis

See "Common Use Cases" section above for examples.

### Q: Why doesn't my bold+italic work?

**A:** Make sure you're using exactly three asterisks: `***text***`

These **won't** work:
- `**_text_**` (bold then italic separately) - renders as just italic
- `__*text*__` (bold then italic separately) - renders as just italic

This **will** work:
- `***text***` - renders as both bold and italic

### Q: Can I nest lists?

**A:** Yes! Indent nested items with spaces (usually 2-4 spaces):

```
- Outer item
  - Inner item 1
  - Inner item 2
- Outer item 2
```

### Q: Do I need to put blank lines between sections?

**A:** Generally, yes. For best results:
- Put a blank line before and after block quotes
- Put a blank line between different formatting types
- Put a blank line between header and body text

### Q: What happens with my old plain text posts?

**A:** They display exactly as before! Markdown formatting is only applied to text that contains markdown syntax. Plain text posts remain unchanged.

---

## Tips for Best Results

1. **Keep it simple** - Don't overuse formatting
2. **Use headers** to organize longer responses
3. **Use block quotes** to cite other teams
4. **Use bold** for important changes or emphasis
5. **Preview before submitting** - Consider how your formatting will look
6. **Use consistent styling** - Stick to one formatting style throughout your post

---

## Need More Help?

If you have questions about markdown formatting, check the info icon (ⓘ) next to the text input field. It shows quick syntax reminders.

