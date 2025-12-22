import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../../controllers/bahn_controller.dart';

class BahnDashboardTile extends StatelessWidget {
  const BahnDashboardTile({super.key});

  @override
  Widget build(BuildContext context) {
    // Try to find controller, return empty widget if not available
    try {
      Get.find<BahnController>();
    } catch (e) {
      // Controller not initialized yet
      return SizedBox.shrink();
    }

    return GetBuilder<BahnController>(
      builder: (controller) {
        final upcoming = controller.upcomingBookmarks;
        final active = controller.activeBookmarks;

        return Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.train, color: Colors.blue, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Train Timetable',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  _StatusBadge(activeCount: active.length),
                ],
              ),
              SizedBox(height: 12),

              // Content
              if (upcoming.isEmpty && active.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No upcoming journeys',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                )
              else
                ..._buildJourneyList(upcoming, active),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildJourneyList(List upcoming, List active) {
    // Show active first, then upcoming (max 3 total)
    final combined = [...active, ...upcoming].take(3).toList();

    return combined.map((bookmark) {
      final journey = bookmark.journey;
      final leg = journey.legs.first;
      final isActive = bookmark.isActiveNow(DateTime.now());

      return Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isActive)
                  Container(
                    width: 8,
                    height: 8,
                    margin: EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                Expanded(
                  child: Text(
                    leg.lineName,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 4),
            Text(
              '${leg.origin.name} → ${journey.destination.name}',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: 2),
            Row(
              children: [
                Icon(Icons.schedule, size: 12, color: Colors.grey[600]),
                SizedBox(width: 4),
                Text(
                  _formatDateTime(journey.plannedDeparture),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                if (journey.totalDepartureDelay > 0) ...[
                  SizedBox(width: 8),
                  Text(
                    '+${(journey.totalDepartureDelay / 60).round()}m',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      );
    }).toList();
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(Duration(days: 1));
    final journeyDay = DateTime(dt.year, dt.month, dt.day);

    String dayLabel;
    if (journeyDay == today) {
      dayLabel = 'Today';
    } else if (journeyDay == tomorrow) {
      dayLabel = 'Tomorrow';
    } else {
      dayLabel = DateFormat('MMM d').format(dt);
    }

    final time = DateFormat('HH:mm').format(dt);
    return '$dayLabel $time';
  }
}

class _StatusBadge extends StatelessWidget {
  final int activeCount;

  const _StatusBadge({required this.activeCount});

  @override
  Widget build(BuildContext context) {
    if (activeCount == 0) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'No active',
          style: TextStyle(fontSize: 11, color: Colors.grey[700]),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 4),
          Text(
            '$activeCount active',
            style: TextStyle(fontSize: 11, color: Colors.green[900]),
          ),
        ],
      ),
    );
  }
}
