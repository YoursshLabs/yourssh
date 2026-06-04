import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yourssh/models/app_notification.dart';
import 'package:yourssh/providers/notification_center_provider.dart';
import 'package:yourssh/providers/update_provider.dart';
import 'package:yourssh/theme/app_theme.dart';

/// Bell button at the right end of the top tab bar. Shows an unread badge
/// and toggles an anchored popover listing in-app notifications.
class NotificationBellBtn extends StatefulWidget {
  const NotificationBellBtn({
    super.key,
    this.onShowUpdateDetails,
    this.onOpenSession,
  });

  /// Navigates to the Settings update section (same as the update banner).
  final VoidCallback? onShowUpdateDetails;

  /// Activates the session tab for a disconnect notification.
  final void Function(String sessionId)? onOpenSession;

  @override
  State<NotificationBellBtn> createState() => _NotificationBellBtnState();
}

class _NotificationBellBtnState extends State<NotificationBellBtn> {
  /// Shared TapRegion group: clicking the bell while the panel is open must
  /// not count as "outside" (which would close and immediately re-open it).
  static const _tapGroup = 'notification-bell-popover';

  final _link = LayerLink();
  final _portal = OverlayPortalController();
  bool _hovered = false;

  void _toggle() {
    if (_portal.isShowing) {
      _portal.hide();
    } else {
      // Opening the panel marks everything read — the badge clears.
      context.read<NotificationCenterProvider>().markAllRead();
      _portal.show();
    }
  }

  @override
  Widget build(BuildContext context) {
    final unread =
        context.select<NotificationCenterProvider, int>((p) => p.unreadCount);

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (_) => Positioned(
          width: 320,
          child: CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, 4),
            child: TapRegion(
              groupId: _tapGroup,
              onTapOutside: (_) => _portal.hide(),
              child: _NotificationPanel(
                onShowUpdateDetails: widget.onShowUpdateDetails,
                onOpenSession: widget.onOpenSession,
                onClose: _portal.hide,
              ),
            ),
          ),
        ),
        child: TapRegion(
          groupId: _tapGroup,
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              onTap: _toggle,
              child: Container(
                width: 36,
                height: 38,
                alignment: Alignment.center,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      Icons.notifications_none,
                      size: 16,
                      color: _hovered
                          ? const Color(0xFFAAAAAA)
                          : const Color(0xFF555555),
                    ),
                    if (unread > 0)
                      Positioned(
                        top: -4,
                        right: -6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          constraints: const BoxConstraints(minWidth: 14),
                          decoration: BoxDecoration(
                            color: AppColors.red,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            unread > 9 ? '9+' : '$unread',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
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
      ),
    );
  }
}

class _NotificationPanel extends StatelessWidget {
  const _NotificationPanel({
    required this.onShowUpdateDetails,
    required this.onOpenSession,
    required this.onClose,
  });

  final VoidCallback? onShowUpdateDetails;
  final void Function(String sessionId)? onOpenSession;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationCenterProvider>();
    final items = provider.notifications;

    return Material(
      color: const Color(0xFF1E1E1E),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 420),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 6, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Notifications',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (items.isNotEmpty)
                    TextButton(
                      onPressed: provider.clearAll,
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.textSecondary),
                      child:
                          const Text('Clear all', style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ),
            if (items.isEmpty)
              _buildEmptyState()
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: items.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1, color: AppColors.border),
                  itemBuilder: (context, i) => _NotificationTile(
                    item: items[i],
                    onShowUpdateDetails: onShowUpdateDetails,
                    onOpenSession: onOpenSession,
                    onClose: onClose,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.cardHover,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.notifications,
                size: 20, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 14),
          const Text(
            'No notifications',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.item,
    required this.onShowUpdateDetails,
    required this.onOpenSession,
    required this.onClose,
  });

  final AppNotification item;
  final VoidCallback? onShowUpdateDetails;
  final void Function(String sessionId)? onOpenSession;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final isDisconnect = item.type == AppNotificationType.sessionDisconnect;

    return InkWell(
      onTap: isDisconnect && item.sessionId != null
          ? () {
              onClose();
              onOpenSession?.call(item.sessionId!);
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isDisconnect ? Icons.link_off : Icons.system_update_alt,
              size: 15,
              color: isDisconnect ? AppColors.orange : AppColors.accent,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 12.5)),
                  if (item.body != null && item.body!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.body!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 11.5),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    relativeTime(item.timestamp),
                    style: const TextStyle(
                        color: AppColors.textTertiary, fontSize: 10.5),
                  ),
                  if (item.type == AppNotificationType.update) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        SizedBox(
                          height: 24,
                          child: FilledButton(
                            onPressed: () {
                              onClose();
                              context
                                  .read<UpdateProvider>()
                                  .downloadAndInstall();
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: Colors.black,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              textStyle: const TextStyle(fontSize: 11.5),
                            ),
                            child: const Text('Update'),
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          height: 24,
                          child: TextButton(
                            onPressed: () {
                              onClose();
                              onShowUpdateDetails?.call();
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.textSecondary,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              textStyle: const TextStyle(fontSize: 11.5),
                            ),
                            child: const Text('Details'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "just now", "5m ago", "3h ago", "2d ago".
@visibleForTesting
String relativeTime(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes}m ago';
  if (d.inDays < 1) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}
