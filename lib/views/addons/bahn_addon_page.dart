import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../../controllers/bahn_controller.dart';
import '../../models/bahn_journey.dart';

class BahnAddonPage extends StatelessWidget {
  const BahnAddonPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Train Timetable'),
          bottom: TabBar(
            tabs: [
              Tab(text: 'Search', icon: Icon(Icons.search)),
              Tab(text: 'Bookmarks', icon: Icon(Icons.bookmark)),
              Tab(text: 'Settings', icon: Icon(Icons.settings)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _SearchTab(),
            _BookmarksTab(),
            _SettingsTab(),
          ],
        ),
      ),
    );
  }
}

class _SearchTab extends StatefulWidget {
  @override
  State<_SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<_SearchTab> {
  late final BahnController _controller;
  final _fromController = TextEditingController();
  final _toController = TextEditingController();
  DateTime _selectedDateTime = DateTime.now().add(Duration(minutes: 5));

  @override
  void initState() {
    super.initState();
    _controller = Get.find<BahnController>();
  }

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    super.dispose();
  }

  Future<void> _selectDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(Duration(days: 90)),
    );

    if (date != null && mounted) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_selectedDateTime),
      );

      if (time != null && mounted) {
        setState(() {
          _selectedDateTime = DateTime(
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute,
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // From Station
          Text('From', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          GetX<BahnController>(
            builder: (controller) {
              final isSearching = controller.isSearchingStations.value;
              final selectedStation = controller.selectedFromStation.value;
              return Autocomplete<BahnStation>(
              key: ValueKey('from_station'),
              displayStringForOption: (station) => station.name,
              optionsBuilder: (textEditingValue) {
                if (textEditingValue.text.isEmpty) {
                  return const Iterable<BahnStation>.empty();
                }
                return controller.stationSearchResults;
              },
              onSelected: (station) {
                controller.selectedFromStation.value = station;
              },
              fieldViewBuilder: (context, textController, focusNode, onSubmitted) {
                // Use the Autocomplete's built-in controller, sync with local controller
                if (textController.text.isEmpty && _fromController.text.isNotEmpty) {
                  textController.text = _fromController.text;
                }
                return TextField(
                  controller: textController,
                  focusNode: focusNode,
                  decoration: InputDecoration(
                    hintText: 'Search departure station...',
                    border: OutlineInputBorder(),
                    suffixIcon: isSearching
                        ? Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : selectedStation != null &&
                          textController.text == selectedStation.name
                            ? IconButton(
                                icon: Icon(Icons.check, color: Colors.green),
                                onPressed: () {},
                              )
                            : SizedBox.shrink(),
                  ),
                  onChanged: (value) {
                    // Clear selection if text changes
                    if (controller.selectedFromStation.value != null &&
                        value != controller.selectedFromStation.value!.name) {
                      controller.selectedFromStation.value = null;
                    }
                    controller.searchStations(value);
                    _fromController.text = value;
                  },
                  onSubmitted: (_) => onSubmitted(),
                );
              },
            );
            },
          ),

          SizedBox(height: 16),

          // To Station
          Text('To', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          GetX<BahnController>(
            builder: (controller) {
              final isSearching = controller.isSearchingStations.value;
              final selectedStation = controller.selectedToStation.value;
              return Autocomplete<BahnStation>(
              key: ValueKey('to_station'),
              displayStringForOption: (station) => station.name,
              optionsBuilder: (textEditingValue) {
                if (textEditingValue.text.isEmpty) {
                  return const Iterable<BahnStation>.empty();
                }
                return controller.stationSearchResults;
              },
              onSelected: (station) {
                controller.selectedToStation.value = station;
              },
              fieldViewBuilder: (context, textController, focusNode, onSubmitted) {
                // Use the Autocomplete's built-in controller, sync with local controller
                if (textController.text.isEmpty && _toController.text.isNotEmpty) {
                  textController.text = _toController.text;
                }
                return TextField(
                  controller: textController,
                  focusNode: focusNode,
                  decoration: InputDecoration(
                    hintText: 'Search arrival station...',
                    border: OutlineInputBorder(),
                    suffixIcon: isSearching
                        ? Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : selectedStation != null &&
                          textController.text == selectedStation.name
                            ? IconButton(
                                icon: Icon(Icons.check, color: Colors.green),
                                onPressed: () {},
                              )
                            : SizedBox.shrink(),
                  ),
                  onChanged: (value) {
                    // Clear selection if text changes
                    if (controller.selectedToStation.value != null &&
                        value != controller.selectedToStation.value!.name) {
                      controller.selectedToStation.value = null;
                    }
                    controller.searchStations(value);
                    _toController.text = value;
                  },
                  onSubmitted: (_) => onSubmitted(),
                );
              },
            );
            },
          ),

          SizedBox(height: 16),

          // Date/Time Picker
          Text('Departure', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          InkWell(
            onTap: _selectDateTime,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    DateFormat('EEE, MMM d, yyyy HH:mm').format(_selectedDateTime),
                    style: TextStyle(fontSize: 16),
                  ),
                  Icon(Icons.calendar_today),
                ],
              ),
            ),
          ),

          SizedBox(height: 24),

          // Search Button
          GetBuilder<BahnController>(
            builder: (controller) => ElevatedButton.icon(
              onPressed: controller.isSearching.value ||
                      controller.selectedFromStation.value == null ||
                      controller.selectedToStation.value == null
                  ? null
                  : () => controller.searchJourneys(departure: _selectedDateTime),
              icon: controller.isSearching.value
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(Icons.search),
              label: Text(controller.isSearching.value ? 'Searching...' : 'Search Connections'),
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),

          SizedBox(height: 16),

          // Error Message
          GetBuilder<BahnController>(
            builder: (controller) {
              if (controller.searchError.value != null) {
                return Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error, color: Colors.red),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          controller.searchError.value!,
                          style: TextStyle(color: Colors.red.shade900),
                        ),
                      ),
                    ],
                  ),
                );
              }
              return SizedBox.shrink();
            },
          ),

          SizedBox(height: 16),

          // Results
          GetBuilder<BahnController>(
            builder: (controller) {
              if (controller.searchResults.isEmpty) {
                return SizedBox.shrink();
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Results (${controller.searchResults.length})',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: NeverScrollableScrollPhysics(),
                    itemCount: controller.searchResults.length,
                    itemBuilder: (context, index) {
                      return _JourneyCard(journey: controller.searchResults[index]);
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _JourneyCard extends StatelessWidget {
  final BahnJourney journey;

  const _JourneyCard({required this.journey});

  @override
  Widget build(BuildContext context) {
    final departure = DateFormat('HH:mm').format(journey.plannedDeparture);
    final arrival = DateFormat('HH:mm').format(journey.plannedArrival);
    final duration = '${journey.duration.inHours}h ${journey.duration.inMinutes % 60}m';

    return Card(
      margin: EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Row(
          children: [
            Icon(Icons.train),
            SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    journey.trainName,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  SizedBox(height: 2),
                  Text(
                    '${journey.origin.name} → ${journey.destination.name}',
                    style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '$departure - $arrival  •  $duration  •  ${journey.changes} changes',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
        trailing: IconButton(
          icon: Icon(Icons.bookmark_add, color: Colors.blue),
          onPressed: () => _showBookmarkDialog(context, journey),
        ),
        children: journey.legs.map((leg) => _LegTile(leg: leg)).toList(),
      ),
    );
  }

  void _showBookmarkDialog(BuildContext context, BahnJourney journey) {
    final controller = Get.find<BahnController>();
    int selectedSlot = controller.defaultSlot.value;
    BahnDisplayTiming selectedTiming = controller.defaultTiming.value;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Bookmark Journey'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${journey.trainName}: ${journey.origin.name} → ${journey.destination.name}'),
              SizedBox(height: 16),
              Text('Dashboard Slot', style: TextStyle(fontWeight: FontWeight.bold)),
              DropdownButton<int>(
                value: selectedSlot,
                isExpanded: true,
                items: [1, 2, 3, 4].map((slot) {
                  return DropdownMenuItem(
                    value: slot,
                    child: Text('Slot $slot${slot == 1 ? ' (used by timed notes)' : ''}'),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) setState(() => selectedSlot = value);
                },
              ),
              SizedBox(height: 8),
              Text('Display Timing', style: TextStyle(fontWeight: FontWeight.bold)),
              ...BahnDisplayTiming.values.map((timing) {
                return RadioListTile<BahnDisplayTiming>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(timing.label),
                  value: timing,
                  groupValue: selectedTiming,
                  onChanged: (value) {
                    if (value != null) setState(() => selectedTiming = value);
                  },
                );
              }).toList(),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                controller.addBookmark(
                  journey,
                  slot: selectedSlot,
                  timing: selectedTiming,
                );
                Navigator.pop(context);
              },
              child: Text('Bookmark'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegTile extends StatelessWidget {
  final BahnLeg leg;

  const _LegTile({required this.leg});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(Icons.train, size: 20),
      title: Text(
        '${leg.lineName} → ${leg.direction}',
        style: TextStyle(fontSize: 13),
      ),
      subtitle: Text(
        '${leg.origin.name} ${DateFormat('HH:mm').format(leg.plannedDeparture)} Gl.${leg.platformDisplay}\n'
        '→ ${leg.destination.name} ${DateFormat('HH:mm').format(leg.plannedArrival)}',
        style: TextStyle(fontSize: 12),
      ),
    );
  }
}

class _BookmarksTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final controller = Get.find<BahnController>();

    return Obx(() {
      final active = controller.activeBookmarks;
      final upcoming = controller.upcomingBookmarks;
      final completed = controller.completedBookmarks;

      if (active.isEmpty && upcoming.isEmpty && completed.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.bookmark_border, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'No bookmarks yet',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
              SizedBox(height: 8),
              Text(
                'Search for connections and bookmark them',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        );
      }

      return ListView(
        padding: EdgeInsets.all(16),
        children: [
          if (active.isNotEmpty) ...[
            _SectionHeader(title: 'Active Now', count: active.length, color: Colors.green),
            ...active.map((b) => _BookmarkCard(bookmark: b)),
            SizedBox(height: 16),
          ],
          if (upcoming.isNotEmpty) ...[
            _SectionHeader(title: 'Upcoming', count: upcoming.length, color: Colors.blue),
            ...upcoming.map((b) => _BookmarkCard(bookmark: b)),
            SizedBox(height: 16),
          ],
          if (completed.isNotEmpty) ...[
            _SectionHeader(title: 'Completed', count: completed.length, color: Colors.grey),
            ...completed.map((b) => _BookmarkCard(bookmark: b)),
          ],
        ],
      );
    });
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final Color color;

  const _SectionHeader({
    required this.title,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            color: color,
          ),
          SizedBox(width: 8),
          Text(
            '$title ($count)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _BookmarkCard extends StatelessWidget {
  final BookmarkedJourney bookmark;

  const _BookmarkCard({required this.bookmark});

  @override
  Widget build(BuildContext context) {
    final journey = bookmark.journey;
    final controller = Get.find<BahnController>();

    return Card(
      margin: EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(Icons.train, color: Colors.blue),
        title: Text(
          '${journey.trainName}: ${journey.origin.name} → ${journey.destination.name}',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Departure: ${DateFormat('MMM d, HH:mm').format(journey.plannedDeparture)}',
              style: TextStyle(fontSize: 12),
            ),
            Text(
              'Slot ${bookmark.dashboardSlot} • ${bookmark.displayTiming.label}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        trailing: PopupMenuButton(
          itemBuilder: (context) => [
            PopupMenuItem(
              child: Text('Edit Settings'),
              value: 'edit',
            ),
            PopupMenuItem(
              child: Text('Delete', style: TextStyle(color: Colors.red)),
              value: 'delete',
            ),
          ],
          onSelected: (value) {
            if (value == 'delete') {
              controller.removeBookmark(bookmark.id);
            } else if (value == 'edit') {
              _showEditDialog(context, bookmark, controller);
            }
          },
        ),
      ),
    );
  }

  void _showEditDialog(
    BuildContext context,
    BookmarkedJourney bookmark,
    BahnController controller,
  ) {
    int selectedSlot = bookmark.dashboardSlot;
    BahnDisplayTiming selectedTiming = bookmark.displayTiming;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Edit Bookmark'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Dashboard Slot', style: TextStyle(fontWeight: FontWeight.bold)),
              DropdownButton<int>(
                value: selectedSlot,
                isExpanded: true,
                items: [1, 2, 3, 4].map((slot) {
                  return DropdownMenuItem(
                    value: slot,
                    child: Text('Slot $slot'),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) setState(() => selectedSlot = value);
                },
              ),
              SizedBox(height: 8),
              Text('Display Timing', style: TextStyle(fontWeight: FontWeight.bold)),
              ...BahnDisplayTiming.values.map((timing) {
                return RadioListTile<BahnDisplayTiming>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(timing.label),
                  value: timing,
                  groupValue: selectedTiming,
                  onChanged: (value) {
                    if (value != null) setState(() => selectedTiming = value);
                  },
                );
              }).toList(),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                controller.updateBookmarkSettings(
                  bookmark.id,
                  slot: selectedSlot,
                  timing: selectedTiming,
                );
                Navigator.pop(context);
              },
              child: Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final controller = Get.find<BahnController>();

    return ListView(
      padding: EdgeInsets.all(16),
      children: [
        Text(
          'Default Settings',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(
          'These settings will be used when bookmarking new journeys',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        SizedBox(height: 16),
        Text('Default Dashboard Slot', style: TextStyle(fontWeight: FontWeight.bold)),
        SizedBox(height: 8),
        Obx(() => DropdownButton<int>(
              value: controller.defaultSlot.value,
              isExpanded: true,
              items: [1, 2, 3, 4].map((slot) {
                return DropdownMenuItem(
                  value: slot,
                  child: Text('Slot $slot${slot == 2 ? ' (Recommended)' : ''}${slot == 1 ? ' (used by timed notes)' : ''}'),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) controller.setDefaultSlot(value);
              },
            )),
        SizedBox(height: 16),
        Text('Default Display Timing', style: TextStyle(fontWeight: FontWeight.bold)),
        SizedBox(height: 8),
        Obx(() => Column(
              children: BahnDisplayTiming.values.map((timing) {
                return RadioListTile<BahnDisplayTiming>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(timing.label),
                  value: timing,
                  groupValue: controller.defaultTiming.value,
                  onChanged: (value) {
                    if (value != null) controller.setDefaultTiming(value);
                  },
                );
              }).toList(),
            )),
        SizedBox(height: 24),
        Divider(),
        SizedBox(height: 16),
        Text(
          'Smart Refresh',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 8),
        Text(
          'Real-time updates are fetched automatically:\n\n'
          '• >2 hours before: every 10 minutes\n'
          '• 30min-2h before: every 5 minutes\n'
          '• <30min or during travel: every 2 minutes\n'
          '• After arrival: auto-cleanup',
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
      ],
    );
  }
}
