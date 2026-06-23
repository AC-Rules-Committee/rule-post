// flutter_app/lib/core/widgets/markdown_display.dart
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

/// A widget that displays text as rendered markdown.
/// Supports: **bold**, _italic_, `code`, # Headers, - lists, and links.
///
/// This widget is used throughout the app to render rich text content
/// that was entered by users as markdown.
class MarkdownDisplay extends StatelessWidget {
  const MarkdownDisplay(
    this.text, {
    super.key,
    this.selectable = true,
    this.maxLines,
  });

  /// The markdown text to display
  final String text;

  /// Whether the text should be selectable
  final bool selectable;

  /// Maximum number of lines to display (null = no limit)
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    // Return plain text if empty
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    // For simple content without markdown, return as SelectableText
    // This handles the common case of plain text content
    if (!_containsMarkdown(text)) {
      if (selectable) {
        return SelectableText(text, maxLines: maxLines);
      } else {
        return Text(
          text,
          maxLines: maxLines,
          overflow: maxLines != null ? TextOverflow.ellipsis : null,
        );
      }
    }

    // Use MarkdownBody for markdown content. Provide an onTapLink handler
    // so links are actionable. We open links externally via url_launcher.
    final markdown = MarkdownBody(
      data: text,
      // Keep MarkdownBody itself non-selectable so link gesture recognizers
      // continue to fire, then opt into copy support with SelectionArea.
      selectable: false,
      shrinkWrap: true,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      styleSheet: _buildStyleSheet(context),
      onTapLink: (textLabel, href, title) async {
        if (href == null) return;
        final uri = Uri.tryParse(href);
        if (uri == null) return;
        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (_) {
          // ignore failures - caller can add error reporting if desired
        }
      },
    );

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: selectable ? SelectionArea(child: markdown) : markdown,
    );
  }

  /// Build a markdown style sheet that matches the app theme
  MarkdownStyleSheet _buildStyleSheet(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return MarkdownStyleSheet(
      p: textTheme.bodyMedium ?? const TextStyle(),
      h1:
          textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold) ??
          const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      h2:
          textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold) ??
          const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      h3:
          textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold) ??
          const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      h4:
          textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold) ??
          const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      h5:
          textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold) ??
          const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
      h6:
          textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold) ??
          const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      em:
          textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic) ??
          const TextStyle(fontStyle: FontStyle.italic),
      strong:
          textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold) ??
          const TextStyle(fontWeight: FontWeight.bold),
      del:
          textTheme.bodyMedium?.copyWith(
            decoration: TextDecoration.lineThrough,
          ) ??
          const TextStyle(decoration: TextDecoration.lineThrough),
      code: TextStyle(
        fontFamily: 'monospace',
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        color: theme.colorScheme.onSurface,
        fontSize: (textTheme.bodyMedium?.fontSize ?? 14) * 0.9,
      ),
      codeblockDecoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      codeblockPadding: const EdgeInsets.all(12),
      blockquote: TextStyle(
        color: theme.colorScheme.onSurfaceVariant,
        fontStyle: FontStyle.italic,
      ),
      blockquoteDecoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          left: BorderSide(color: theme.colorScheme.outlineVariant, width: 4),
        ),
      ),
      blockquotePadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      listBullet: textTheme.bodyMedium ?? const TextStyle(),
      a:
          textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.primary,
            decoration: TextDecoration.underline,
          ) ??
          TextStyle(
            color: theme.colorScheme.primary,
            decoration: TextDecoration.underline,
          ),
    );
  }

  /// Quick check if text contains markdown syntax
  static bool _containsMarkdown(String text) {
    final markdownPatterns = [
      RegExp(r'\*\*\*.+?\*\*\*'), // ***bold+italic***
      RegExp(r'\*\*.+?\*\*'), // **bold**
      RegExp(r'__.+?__'), // __bold__
      RegExp(r'\*.+?\*'), // *italic*
      RegExp(r'_.+?_'), // _italic_
      RegExp(r'`[^`]+`'), // `code`
      RegExp(r'^#+\s'), // # Headers
      RegExp(r'^\s*[-*+]\s'), // - lists
      RegExp(r'^\s*\d+\.\s'), // 1. numbered lists
      RegExp(r'>.+'), // > blockquotes
      RegExp(r'~~.+?~~'), // ~~strikethrough~~
      RegExp(
        r'^(?=.*\|)(?=.*-)[\s|:-]+$',
        multiLine: true,
      ), // | table | delimiter row
      RegExp(r'https?:\/\/\S+'), // bare URLs like https://example.com
    ];

    return markdownPatterns.any((pattern) => pattern.hasMatch(text));
  }
}
