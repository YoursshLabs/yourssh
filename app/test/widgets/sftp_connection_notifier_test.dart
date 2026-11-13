import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/theme/app_theme.dart' show ysRootBuilder;
import 'package:yourssh/utils/safe_set_state.dart';
import 'package:yourssh/widgets/dual_panel_sftp_screen.dart';

/// Mirrors MainScreen: listens to the SFTP connection notifier with setState,
/// and swaps the body (as RDP fullscreen does) so the SFTP screen is unmounted.
class _Owner extends StatefulWidget {
  const _Owner(this.notifier);
  final ValueNotifier<bool> notifier;
  @override
  State<_Owner> createState() => _OwnerState();
}

class _OwnerState extends State<_Owner> {
  bool swapped = false;
  void swap() => setState(() => swapped = true);
  @override
  void initState() {
    super.initState();
    widget.notifier.addListener(_changed);
  }

  void _changed() {
    setStateSafely();
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (swapped) return const Scaffold(body: SizedBox());
    return Scaffold(
      body: Column(children: [
        Expanded(child: DualPanelSftpScreen(connectionNotifier: widget.notifier)),
      ]),
    );
  }
}

void main() {
  testWidgets('unmounting a connected SFTP screen does not setState its '
      'owner while the tree is locked', (t) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    final notifier = ValueNotifier<bool>(false);
    addTearDown(notifier.dispose);
    late _OwnerState owner;
    await t.pumpWidget(MultiProvider(
      providers: [
        Provider<SshService>(create: (_) => SshService(storage)),
        ChangeNotifierProvider(create: (_) => HostProvider(storage)),
      ],
      child: MaterialApp(
        builder: ysRootBuilder,
        home: Builder(builder: (c) => _Owner(notifier)),
      ),
    ));
    await t.pump();
    owner = t.state<_OwnerState>(find.byType(_Owner));
    notifier.value = true; // a remote host is connected in the SFTP screen
    await t.pump();

    owner.swap();
    await t.pump();
    expect(t.takeException(), isNull);
  });
}
