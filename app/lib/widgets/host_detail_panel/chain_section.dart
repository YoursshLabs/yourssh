part of 'host_detail_panel.dart';

/// CONNECTION CHAIN (SSH only): the multi-hop [HostChainEditor]. Stale hop
/// ids (host deleted while referenced) are pruned after the frame.
class _ChainSection extends StatelessWidget {
  final _HostDetailPanelState form;
  const _ChainSection({required this.form});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [const _SectionLabel('CONNECTION CHAIN'), _editor(context)],
    );
  }

  Widget _editor(BuildContext context) {
    final allHosts = context.watch<HostProvider>().allHosts;
    final existingId = form.widget.existing?.id;
    final otherHosts = allHosts.where((h) => h.id != existingId).toList();
    if (otherHosts.isEmpty) return const SizedBox.shrink();
    // Resolve ids → hosts in order, dropping any that no
    // longer exist (host deleted while referenced).
    final chainHosts = form._jumpHostIds
        .map((id) => otherHosts.where((h) => h.id == id).firstOrNull)
        .whereType<Host>()
        .toList();
    if (chainHosts.length != form._jumpHostIds.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (form.mounted) {
          form._set(
            () => form._jumpHostIds = chainHosts.map((h) => h.id).toList(),
          );
        }
      });
    }
    return ListenableBuilder(
      // Live-update the bottom card while typing label/host.
      listenable: Listenable.merge([
        form._labelCtrl,
        form._usernameCtrl,
        form._hostCtrl,
      ]),
      builder: (context, _) => HostChainEditor(
        currentHostLabel: form._currentHostLabel(),
        currentHostOs: form.widget.existing?.detectedOs,
        chain: chainHosts,
        agentForwarding: form._agentForwarding,
        candidates: otherHosts,
        onChanged: (ids) => form._set(() => form._jumpHostIds = ids),
      ),
    );
  }
}
