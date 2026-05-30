import 'package:flutter/material.dart';
import 'plugin_context.dart';

abstract class YourSSHPlugin {
  /// Reverse-domain unique ID, e.g. "dev.yourssh.devops"
  String get id;
  String get name;
  String get description;
  IconData get icon;
  String get version;

  /// The minimum `yourssh_plugin_api` version this plugin requires.
  /// Format: semantic version `MAJOR.MINOR.PATCH` — no leading `v`,
  /// no pre-release or build suffixes. Example: `"1.0.0"`.
  String get minApiVersion;

  /// Builds the UI for this plugin.
  ///
  /// Called by the host whenever this plugin's panel needs to be rendered.
  /// May be called many times — do not perform side effects or expensive
  /// initialization here. Use [onActivate] for one-time setup.
  Widget buildUI(BuildContext context, YourSSHPluginContext pluginContext);

  /// Called once before the first [buildUI], with the context that will be
  /// passed to [buildUI] during this activation. Use for one-time setup.
  void onActivate(YourSSHPluginContext ctx) {}

  /// Called once when the plugin is disabled. The context passed to
  /// [onActivate] must not be used after this point.
  void onDeactivate() {}
}
