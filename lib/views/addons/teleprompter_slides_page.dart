import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../ble_manager.dart';
import '../../controllers/teleprompter_controller.dart';
import '../../models/teleprompter_models.dart';
import '../../services/teleprompter_font_metrics.dart';
import '../../services/teleprompter_service.dart';
import '../../services/teleprompter_text_processor.dart';

class TeleprompterSlidesPage extends StatefulWidget {
  final String presentationId;

  const TeleprompterSlidesPage({
    super.key,
    required this.presentationId,
  });

  @override
  State<TeleprompterSlidesPage> createState() => _TeleprompterSlidesPageState();
}

class _TeleprompterSlidesPageState extends State<TeleprompterSlidesPage> {
  late final TeleprompterController _controller;
  String? _presentingSlideId;
  bool _isSending = false;
  final ScrollController _previewScrollController = ScrollController();
  int _lastSentScrollPercent = 0;
  TeleprompterSlide? _currentSlide;
  String _currentFormattedText = '';
  String _lastSentWindowText = '';
  bool _suppressScrollSync = false;
  Timer? _scrollDebounce;
  Timer? _keepAliveTimer;
  bool _volumeScrollEnabled = false;

  @override
  void initState() {
    super.initState();
    _controller = Get.find<TeleprompterController>();
    BleManager.get().onTouchpadTap = _handleTouchpadTap;
    BleManager.get().onVolumeKey = _handleVolumeKey;
  }

  @override
  void dispose() {
    BleManager.get().onTouchpadTap = null;
    BleManager.get().onVolumeKey = null;
    _setVolumeKeyHandling(false);
    if (_presentingSlideId != null) {
      TeleprompterService.instance.exitTeleprompter();
    }
    _scrollDebounce?.cancel();
    _keepAliveTimer?.cancel();
    _previewScrollController.dispose();
    super.dispose();
  }

  Future<void> _addSlide() async {
    final slideText = await _promptSlideText();
    if (slideText == null || slideText.trim().isEmpty) return;
    final slide = TeleprompterSlide(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      text: slideText.trim(),
    );
    await _controller.addSlide(widget.presentationId, slide);
  }

  Future<void> _editSlide(TeleprompterSlide slide) async {
    final updatedText = await _promptSlideText(initialText: slide.text);
    if (updatedText == null) return;
    if (updatedText.trim().isEmpty) {
      await _controller.deleteSlide(widget.presentationId, slide.id);
      return;
    }
    await _controller.updateSlide(
      widget.presentationId,
      slide.copyWith(text: updatedText.trim()),
    );
  }

  Future<String?> _promptSlideText({String? initialText}) async {
    final controller = TextEditingController(text: initialText ?? '');
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(initialText == null ? 'New Slide' : 'Edit Slide'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: 'Slide text'),
          keyboardType: TextInputType.multiline,
          maxLines: 6,
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
  }

