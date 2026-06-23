//flutter_app/lib/content/widgets/post_buttons.dart
import 'dart:async';
import 'dart:io' show File;
import 'package:file_picker/file_picker.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web/web.dart' as web;

import 'package:rule_post/api/post_apis.dart';
import 'package:rule_post/core/models/attachments.dart';
import 'package:rule_post/core/models/post_payloads.dart';
import 'package:rule_post/core/models/post_types.dart';
import 'package:rule_post/core/models/types.dart' show NewPostPayload;
import 'package:rule_post/riverpod/user_detail.dart';

/// Used to create a new post, will be unpublished until scheduled function runs
class NewPostButton extends ConsumerStatefulWidget {
  const NewPostButton({
    super.key,
    required this.type,
    this.parentIds,
    this.isLocked = false,
    this.lockedReason,
    this.edit = false,
  });

  final PostType type;
  final List<String>? parentIds;
  final bool isLocked;
  final String? lockedReason;
  final bool edit;

  @override
  ConsumerState<NewPostButton> createState() => _NewPostButtonState();
}

class _NewPostButtonState extends ConsumerState<NewPostButton> {
  final _tooltipKey = GlobalKey<TooltipState>();

  @override
  Widget build(BuildContext context) {
    final locked = widget.isLocked;
    const labelText = 'New';

    final scheme = Theme.of(context).colorScheme;
    final bg = scheme.primary;
    final fg = scheme.onPrimary;

    // Dimmed look when locked (keeps theme hue, lowers alpha only).
    final bgColor = locked ? bg.withValues(alpha: 0.55) : bg;
    final fgColor = locked ? fg.withValues(alpha: 0.55) : fg;

    return Semantics(
      button: true,
      enabled: !locked,
      label: locked && widget.lockedReason != null
          ? 'New (locked — ${widget.lockedReason})'
          : 'New',
      child: Tooltip(
        key: _tooltipKey,
        triggerMode:
            TooltipTriggerMode.longPress, // hover still works on desktop
        message: locked
            ? (widget.lockedReason ?? 'This action is currently locked.')
            : 'Create a new ${widget.type.singular}',
        child: FilledButton.icon(
          style: ButtonStyle(
            backgroundColor: WidgetStatePropertyAll(bgColor),
            foregroundColor: WidgetStatePropertyAll(fgColor),
            overlayColor: WidgetStatePropertyAll(
              locked
                  ? scheme.onSurface.withValues(alpha: 0.04)
                  : scheme.primary.withValues(alpha: 0.08),
            ),
          ),
          icon: Icon(locked ? Icons.lock_outline : Icons.add, color: fgColor),
          label: const Text(labelText),
          onPressed: () async {
            if (locked) {
              final s = _tooltipKey.currentState;
              if (s is TooltipState) s.ensureTooltipVisible();
              return;
            }

            final payload = await showDialog<NewPostPayload>(
              context: context,
              builder: (_) => NewPostDialog(
                dialogTitle: 'New ${widget.type.singular}',
                tempFolder: widget.type.tempFolder,
                postType: widget.type.singular,
              ),
            );
            if (payload == null) return;
            if (!context.mounted) return;

            final createPostPayload = PostPayload(
              postType: widget.type,
              title: payload.title,
              postText: payload.text,
              attachments: payload.attachments,
              parentIds: widget.parentIds,
              closeEnquiryOnPublish: payload.closeEnquiryOnPublish,
              enquiryConclusion: payload.enquiryConclusion,
            );

            if (!context.mounted) return;
            await createPost(context, createPostPayload);
          },
        ),
      ),
    );
  }
}

class NewPostDialog extends ConsumerStatefulWidget {
  const NewPostDialog({
    super.key,
    required this.dialogTitle,
    required this.tempFolder,
    required this.postType,

    this.initialTitle,
    this.initialText,
    this.initialAttachments,
    this.initialCloseEnquiryOnPublish = false,
    this.initialEnquiryConclusion,
  });

  final String dialogTitle;
  final String tempFolder;
  final String postType;

  final String? initialTitle;
  final String? initialText;
  final List<TempAttachment>? initialAttachments;
  final bool initialCloseEnquiryOnPublish;
  final String?
  initialEnquiryConclusion; // "amendment", "interpretation", "noResult" or null

