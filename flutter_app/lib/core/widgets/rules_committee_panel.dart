// flutter_app/lib/core/widgets/rules_committee_panel.dart
import 'package:flutter/material.dart';

import 'package:rule_post/api/admin_apis.dart';
import 'package:rule_post/content/widgets/prompt_stage_length.dart';
import 'package:rule_post/core/models/types.dart';


// Class to create consistency in the admin buttons that live in the Rules Committee Panel
class AdminAction {
  const AdminAction({
    required this.label,
    required this.runWithArgs,
    this.icon,
    this.tooltip,
    this.enabled = true,
    this.buildAndGetArgs, // dialog/input step
  });

  final String label;
  final IconData? icon;
  final String? tooltip;
  final bool enabled;
  final Future<dynamic> Function(BuildContext context)? buildAndGetArgs;
  // final Future<Json?> Function(dynamic args) runWithArgs;
  final Future<void> Function(dynamic args) runWithArgs;

  factory AdminAction.publishCompetitorResponses({
    required String enquiryId,
    required bool enabled,
    required BuildContext context,
  }) => AdminAction(
          label: 'Publish Competitor Responses',
          icon: Icons.publish,
          tooltip: enabled ? 'Publish all submitted responses' : 'Locked: No pending responses',
          enabled: enabled,
          runWithArgs: (_) async { publishCompetitorResponses(context, enquiryId); },
        );

  factory AdminAction.publishRCResponse({
    required String enquiryId,
    required bool enabled,
    required BuildContext context,
  }) => AdminAction(
    label: 'Publish RC Response',
    icon: Icons.publish,
    tooltip: enabled ? 'Finish this enquiry stage and skip to the next' : 'Locked: Wait for Competitors to respond',
    enabled: enabled,
    runWithArgs: (_) async { publishRcResponse(context, enquiryId); },
  );

  factory AdminAction.closeEnquiry({
    required String enquiryId,
    required bool enabled,
    required BuildContext context,
  }) {
    return AdminAction(
      label: 'Close Enquiry',
      icon: Icons.lock,
      tooltip: enabled ? 'End enquiry and lock all submissions' : 'Locked: Enquiry already closed',
      enabled: enabled,
      // Step 1: show dropdown dialog and return the chosen EnquiryConclusion (or null)
      buildAndGetArgs: (ctx) async {
        return promptChooseOption<EnquiryConclusion>(
          context: ctx,
          title: 'Close enquiry?',
          message:
              'Indicate how it ended:',
          confirmLabel: 'Proceed',
          items: const [
            DropdownMenuItem(
              value: EnquiryConclusion.amendment,
              child: Text('Amendment'),
            ),
            DropdownMenuItem(
              value: EnquiryConclusion.interpretation,
              child: Text('Interpretation'),
            ),
            DropdownMenuItem(
              value: EnquiryConclusion.noResult,
              child: Text('Enquiry closed with no interpretation or amendment.'),
            ),
          ],
        );
      },
      runWithArgs: (args) async { closeEnquiry(context, enquiryId, args); }
    );
  }

  factory AdminAction.changeStageLength({
    required String enquiryId,
    required Future<int> Function() loadCurrent,
    required bool enabled,
    bool canTerminate = false,
    required BuildContext context,
  }) {
    return AdminAction(
      label: 'Change Stage Length',
      icon: Icons.timer,
      tooltip: enabled ? 'Change stage length or terminate the current stage' : 'Locked: Enquiry closed',
      enabled: enabled,
      buildAndGetArgs: (ctx) async {
        return promptStageLength(
          ctx,
          loadCurrent: loadCurrent,
          min: 1,
          max: 30,
          canTerminate: canTerminate,
        );
      },
      runWithArgs: (args) async {
        if (args is ChangeLength) {
          changeStageLength(context, enquiryId, args.newLength);
        } else if (args is TerminateStage) {
          terminateCompetitorResponseStage(
            context,
            enquiryId,
            publishPendingResponses: args.publishPendingResponses,
          );
        }
      },
    );   
  }

  // [TEST] Send a sample digest email to preview deadline reminders
  factory AdminAction.testSendDigest({
    required BuildContext context,
    required String? userEmail,
  }) => AdminAction(
    label: '[TEST] Send Preview Email',
    icon: Icons.mail_outline,
    tooltip: 'Send a sample digest email with deadline reminder preview (admin-only)',
    enabled: userEmail != null && userEmail.isNotEmpty,
    runWithArgs: (_) async {
      if (userEmail != null) {
        // ignore: use_build_context_synchronously
        await testSendDigest(context, recipientEmail: userEmail);
      }
    },
  );
}


