// flutter_app/lib/content/screens/help_screen.dart
import "package:flutter/material.dart";

import 'package:rule_post/core/buttons/back_button.dart';


class HelpFaqScreen extends StatelessWidget {
  const HelpFaqScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final faqs = <Map<String, Object>>[
      // General
      {
        "icon": Icons.info_outline, // was 🧭
        "header": "General",
        "items": <Map<String, String>>[
          {
            "question": "What is a Rule Enquiry?",
            "answer":
                "A request for interpretation or amendment of the America's Cup Class Rules and Specifications."
          },
          {
            "question": "What are enquiries, responses, comments and posts?",
            "answer":
                "Enquiry refers to both the initial question and the entire discussion thread. Responses are formal replies from teams to the initial enquiry and the Rules Committee's proposals. Comments allow teams to engage directly with each other's responses. Post is a general term for any of these submission types."
          },
          {
            "question": "How can I keep up to date with new posts?",
            "answer":
                "Enable email notifications under your account settings to receive updates when new posts are made. Posts you haven't read yet will also have a visual indicator, and be listed in the 'unread posts' dropdown."
          },
          {
            "question": "How do I get an account?",
            "answer":
                "Accounts are only for team members of America's Cup Competitors. Each Competitor has a nominated 'team admin' who can add or delete users."
          },
        ]
      },

      // How to Submit
      {
        "icon": Icons.edit, // was ✏️
        "header": "How to Submit",
        "items": <Map<String, String>>[
          {
            "question": "How do I submit a new enquiry?",
            "answer":
                "Log in, and click the '+ New' button next to 'Rule Enquiries' at the top left of the screen."
          },
          {
            "question": "How do I submit a new response?",
            "answer":
                "Log in, and navigate to the parent enquiry using the navigation pane on the left. Click the '+ New' button in the 'Responses' section."
          },
          {
            "question": "How do I submit a new comment?",
            "answer":
                "Log in, and navigate to the parent response using the navigation pane on the left. Click the '+ New' button in the 'Comments' section."
          },
        ]
      },

      // Posts
      {
        "icon": Icons.description, // was 📋
        "header": "Posts",
        "items": <Map<String, String>>[
          {
            "question": "Are posts anonymous?",
            "answer":
                "Yes. However, there is Competitor colour-coding unique to each enquiry, to make post threads more readable."
          },
          {
            "question": "Why didn't my post publish after I submitted it?",
            "answer":
                "Post publications are delayed to specific times, detailed in the AC Technical Regulations. The draft should be viewable if you are logged in."
          },
          {
            "question": "Can I edit or delete a post after submitting it?",
            "answer":
                "If you're logged in, you should be able to view and edit any posts submitted by your team. Deletion is not currently available."
          },
          {
            "question": "What types of files can I upload?",
            "answer":
                "PDF and Word (.docx) files are supported. Files are automatically renamed for storage to include the enquiry number."
          },
          {
            "question": "Why can't I submit?",
            "answer":
                "The enquiry is probably at the incorrect stage for your submission type. If you don't believe this is correct, contact the Rules Committee."
          },
          {
            "question": "Should I use 'details' or 'attachments' field for post content?",
            "answer":
                "Details are better for website performance, but attachments are useful for images and complex content."
          },
          {"question": "Can I use markdown formatting in my post?",
            "answer":
                "Yes. The following markdown syntax is supported; italics, bold text, strikethrough, lists, headers, blockquotes, tables and code blocks."},
        ]
      },

      // Timing & Stages
      {
        "icon": Icons.schedule, // was ⏰
        "header": "Timing & Stages",
        "items": <Map<String, String>>[
          {
            "question": "How do I find a submission deadline?",
            "answer":
                "Enquiries have an 'Enquiry Stage' section, which details the current enquiry stage, when it ends, and what the next one will be."
          },
          {
            "question": "How are deadlines calculated?",
            "answer":
                "They are based on the AC Technical Regulations. The general flow is as follows: Enquiry is submitted, teams respond, teams comment on each other's responses, Rules Committee responds. Those last three steps repeat until the enquiry is closed."
          },
          {
            "question": "What if I miss a deadline?",
            "answer":
                "There is currently no mechanism for allowing late submissions, but contact the Rules Committee if you believe this website facilitated the submission error."
          },
          {
            "question": "Which time zone are deadlines in?",
            "answer":
                "The displayed enquiry deadlines are adjusted to your device's timezone."
          },
        ]
      },

      // Technical / Troubleshooting
      {
        "icon": Icons.build, // was ⚙️
        "header": "Technical / Troubleshooting",
        "items": <Map<String, String>>[
          {
            "question": "I can't upload a file, what should I check?",
            "answer":
                "Confirm it's under the size limit (e.g. 10 MB) and in an allowed format (.pdf or .docx)."
          },
          {
            "question": "Why is the '+ New' button greyed out?",
            "answer":
                "The submission window may have closed, or your team has already submitted for this round."
          },
          {
            "question": "Why do I get 'permission denied'?",
            "answer":
                "Your account might not have the right role (Team vs Rules Committee) or the enquiry is locked."
          },
        ]
      },
    ];

    return Scaffold(
      appBar: AppBar(
        leading: const Padding(
          padding: EdgeInsets.all(12),
          child: BackButtonCompact(),
        ),
        title: const Text("Help & FAQ"),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            "Frequently Asked Questions",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          for (final section in faqs) ...[
          const SizedBox(height: 16),
            Row(
              children: [
                Icon(section["icon"] as IconData),
                const SizedBox(width: 8),
                Text(
                  section["header"] as String,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...(section["items"] as List<Map<String, String>>).map(
              (faq) => Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ExpansionTile(
                  title: Text(faq["question"]!),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: buildAnswerText(context, faq["answer"]!),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}


Widget buildAnswerText(BuildContext context, String text) {
  // Supports **bold** inline
  final regex = RegExp(r"\*\*(.+?)\*\*");
  final spans = <TextSpan>[];
  int lastIndex = 0;

  for (final match in regex.allMatches(text)) {
    if (match.start > lastIndex) {
      spans.add(TextSpan(text: text.substring(lastIndex, match.start)));
    }
    spans.add(
      TextSpan(
        text: match.group(1),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
    lastIndex = match.end;
  }

  if (lastIndex < text.length) {
    spans.add(TextSpan(text: text.substring(lastIndex)));
  }

  return Text.rich(
    TextSpan(
      style: DefaultTextStyle.of(context).style,
      children: spans,
    ),
    textAlign: TextAlign.center,
  );
}