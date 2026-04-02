// flutter_app/lib/content/widgets/detail_scaffold.dart
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:web/web.dart' as web;

import 'package:rule_post/content/widgets/header_block.dart';
import 'package:rule_post/content/widgets/section_card.dart';
import 'package:rule_post/content/widgets/status_card.dart';

// Used in the enquiry and response detail pages
class DetailScaffold extends StatelessWidget {
  const DetailScaffold({
    super.key,
    required this.headerLines,
    this.meta,
    this.subHeaderLines = const <String>[],
    this.headerButton,
    this.headerColour,
    this.summary,
    this.summaryText,
    this.commentary,
    this.commentaryText,
    this.attachments = const <Widget>[],
    this.footer,
    this.adminPanel,
    this.stageMap,
  });

  final List<String> headerLines;
  final List<String> subHeaderLines;
  final Widget? headerButton;
  final Color?
  headerColour; // allows the header to be coloured by author (for responses)
  final Widget? meta; // usually MetaChips (+ optional status chips)
  final Widget? summary; // null => hide section
  final String? summaryText; // raw markdown for clipboard
  final Widget? commentary; // null => hide section
  final String? commentaryText; // raw markdown for clipboard
  final List<Widget> attachments; // empty => hide section
  final Widget? footer; // usually Children card; null => hide
  final Widget? adminPanel; // only shows for admins; null => hide
  final Map<String, dynamic>?
  stageMap; // isOpen, teamsCanRespond, teamsCanComment, stageStarts, stageEnds

  @override
  Widget build(BuildContext context) {
    // final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // HEADER CARD
          SectionCard(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
            backgroundColor: headerColour,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: title(s) + trailing actions
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: HeaderBlock(
                        headerLines: headerLines,
                        subHeaderLines: subHeaderLines,
                        trailing: headerButton,
                      ),
                    ),
                  ],
                ),
                if (meta is Wrap && (meta as Wrap).children.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  meta!,
                ],
              ],
            ),
          ),

          // STAGE CARD (optional)
          if (stageMap != null &&
              stageMap!['isOpen'] &&
              stageMap!['isPublished']) ...[
            const SizedBox(height: 12),
            SectionCard(
              title: 'Enquiry Stage',
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: StatusCard(stageMap: stageMap!),
              ),
            ),
          ],

          // SUMMARY CARD (optional)
          if (summary != null) ...[
            const SizedBox(height: 12),
            SectionCard(
              title: 'Summary',
              trailing: summaryText != null && summaryText!.isNotEmpty
                  ? _CopyButtons(text: summaryText!)
                  : null,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: summary!,
              ),
            ),
          ],

          // DETAILS CARD (optional)
          if (commentary != null) ...[
            const SizedBox(height: 12),
            SectionCard(
              title: 'Details',
              trailing: commentaryText != null && commentaryText!.isNotEmpty
                  ? _CopyButtons(text: commentaryText!)
                  : null,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: commentary!,
              ),
            ),
          ],

          // ATTACHMENTS CARD (optional)
          if (attachments.isNotEmpty) ...[
            const SizedBox(height: 12),
            SectionCard(
              title: 'Attachments',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final w in attachments)
                    Padding(padding: const EdgeInsets.only(top: 8), child: w),
                ],
              ),
            ),
          ],

          // FOOTER (usually children section card)
          if (footer != null) ...[const SizedBox(height: 12), footer!],

          // ADMIN PANEL
          if (adminPanel != null) ...[
            const SizedBox(height: 12),
            adminPanel!,
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _CopyButtons extends StatelessWidget {
  const _CopyButtons({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.copy, size: 18),
          tooltip: 'Copy markdown',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: text));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Markdown copied to clipboard'),
                duration: Duration(seconds: 2),
              ),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.copy_all, size: 18),
          tooltip: 'Copy as rich text',
          onPressed: () => _copyAsHtml(context, text),
        ),
      ],
    );
  }

  void _copyAsHtml(BuildContext context, String markdown) {
    final rawHtml = md.markdownToHtml(markdown);
    // Wrap with inline styles so headings survive paste into Word/Google Docs.
    final html =
        '<div style="font-family:Calibri,sans-serif;font-size:11pt;">'
        '$rawHtml</div>'
        '<style>'
        'h1{font-size:20pt;font-weight:bold;}'
        'h2{font-size:16pt;font-weight:bold;}'
        'h3{font-size:13pt;font-weight:bold;}'
        'h4{font-size:11pt;font-weight:bold;}'
        '</style>';
    final htmlBlob = web.Blob(
      [html.toJS].toJS,
      web.BlobPropertyBag(type: 'text/html'),
    );
    final textBlob = web.Blob(
      [markdown.toJS].toJS,
      web.BlobPropertyBag(type: 'text/plain'),
    );
    final item = web.ClipboardItem(
      {'text/html': htmlBlob, 'text/plain': textBlob}.jsify() as JSObject,
    );
    web.window.navigator.clipboard.write([item].toJS);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Rich text copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}
