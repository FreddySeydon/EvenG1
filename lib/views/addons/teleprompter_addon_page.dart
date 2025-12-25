import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/teleprompter_controller.dart';
import '../../models/teleprompter_models.dart';
import 'teleprompter_slides_page.dart';

class TeleprompterAddonPage extends StatefulWidget {
  const TeleprompterAddonPage({super.key});

  @override
  State<TeleprompterAddonPage> createState() => _TeleprompterAddonPageState();
}

class _TeleprompterAddonPageState extends State<TeleprompterAddonPage> {
  late final TeleprompterController _controller;

  @override
  void initState() {
    super.initState();
    if (Get.isRegistered<TeleprompterController>()) {
      _controller = Get.find<TeleprompterController>();
    } else {
      _controller = Get.put(TeleprompterController());
    }
  }

  Future<void> _promptCreatePresentation() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('New Presentation'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: 'Presentation name',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text('Create'),
          ),
        ],
      ),
    );

    if (result == null) return;
    final presentation = await _controller.addPresentation(result);
    if (!mounted) return;
    _openPresentation(presentation);
  }

  Future<void> _promptRenamePresentation(
    TeleprompterPresentation presentation,
  ) async {
    final controller = TextEditingController(text: presentation.name);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Rename Presentation'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: 'Presentation name',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text('Save'),
          ),
        ],
      ),
    );

    if (result == null) return;
    await _controller.renamePresentation(presentation.id, result);
  }

  Future<void> _confirmDeletePresentation(
    TeleprompterPresentation presentation,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Presentation'),
        content: Text(
          'Delete "${presentation.name}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _controller.deletePresentation(presentation.id);
    }
  }

  void _openPresentation(TeleprompterPresentation presentation) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TeleprompterSlidesPage(
          presentationId: presentation.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Teleprompter'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _promptCreatePresentation,
        child: Icon(Icons.add),
      ),
      body: Obx(() {
        if (_controller.isLoading.value) {
          return Center(child: CircularProgressIndicator());
        }

        if (_controller.presentations.isEmpty) {
          return Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.slideshow, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No presentations yet',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Create a presentation to start sending teleprompter slides.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.all(16),
          itemCount: _controller.presentations.length,
          itemBuilder: (context, index) {
            final presentation = _controller.presentations[index];
            return Card(
              margin: EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: Icon(Icons.slideshow),
                title: Text(presentation.name),
                subtitle: Text('${presentation.slides.length} slides'),
                onTap: () => _openPresentation(presentation),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'rename') {
                      _promptRenamePresentation(presentation);
                    } else if (value == 'delete') {
                      _confirmDeletePresentation(presentation);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'rename',
                      child: Text('Rename'),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      }),
    );
  }
}