  Future<void> _confirmDeleteSlide(TeleprompterSlide slide) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Slide'),
        content: Text('Delete this slide?'),
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
      await _controller.deleteSlide(widget.presentationId, slide.id);
    }
  }

  Future<void> _togglePresenting(
    TeleprompterPresentation presentation,
    TeleprompterSlide slide,
  ) async {
    if (_isSending) return;
    if (_presentingSlideId == slide.id) {
      await _stopPresenting();
      return;
    }

    final slideIndex = presentation.slides.indexWhere((s) => s.id == slide.id);
    if (slideIndex == -1) return;

    await _sendSlide(presentation, slideIndex);
  }

  Future<void> _sendSlide(
    TeleprompterPresentation presentation,
    int slideIndex,
  ) async {
    if (_isSending) return;
    if (!BleManager.get().isConnected) {
      _showSnack('Glasses are not connected.');
      return;
    }

    final slide = presentation.slides[slideIndex];
    final slidePercentage = presentation.slides.length > 1
        ? ((slideIndex / (presentation.slides.length - 1)) * 100).round()
        : 0;

    setState(() => _isSending = true);
    final formatted = await _formatSlideText(slide.text);
    final success = await TeleprompterService.instance.sendTeleprompterText(
      slide.text,
      slidePercentage: slidePercentage,
      manualMode: false,
    );
    if (!mounted) return;
    setState(() {
      _isSending = false;
      _presentingSlideId = success ? slide.id : null;
      _currentSlide = success ? slide : null;
      _currentFormattedText = success ? formatted : '';
      _lastSentScrollPercent = slidePercentage;
      _lastSentWindowText = success
          ? TeleprompterTextProcessor.sliceFormattedTextAtPercent(
              formatted,
              slidePercentage,
            )
          : '';
    });
    if (!success) {
      _showSnack('Failed to send slide to glasses.');
      return;
    }
    _suppressScrollSync = true;
    _previewScrollController.jumpTo(0);
    _suppressScrollSync = false;
    _startKeepAlive();
  }

  Future<void> _stopPresenting() async {
    if (_isSending) return;
    setState(() => _isSending = true);
    await TeleprompterService.instance.exitTeleprompter();
    if (!mounted) return;
    setState(() {
      _isSending = false;
      _presentingSlideId = null;
      _currentSlide = null;
      _currentFormattedText = '';
      _lastSentWindowText = '';
      _lastSentScrollPercent = 0;
    });
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }

  Future<void> _navigateSlide(
    TeleprompterPresentation presentation,
    int delta,
  ) async {
    if (_presentingSlideId == null) return;
    final currentIndex = presentation.slides
        .indexWhere((slide) => slide.id == _presentingSlideId);
    if (currentIndex == -1) return;
    final nextIndex = currentIndex + delta;
    if (nextIndex < 0 || nextIndex >= presentation.slides.length) {
      return;
    }
    await _sendSlide(presentation, nextIndex);
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _handleTouchpadTap(String lr) {
    if (!mounted || _presentingSlideId == null) return;
    final presentation = _controller.getPresentation(widget.presentationId);
    if (presentation == null) return;
    if (lr == 'R') {
      _navigateSlide(presentation, 1);
    } else {
      _navigateSlide(presentation, -1);
    }
  }

  void _handleVolumeKey(String direction) {
    if (!_volumeScrollEnabled || _presentingSlideId == null) return;
    final step = direction == 'up' ? -5 : 5;
    _sendScrollStep(step);
  }

  Future<void> _sendScrollStep(int step) async {
    final nextPercent = (_lastSentScrollPercent + step).clamp(0, 100);
    await _sendScrollPercent(nextPercent);
    if (_previewScrollController.hasClients) {
      final maxScroll = _previewScrollController.position.maxScrollExtent;
      if (maxScroll > 0) {
        _suppressScrollSync = true;
        _previewScrollController.jumpTo(maxScroll * (nextPercent / 100));
        _suppressScrollSync = false;
      }
    }
  }

  Future<void> _sendScrollPercent(int percent) async {
    if (_currentSlide == null) return;
    if (_isSending) return;
    final windowText = TeleprompterTextProcessor.sliceFormattedTextAtPercent(
      _currentFormattedText,
      percent,
    );
    if (windowText == _lastSentWindowText) {
      return;
    }
    setState(() => _isSending = true);
    final success = await TeleprompterService.instance.sendTeleprompterText(
      _currentSlide!.text,
      slidePercentage: percent,
      exitBeforeSend: false,
      manualMode: false,
      updateMode: true,
      formattedText: _currentFormattedText,
      scrollPercent: percent,
    );
    if (!mounted) return;
    setState(() {
      _isSending = false;
      if (success) {
        _lastSentScrollPercent = percent;
        _lastSentWindowText = windowText;
      }
    });
    if (!success) {
      _showSnack('Failed to sync scroll position.');
    }
  }

  Future<void> _setVolumeKeyHandling(bool enabled) async {
    await BleManager.invokeMethod('setVolumeKeyHandlingEnabled', {
      'enabled': enabled,
    });
  }

  Future<void> _syncScrollPosition() async {
    if (_suppressScrollSync || _isSending) return;
    if (_presentingSlideId == null || _currentSlide == null) return;
    if (!_previewScrollController.hasClients) return;

    final maxScroll = _previewScrollController.position.maxScrollExtent;
    if (maxScroll <= 0) return;

    final percent = ((_previewScrollController.offset / maxScroll) * 100)
        .round()
        .clamp(0, 100);
    if ((percent - _lastSentScrollPercent).abs() < 1) {
      return;
    }

    _lastSentScrollPercent = percent;
    setState(() => _isSending = true);
    final success = await TeleprompterService.instance.sendTeleprompterText(
      _currentSlide!.text,
      slidePercentage: percent,
      exitBeforeSend: false,
      manualMode: false,
      updateMode: true,
      formattedText: _currentFormattedText,
      scrollPercent: percent,
    );
    if (!mounted) return;
    setState(() => _isSending = false);
    if (!success) {
      _showSnack('Failed to sync scroll position.');
    }
  }

  void _handleScroll() {
    if (_suppressScrollSync || _presentingSlideId == null) return;
    _scrollDebounce?.cancel();
    _scrollDebounce = Timer(const Duration(milliseconds: 250), () {
      _syncScrollPosition();
    });
  }

  Future<String> _formatSlideText(String text) async {
    final charWidths = await TeleprompterFontMetrics.load();
    return TeleprompterTextProcessor.addLineBreaksWithMetrics(
      text,
      charWidths,
      maxWidth: 180,
    );
  }

  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) async {
        if (_presentingSlideId == null || _currentSlide == null) return;
        if (_isSending) return;
        setState(() => _isSending = true);
        await TeleprompterService.instance.sendTeleprompterText(
          _currentSlide!.text,
          slidePercentage: _lastSentScrollPercent,
          exitBeforeSend: false,
          manualMode: false,
          updateMode: true,
          formattedText: _currentFormattedText,
          scrollPercent: _lastSentScrollPercent,
        );
        if (mounted) {
          setState(() => _isSending = false);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final presentation =
          _controller.getPresentation(widget.presentationId);
      if (presentation == null) {
        return Scaffold(
          appBar: AppBar(title: Text('Teleprompter')),
          body: Center(child: Text('Presentation not found.')),
        );
      }

      return Scaffold(
        appBar: AppBar(
          title: Text(presentation.name),
          actions: [
            if (_presentingSlideId != null)
              IconButton(
                icon: Icon(Icons.stop),
                onPressed: _isSending ? null : _stopPresenting,
              ),
            IconButton(
              icon: Icon(Icons.add),
              onPressed: _addSlide,
            ),
          ],
        ),
        body: presentation.slides.isEmpty
            ? Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notes, size: 48, color: Colors.grey),
                      SizedBox(height: 12),
                      Text(
                        'No slides yet',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Add a slide to start presenting.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                      SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _addSlide,
                        icon: Icon(Icons.add),
                        label: Text('Add Slide'),
                      ),
                    ],
                  ),
                ),
              )
            : Column(
                children: [
                  if (_presentingSlideId != null)
                    Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Card(
                        child: SizedBox(
                          height: 160,
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Preview (scroll to sync)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text('Use volume keys to scroll'),
                                  value: _volumeScrollEnabled,
                                  onChanged: (value) async {
                                    setState(() => _volumeScrollEnabled = value);
                                    await _setVolumeKeyHandling(value);
                                  },
                                ),
                                SizedBox(height: 8),
                                Expanded(
                                  child: NotificationListener<ScrollNotification>(
                                    onNotification: (notification) {
                                      if (notification is ScrollUpdateNotification) {
                                        _handleScroll();
                                      } else if (notification is ScrollEndNotification) {
                                        _syncScrollPosition();
                                      }
                                      return false;
                                    },
                                    child: Scrollbar(
                                      controller: _previewScrollController,
                                      child: SingleChildScrollView(
                                        controller: _previewScrollController,
                                        child: Text(
                                          _currentFormattedText,
                                          style: TextStyle(fontSize: 14),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_presentingSlideId != null)
                    Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isSending
                                  ? null
                                  : () => _navigateSlide(presentation, -1),
                              icon: Icon(Icons.skip_previous),
                              label: Text('Previous'),
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isSending
                                  ? null
                                  : () => _navigateSlide(presentation, 1),
                              icon: Icon(Icons.skip_next),
                              label: Text('Next'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.all(16),
                      itemCount: presentation.slides.length,
                      itemBuilder: (context, index) {
                        final slide = presentation.slides[index];
                        final isPresenting = slide.id == _presentingSlideId;
                        return Card(
                          margin: EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            title: Text(
                              slide.text.length > 60
                                  ? '${slide.text.substring(0, 60)}...'
                                  : slide.text,
                            ),
                            subtitle: Text('Slide ${index + 1}'),
                            onTap: () => _togglePresenting(
                              presentation,
                              slide,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.keyboard_arrow_up),
                                  onPressed: index == 0
                                      ? null
                                      : () => _controller.moveSlide(
                                            presentation.id,
                                            index,
                                            index - 1,
                                          ),
                                ),
                                IconButton(
                                  icon: Icon(Icons.keyboard_arrow_down),
                                  onPressed: index == presentation.slides.length - 1
                                      ? null
                                      : () => _controller.moveSlide(
                                            presentation.id,
                                            index,
                                            index + 1,
                                          ),
                                ),
                                IconButton(
                                  icon: Icon(Icons.edit),
                                  onPressed: () => _editSlide(slide),
                                ),
                                IconButton(
                                  icon: Icon(Icons.delete),
                                  onPressed: () => _confirmDeleteSlide(slide),
                                ),
                                IconButton(
                                  icon: Icon(
                                    isPresenting
                                        ? Icons.stop_circle_outlined
                                        : Icons.play_circle_fill,
                                  ),
                                  color: isPresenting ? Colors.red : Colors.green,
                                  onPressed: _isSending
                                      ? null
                                      : () => _togglePresenting(
                                            presentation,
                                            slide,
                                          ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
      );
    });
  }
}
