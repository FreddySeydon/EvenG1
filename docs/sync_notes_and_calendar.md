Sync cadence for calendar-linked notes and dashboard displays
============================================================

- Calendar refresh: `CalendarController` refreshes events every 10 minutes, on manual refresh, and when auto-send is toggled.
- Linked event polling: `TimeNotesController` polls linked events by `eventId` every ~1 minute (and once on app load) to pick up start/end changes even if the event is outside the current window.
- Active window recompute: active notes are recomputed every ~1 minute and on note/calendar changes; this is when a moved event can deactivate/reactivate its attached note.
- Send to glasses: `TimeNotesScheduler` reacts immediately to active note list changes and also runs a 1-minute safety tick. Worst-case delay from an event time change to a dashboard update is roughly a minute.
- Battery tradeoff: shorter poll/tick intervals would update faster but cost more BLE activity and CPU wakeups. Current intervals favor battery while keeping “event moved” updates reasonably fresh for typical use (future events moved minutes or hours ahead).

Placeholder behavior
--------------------
- When no active or general notes exist, the scheduler shows a placeholder: “No notes yet / Add notes in the app to display them here.”
- World-time mode always continues to refresh even right after a timed note ends; a brief hold is applied only to general/placeholder sends to avoid flicker with just-ended timed notes.

