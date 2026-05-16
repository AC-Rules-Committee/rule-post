// flutter_app/lib/content/widgets/prompt_stage_length.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Result type for the stage length dialog.
/// Either a new stage length or a terminate action.
sealed class StageDialogResult {}

class ChangeLength extends StageDialogResult {
  final int newLength;
  ChangeLength(this.newLength);
}

class TerminateStage extends StageDialogResult {
  final bool publishPendingResponses;
  TerminateStage(this.publishPendingResponses);
}


// Used in rules committee function to alter stage lengths or terminate stage
Future<StageDialogResult?> promptStageLength(
  BuildContext context, {
  required Future<int> Function() loadCurrent,
  int min = 1,
  int max = 30,
  bool canTerminate = false,
}) async {
  final result = await showDialog<StageDialogResult?>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      // 👇 correctly *call* the function
      final future = loadCurrent();
      final controller = TextEditingController();
      final formKey = GlobalKey<FormState>();

      return FutureBuilder<int>(
        future: future,
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return const AlertDialog(
              content: SizedBox(height: 96, child: Center(child: CircularProgressIndicator())),
            );
          }

          controller.text = snap.data!.toString();

          return AlertDialog(
            title: const Text('Change Stage Length'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Form(
                  key: formKey,
                  child: TextFormField(
                    controller: controller,
                    decoration: const InputDecoration(
                      labelText: 'Working days',
                      helperText: 'Set the number of working days for major stages',
                      helperMaxLines: 2,
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Enter a number';
                      final n = int.tryParse(v);
                      if (n == null) return 'Invalid number';
                      if (n < min || n > max) return 'Must be between $min and $max';
                      return null;
                    },
                  ),
                ),
                if (canTerminate) ...[
                  const Divider(height: 32),
                  Text(
                    'Or terminate the competitor response stage immediately:',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              Navigator.of(ctx).pop(TerminateStage(true)),
                          icon: const Icon(Icons.publish),
                          label: const Text('Terminate & Publish'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              Navigator.of(ctx).pop(TerminateStage(false)),
                          icon: const Icon(Icons.cancel),
                          label: const Text('Terminate & Discard'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Publish: pending responses are published before advancing.\n'
                    'Discard: advance to comment stage without publishing.',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    Navigator.of(ctx).pop(ChangeLength(int.parse(controller.text)));
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );

  return result;
}