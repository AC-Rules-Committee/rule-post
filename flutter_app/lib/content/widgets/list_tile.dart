// flutter_app/lib/content/widgets/list_tile.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

// special tile for comments, which can be expanded/collapsed if the text is long
class ListTileCollapsibleText extends StatefulWidget {
  const ListTileCollapsibleText(
    this.text, {
    super.key,
    this.maxLines = 3,
    this.contentPadding = const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 12,
    ),
    this.tileColor,
    this.sideWidget,
  });

  final String text;
  final int maxLines;
  final EdgeInsetsGeometry contentPadding;
  final Color? tileColor;
  final Widget? sideWidget;

  @override
  State<ListTileCollapsibleText> createState() =>
      _ListTileCollapsibleTextState();
}

class _ListTileCollapsibleTextState extends State<ListTileCollapsibleText>
    with TickerProviderStateMixin {
  bool _expanded = false;
  bool _overflows = false;

  void _checkOverflow(
    BoxConstraints c,
    TextStyle style,
    TextDirection dir,
    EdgeInsets resolvedPad,
  ) {
    final maxWidth = c.maxWidth - resolvedPad.horizontal;
    final tp = TextPainter(
      text: TextSpan(text: widget.text, style: style),
      maxLines: widget.maxLines,
      textDirection: dir,
    )..layout(maxWidth: maxWidth > 0 ? maxWidth : 0);
    _overflows = tp.didExceedMaxLines;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final listTileTheme = ListTileTheme.of(context);
    final dir = Directionality.of(context);
    final textStyle = theme.textTheme.bodyMedium!;
    final iconColor = listTileTheme.iconColor ?? theme.iconTheme.color;
    final resolvedPad = widget.contentPadding.resolve(dir);

    return LayoutBuilder(
      builder: (context, constraints) {
        _checkOverflow(constraints, textStyle, dir, resolvedPad);

        return Material(
          color: widget.tileColor ?? Colors.transparent,
          child: InkWell(
            onTap: _overflows
                ? () => setState(() => _expanded = !_expanded)
                : null,
            overlayColor: WidgetStateProperty.resolveWith((states) {
              final base = theme.colorScheme.onSurface;
              if (states.contains(WidgetState.pressed) ||
                  states.contains(WidgetState.focused)) {
                return base.withValues(alpha: 0.12);
              }
              if (states.contains(WidgetState.hovered)) {
                return base.withValues(alpha: 0.04);
              }
              return null;
            }),
            child: Padding(
              padding: resolvedPad,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: AnimatedSize(
                          duration: const Duration(milliseconds: 160),
                          alignment: Alignment.topLeft,
                          child: _buildTextContent(
                            widget.text,
                            textStyle,
                            _expanded ? null : widget.maxLines,
                            _expanded
                                ? TextOverflow.visible
                                : TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (widget.sideWidget != null)
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 240),
                          child: widget.sideWidget!,
                        ),
                    ],
                  ),

                  if (_overflows) ...[
                    // One row under the main content:
                    // - left side: "…" hint that not all text is showing
                    // - right side: chevron button for expanding/collapsing tile
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Collapsed hint on the left (only when collapsed + enabled)
                        if (!_expanded)
                          Expanded(
                            child: Text(
                              "…",
                              style: textStyle.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          )
                        else
                          const Spacer(),

                        InkWell(
                          onTap: () => setState(() => _expanded = !_expanded),
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: AnimatedRotation(
                              duration: const Duration(milliseconds: 160),
                              turns: _expanded ? 0.5 : 0.0,
                              child: Icon(
                                Icons.expand_more,
                                size: 24,
                                color: iconColor,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  Semantics(
                    button: true,
                    expanded: _expanded,
                    label: _expanded ? 'Collapse' : 'Expand',
                    child: const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Build markdown-aware text content
  /// Renders markdown if detected, otherwise shows plain text
  Widget _buildTextContent(
    String text,
    TextStyle baseStyle,
    int? maxLines,
    TextOverflow overflow,
  ) {
    // Quick check for markdown
    if (_containsMarkdown(text)) {
      // For collapsed view, just show plain text truncated
      if (!_expanded && maxLines != null) {
        return Text(
          text,
          style: baseStyle,
          maxLines: maxLines,
          overflow: overflow,
        );
      }
      // For expanded view, keep markdown link taps working and add text
      // selection around the rendered content so users can copy text.
      final markdown = MarkdownBody(
        data: text,
        selectable: false,
        shrinkWrap: true,
        extensionSet: md.ExtensionSet.gitHubFlavored,
        styleSheet: _buildMarkdownStyle(baseStyle),
        onTapLink: (textLabel, href, title) async {
          if (href == null) return;
          final uri = Uri.tryParse(href);
          if (uri == null) return;
          try {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } catch (_) {
            // ignore failures for now
          }
        },
      );

      return SelectionArea(child: markdown);
    }

    // No markdown, render as plain text
    return Text(text, style: baseStyle, maxLines: maxLines, overflow: overflow);
  }

  /// Build markdown style sheet matching the tile's text style
  MarkdownStyleSheet _buildMarkdownStyle(TextStyle baseStyle) {
    return MarkdownStyleSheet(
      p: baseStyle,
      em: baseStyle.copyWith(fontStyle: FontStyle.italic),
      strong: baseStyle.copyWith(fontWeight: FontWeight.bold),
      del: baseStyle.copyWith(decoration: TextDecoration.lineThrough),
      code: baseStyle.copyWith(
        fontFamily: 'monospace',
        fontSize: baseStyle.fontSize != null ? baseStyle.fontSize! * 0.9 : null,
      ),
    );
  }

  /// Check if text contains markdown syntax
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

String _fmt(DateTime? dt) {
  if (dt == null) return '';
  // Show in local time with short readable format
  return '${dt.day.toString().padLeft(2, '0')} '
      '${_month(dt.month)} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

String _month(int m) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return months[m - 1];
}

DateTime? _asLocal(dynamic v) {
  if (v == null) return null;

  DateTime asUtc;
  if (v is DateTime) {
    asUtc = v.isUtc ? v : v.toUtc();
  } else if (v is Timestamp) {
    asUtc = v.toDate().toUtc();
  } else if (v is int) {
    asUtc = DateTime.fromMillisecondsSinceEpoch(v, isUtc: true);
  } else if (v is String) {
    asUtc = DateTime.parse(v).toUtc(); // expects ISO-8601
  } else {
    throw ArgumentError('Unsupported date type: ${v.runtimeType}');
  }
  return asUtc.toLocal(); // ← device/browser local time zone
}

Widget publishedAtSideWidget(dynamic publishedAt) {
  final dt = _asLocal(publishedAt);
  if (dt == null) return const SizedBox.shrink();

  return Text(
    _fmt(dt),
    style: const TextStyle(fontSize: 12, color: Colors.grey),
    textAlign: TextAlign.right,
  );
}
