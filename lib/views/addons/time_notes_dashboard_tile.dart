import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../ble_manager.dart';
import '../../controllers/time_notes_controller.dart';
import '../../models/time_note.dart';
import '../../services/pin_text_service.dart';

class TimeNotesDashboardTile extends StatelessWidget {
  const TimeNotesDashboardTile({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<TimeNotesController>();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Obx(() {
        final active = controller.activeNotes;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Time-aware Notes',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  active.isEmpty ? 'Idle' : '${active.length} active',
                  style: TextStyle(
                    color: active.isEmpty ? Colors.grey : Colors.green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (active.isEmpty)
              const Text(
                'No notes are active right now. Add one or use the test send.',
                style: TextStyle(color: Colors.grey),
              )
            else
              ...active.take(2).map((note) => _ActiveNoteRow(note: note)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _sendTest(context),
                    icon: const Icon(Icons.push_pin_outlined),
                    label: const Text('Send test note'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: active.isEmpty
                        ? null
                        : () => _sendNote(context, active.first),
                    icon: const Icon(Icons.send),
                    label: const Text('Send active'),
                  ),
                ),
              ],
            ),
          ],
        );
      }),
    );
  }

  Future<void> _sendTest(BuildContext context) async {
    const message = 'Test dashboard note: hello from time-aware notes addon.';
    await _sendContent(context, message);
  }

  Future<void> _sendNote(BuildContext context, TimeNote note) async {
    await _sendContent(context, note.content);
  }

  Future<void> _sendContent(BuildContext context, String content) async {
    if (!BleManager.get().isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Glasses not connected — connect to send notes.')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sending to G1 dashboard...')),
    );
    await PinTextService.instance.sendPinText(content);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sent to G1 dashboard')),
    );
  }
}

class _ActiveNoteRow extends StatelessWidget {
  const _ActiveNoteRow({required this.note});

  final TimeNote note;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            note.title.isEmpty ? 'Active note' : note.title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            note.content,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