  @override
  ConsumerState<NewPostDialog> createState() => _NewPostDialogState();
}

class _NewPostDialogState extends ConsumerState<NewPostDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _text;
  late final List<TempAttachment> _pending;
  bool _busy = false;
  bool _uploading = false;
  bool _closeEnquiryOnPublish = false;
  String? _enquiryConclusion; // "amendment", "interpretation", "noResult"
  final Map<String, double> _fileProgress = {}; // key = file path or name
  double get _aggregateProgress => _fileProgress.isEmpty
      ? 0
      : _fileProgress.values.reduce((a, b) => a + b) / _fileProgress.length;

  @override
  void initState() {
    super.initState();

    _title = TextEditingController(text: widget.initialTitle ?? '');
    _text = TextEditingController(text: widget.initialText ?? '');

    _pending = [...(widget.initialAttachments ?? const [])];
    _closeEnquiryOnPublish = widget.initialCloseEnquiryOnPublish;
    _enquiryConclusion = widget.initialEnquiryConclusion;
  }

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = !_busy && !_uploading;

    // Show closure option only for RC users posting a response (not comment) or enquiry edits with conclusion
    final userTeam = ref.watch(teamProvider);
    final isRC = userTeam == 'RC';
    final isResponsePost = widget.postType == 'response';
    final showCloseOption = isRC && isResponsePost;

    return AlertDialog(
      title: Text(widget.dialogTitle),
      content: SizedBox(
        width: (MediaQuery.of(context).size.width * 0.85).clamp(300.0, 800.0),
        child: Form(
          key: _form,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.postType != 'comment') ...[
                    TextFormField(
                      controller: _title,
                      decoration: InputDecoration(
                        labelText: widget.postType == 'enquiry'
                            ? 'Title'
                            : 'Summary (optional)',
                      ),
                      validator: (v) =>
                          ((widget.postType == 'enquiry') &&
                              (v == null || v.trim().isEmpty))
                          ? 'Title is required'
                          : null,
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _text,
                    decoration: InputDecoration(
                      labelText: widget.postType == 'comment'
                          ? 'Comment'
                          : 'Details',
                      suffixIcon: _buildTextFieldSuffixIcon(),
                      helperText:
                          'Markdown formatting is supported: **bold**, _italic_, `code`, etc.',
                      helperMaxLines: 2,
                    ),
                    maxLines: null,
                    minLines: 2,
                    expands: false,
                    validator: (v) =>
                        ((widget.postType == 'comment') &&
                            (v == null || v.trim().isEmpty))
                        ? 'Content is required'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  if (showCloseOption) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Tooltip(
                        message:
                            'When published, this response will close the enquiry and prevent further submissions',
                        child: CheckboxListTile(
                          value: _closeEnquiryOnPublish,
                          onChanged: (val) => setState(
                            () => _closeEnquiryOnPublish = val ?? false,
                          ),
                          title: const Text('Close enquiry?'),
                          contentPadding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_closeEnquiryOnPublish) ...[
                      DropdownButtonFormField<String>(
                        initialValue: _enquiryConclusion,
                        items: const [
                          DropdownMenuItem(
                            value: "amendment",
                            child: Text('Amendment'),
                          ),
                          DropdownMenuItem(
                            value: "interpretation",
                            child: Text('Interpretation'),
                          ),
                          DropdownMenuItem(
                            value: "noResult",
                            child: Text('No result'),
                          ),
                        ],
                        onChanged: (val) =>
                            setState(() => _enquiryConclusion = val),
                        decoration: const InputDecoration(
                          labelText: 'How did this enquiry conclude?',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => _closeEnquiryOnPublish && v == null
                            ? 'Select a conclusion type'
                            : null,
                      ),
                      const SizedBox(height: 16),
                    ],
                  ],
                  if (widget.postType != 'comment') ...[
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: _uploading ? null : _addAttachmentToTemp,
                          icon: const Icon(Icons.attach_file),
                          label: const Text('Add attachment'),
                        ),
                        const Spacer(),
                        Tooltip(
                          message:
                              'Note: large attachments may take a minute or two to upload',
                          child: Icon(
                            Icons.info_outline,
                            size: 18,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_uploading) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: _aggregateProgress == 0
                            ? null
                            : _aggregateProgress,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _fileProgress.isEmpty
                            ? 'Preparing uploads...'
                            : 'Uploading ${_fileProgress.length} file(s): ${(100 * _aggregateProgress).toStringAsFixed(0)}%',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                  if (_pending.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _pending
                            .map(
                              (a) => InputChip(
                                label: Text(a.name),
                                onDeleted: () =>
                                    setState(() => _pending.remove(a)),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: canSubmit
              ? () async {
                  if (!(_form.currentState?.validate() ?? false)) return;
                  if (widget.postType == 'enquiry' &&
                      _text.text.trim().isEmpty &&
                      _pending.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('No details or attachments provided.'),
                      ),
                    );
                    return;
                  }
                  if (widget.postType == 'response' &&
                      _title.text.trim().isEmpty &&
                      _text.text.trim().isEmpty &&
                      _pending.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('No input provided.')),
                    );
                    return;
                  }
                  setState(() => _busy = true);
                  if (context.mounted) {
                    Navigator.pop(
                      context,
                      NewPostPayload(
                        title: _title.text.trim(),
                        text: _text.text.trim(),
                        attachments: _pending.toList(),
                        closeEnquiryOnPublish: _closeEnquiryOnPublish,
                        enquiryConclusion: _enquiryConclusion,
                      ),
                    );
                  }
                }
              : null,
          child: _busy
              ? const CircularProgressIndicator()
              : Text(
                  widget.initialTitle != null || widget.initialText != null
                      ? 'Save changes'
                      : 'Create',
                ),
        ),
      ],
    );
  }

  Future<void> _addAttachmentToTemp() async {
    if (_uploading) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _toast('You must be signed in to add attachments.');
      return;
    }

    try {
      // Don’t await anything before opening the picker
      List<web.File>? webFiles;

      if (kIsWeb) {
        webFiles = await _pickWebFiles(
          accept: '.pdf,.doc,.docx',
          multiple: true,
        );
      } else {
        // Non-web fallback keeps your old plugin flow
        final picked = await FilePicker.platform.pickFiles(
          allowMultiple: true,
          withData: true,
          type: FileType.custom,
          allowedExtensions: ['pdf', 'doc', 'docx'],
        );
        if (picked == null || picked.files.isEmpty) return;

        // If you ever target mobile/desktop again, this will be used.
        setState(() => _uploading = true);
        int success = 0;
        final errors = <String>[];
        for (final f in picked.files) {
          try {
            await _uploadOneFile(uid, f);
            success++;
          } catch (e) {
            errors.add('${f.name}: $e');
          }
        }
        if (success > 0)
          _toast('Uploaded $success file${success == 1 ? '' : 's'}.');
        if (errors.isNotEmpty)
          _toast('Some files failed:\n${errors.join('\n')}');
        return;
      }

      // User canceled or no files selected
      if (webFiles == null || webFiles.isEmpty) return;

      // Now it’s safe to set uploading + do any warm-ups concurrently
      setState(() => _uploading = true);
      // Fire and forget App Check warm-up (don’t break user gesture earlier)
      unawaited(FirebaseAppCheck.instance.getToken(true));

      // Bounded concurrency
      const maxConcurrent = 3;
      int success = 0;
      final errors = <String>[];

      void onProgress(String key, int sent, int total) {
        setState(() {
          _fileProgress[key] = total == 0 ? 0 : sent / total;
        });
      }

      try {
        for (var i = 0; i < webFiles.length; i += maxConcurrent) {
          final batch = webFiles.sublist(
            i,
            (i + maxConcurrent > webFiles.length)
                ? webFiles.length
                : i + maxConcurrent,
          );

          await Future.wait(
            batch.map((f) async {
              try {
                await _uploadOneWebBlobWithProgress(
                  uid,
                  f,
                  onProgress: onProgress,
                );
                success++;
              } catch (e) {
                errors.add('${f.name}: $e');
              }
            }),
          );
        }

        if (success > 0)
          _toast('Uploaded $success file${success == 1 ? '' : 's'}.');
        if (errors.isNotEmpty)
          _toast('Some files failed:\n${errors.join('\n')}');
      } finally {
        // Clear progress + uploading flag
        setState(() {
          _uploading = false;
          _fileProgress.clear();
        });
      }

      if (success > 0)
        _toast('Uploaded $success file${success == 1 ? '' : 's'}.');
      if (errors.isNotEmpty) _toast('Some files failed:\n${errors.join('\n')}');
    } catch (e) {
      _toast('Attachment failed: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<List<web.File>?> _pickWebFiles({
    String accept = '',
    bool multiple = true,
  }) async {
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..accept = accept
      ..multiple = multiple
      ..style.display = 'none'; // keep it invisible

    // Must be in DOM for some browsers
    web.document.body?.append(input);

    // Synchronously trigger the dialog — no awaits before this
    input.click();

    // Wait for user selection
    await input.onChange.first;

    final list = <web.File>[];
    final files = input.files;
    if (files != null) {
      final len = files.length;
      for (var i = 0; i < len; i++) {
        final f = files.item(i);
        if (f != null) list.add(f);
      }
    }

    input.remove();
    return list.isEmpty ? null : list;
  }

  /// Build suffix icon for text field showing markdown formatting help
  Widget? _buildTextFieldSuffixIcon() {
    return Tooltip(
      message:
          'Markdown formatting supported:\n'
          '**bold**, _italic_, ***bold+italic***, ~~strikethrough~~,\n'
          '`code`, # Headers, - lists, > quotes, tables',
      showDuration: const Duration(seconds: 5),
      child: Icon(Icons.info_outline, size: 18),
    );
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  String _sanitiseName(String name) => name
      .replaceAll(RegExp(r'[^\w.\-+]'), '_')
      .substring(0, name.length.clamp(0, 200));

  String? _guessContentType(String ext) {
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'doc':
        return 'application/msword';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'txt':
        return 'text/plain';
      default:
        return null;
    }
  }

  Future<void> _uploadOneFile(String uid, PlatformFile f) async {
    final bytes = f.bytes; // present on web (withData: true)
    final path = f.path; // present on mobile/desktop
    if (bytes == null && (path == null || path.isEmpty)) {
      throw 'Could not read file bytes or path.';
    }

    final name = f.name;
    final size = f.size;
    final ext = (f.extension ?? '').toLowerCase();
    final contentType = _guessContentType(ext) ?? 'application/octet-stream';

    final ts = DateTime.now().millisecondsSinceEpoch;
    final safeName = _sanitiseName(name);
    final tempPath = '${widget.tempFolder}/$uid/$ts-$safeName';

    final ref = FirebaseStorage.instance.ref(tempPath);

    if (kIsWeb || bytes != null) {
      await ref.putData(bytes!, SettableMetadata(contentType: contentType));
    } else {
      await ref.putFile(
        File(path!),
        SettableMetadata(contentType: contentType),
      );
    }

    _pending.add(
      TempAttachment(
        name: name,
        storagePath: tempPath,
        size: size,
        contentType: contentType,
      ),
    );
  }

  Future<void> _uploadOneWebBlobWithProgress(
    String uid,
    web.File f, {
    required void Function(String key, int sent, int total) onProgress,
  }) async {
    final name = f.name;
    final size = f.size;
    final browserType = f.type.isNotEmpty ? f.type : null;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    final contentType =
        browserType ?? _guessContentType(ext) ?? 'application/octet-stream';

    final ts = DateTime.now().millisecondsSinceEpoch;
    final safeName = _sanitiseName(name);
    final tempPath = '${widget.tempFolder}/$uid/$ts-$safeName';

    final ref = FirebaseStorage.instance.ref(tempPath);
    final task = ref.putBlob(f, SettableMetadata(contentType: contentType));

    final sub = task.snapshotEvents.listen((snap) {
      final total = snap.totalBytes;
      onProgress(tempPath, snap.bytesTransferred, total);
    });

    try {
      await task;
    } finally {
      await sub.cancel();
    }

    _pending.add(
      TempAttachment(
        name: name,
        storagePath: tempPath,
        size: size,
        contentType: contentType,
      ),
    );
  }
}