class AdminCard extends StatefulWidget {
  const AdminCard({
    super.key,
    this.title = 'Rules Committee Panel',
    required this.actions,
    this.initiallyExpanded = false,
    this.compact = false,
    this.buttonMinWidth = 140,
    this.buttonMinHeight = 40,
    this.titleColour,
    this.boldTitle = true,
  });

  final String title;
  final List<AdminAction> actions;
  final bool initiallyExpanded;

  final bool compact;
  final double buttonMinWidth;
  final double buttonMinHeight;
  final Color? titleColour;
  final bool boldTitle;

  @override
  State<AdminCard> createState() => _AdminCardState();
}

class _AdminCardState extends State<AdminCard> {
  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.titleMedium;
    final titleStyle = base?.copyWith(
      color: widget.titleColour ?? base.color,
      fontWeight: widget.boldTitle ? FontWeight.bold : base.fontWeight,
    );

    final spacing = widget.compact ? 8.0 : 12.0;

    return Card(
      child: Theme( // Tighten ExpansionTile divider look
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: widget.initiallyExpanded,
          title: Text(widget.title, style: titleStyle),
          childrenPadding: const EdgeInsets.all(16),
          children: [
            // Vertical list of guarded admin actions
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < widget.actions.length; i++) ...[
                  _GuardedActionButton(
                    action: widget.actions[i],
                    minWidth: widget.buttonMinWidth,
                    minHeight: widget.buttonMinHeight,
                  ),
                  if (i != widget.actions.length - 1)
                    SizedBox(height: spacing),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}


/// A full-width button that shows a warning/confirmation dialog before running.
class _GuardedActionButton extends StatelessWidget {
  const _GuardedActionButton({
    required this.action,
    required this.minWidth,
    required this.minHeight,
  });

  final AdminAction action;
  final double minWidth;
  final double minHeight;

  Future<void> _handlePress(BuildContext context) async {
    if (!action.enabled) return;

    // 1. If there's a dialog/input step, run it.
    dynamic args;
    if (action.buildAndGetArgs != null) {
      args = await action.buildAndGetArgs!(context);
      // User hit cancel
      if (args == null) return;
    } else {
      // 2. Otherwise show the stock "are you sure?" dialog.
      final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              icon: const Icon(Icons.warning_amber_rounded),
              title: Text(action.label),
              content: Text(
                (action.tooltip?.trim().isNotEmpty ?? false)
                    ? action.tooltip!.trim()
                    : 'Are you sure you want to run “${action.label}”?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Proceed'),
                ),
              ],
            ),
          ) ??
          false;
      if (!ok) return;
      args = null; // no custom data
    }

    // 3. Run the action with the gathered args (if any).
    await action.runWithArgs(args);
    return;
  }

  @override
  Widget build(BuildContext context) {
    final btn = ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: minWidth,
        minHeight: minHeight,
      ),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: action.enabled ? () => _handlePress(context) : null,
          icon: Icon(action.icon ?? Icons.settings),
          label: Text(action.label),
        ),
      ),
    );

    return (action.tooltip == null || action.tooltip!.isEmpty)
        ? btn
        : Tooltip(message: action.tooltip!, child: btn);
  }
}


Future<T?> promptChooseOption<T>({
  required BuildContext context,
  required String title,
  required String message,
  required List<DropdownMenuItem<T>> items,
  required String confirmLabel,
}) async {
  T? tempValue;

  return showDialog<T>(
    context: context,
    barrierDismissible: false, // force explicit Cancel/Confirm
    builder: (ctx) {
      return AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(message),
            const SizedBox(height: 12),
            StatefulBuilder(
              builder: (ctx, setState) {
                return DropdownButtonFormField<T>(
                  initialValue: tempValue,
                  items: items,
                  onChanged: (newVal) {
                    setState(() {
                      tempValue = newVal;
                    });
                  },
                  decoration: const InputDecoration(
                    labelText: 'Select an option',
                    border: OutlineInputBorder(),
                  ),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              // Only allow confirm if something is chosen
              if (tempValue != null) {
                Navigator.of(ctx).pop(tempValue);
              }
            },
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
}